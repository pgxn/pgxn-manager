package PGXN::Manager::Distribution;

use 5.12.0;
use utf8;
use Moose;
use PGXN::Manager;
use Archive::Extract;
use Archive::Zip qw(:ERROR_CODES);
use File::Basename qw(dirname);
use File::Copy qw(move);
use File::Spec;
use Try::Tiny;
use File::Path qw(make_path remove_tree);
use Cwd;
use JSON::XS;
use SemVer;
use Digest::SHA1 'sha1_hex';
use namespace::autoclean;

my $TMPDIR = PGXN::Manager->new->config->{tmpdir}
          || File::Spec->catdir(File::Spec->tmpdir, 'pgxn');
my $EXT_RE = do {
    my ($ext) = lc(PGXN::Manager->new->config->{uri_templates}{dist}) =~ /[.]([^.]+)$/;
    qr/[.](?:$ext|zip)$/
};
my $META_RE = qr/\bMETA[.]json$/;

make_path $TMPDIR if !-d $TMPDIR;
Archive::Zip::setErrorHandler(\&_zip_error_handler);

has upload   => (is => 'ro', required => 1, isa => 'Plack::Request::Upload');
has owner    => (is => 'ro', required => 1, isa => 'Str');
has error    => (is => 'rw', required => 0, isa => 'Str');
has zip      => (is => 'rw', required => 0, isa => 'Archive::Zip');
has metamemb => (is => 'rw', required => 0, isa => 'Archive::Zip::FileMember');
has distmeta => (is => 'rw', required => 0, isa => 'HashRef');
has modified => (is => 'rw', required => 0, isa => 'Bool', default => 0);
has zipfile  => (is => 'rw', required => 0, isa => 'Str');
has sha1     => (is => 'rw', required => 0, isa => 'Str');
has workdir  => (is => 'rw', required => 0, isa => 'Str', default => sub {
    File::Spec->catdir($TMPDIR, "working.$$")
});

sub process {
    my $self = shift;

    # 1. Unpack distro.
    $self->extract or return;

    # 2. Process its META.json.
    $self->read_meta or return;

    # 3. Normalize it.
    $self->normalize or return;

    # 4. Zip it up.
    $self->zipit or return;

    # 5. Send JSON + SHA1 to server and index it.
    $self->indexit or return;
}

sub extract {
    my $self   = shift;
    my $upload = $self->upload;

    # Set up the working directory.
    my $workdir = $self->workdir;
    remove_tree $workdir if -e $workdir;
    make_path $workdir;

    # If upload extension matches dist template suffix, it's a Zip file.
    my ($ext) = lc($upload->basename) =~ /([.][^.]+)$/;
    try {
        if ($ext =~ $EXT_RE) {
            # It's a zip acrhive.
            my $zip = Archive::Zip->new;
            $zip->read($upload->path);
            $self->zip($zip);
        } else {
            # It's something else. Extract it and then zip it up.
            my $ae = do {
                my $extract_dir = File::Spec->catdir($workdir, 'source');
                local $Archive::Extract::WARN = 1;
                local $Archive::Extract::PREFER_BIN = 1;
                # local $Archive::Extract::DEBUG = 1;
                local $SIG{__WARN__} = \&_ae_error_handler;
                my $ae = Archive::Extract->new(archive => $upload->path);
                $ae->extract(to => $extract_dir);
                $ae;
            };

            # Create the zip.
            my $dir = (File::Spec->splitdir($ae->extract_path))[-1];
            my $zip = Archive::Zip->new;
            $zip->addTree($ae->extract_path, $dir);
            $self->zip($zip);
            $self->modified(1);
        }
    } catch {
        $self->error(ref $_ eq 'ARRAY' ? sprintf $_->[0], $upload->basename : $_);
        return;
    };
    return $self;
}

sub read_meta {
    my $self    = shift;
    my $zip     = $self->zip;

    my ($member) = $zip->membersMatching($META_RE);
    unless ($member) {
        $self->error('Cannot find a META.json in ' . $self->upload->basename);
        return;
    }

    # Cache the member.
    $self->metamemb($member);

    # Process the JSON.
    try {
        $self->distmeta(decode_json scalar $member->contents );
    } catch {
        my $f = quotemeta __FILE__;
        (my $err = $_) =~ s/\s+at\s+$f.+//ms;
        $self->error('Cannot parse JSON from ' . $member->fileName . ": $err");
        return;
    } or return;

    return $self;
}

sub normalize {
    my $self = shift;
    my $meta = $self->distmeta;

    # Check required keys.
    if (my @missing = grep { !exists $meta->{$_} } qw(
        name version license maintainer abstract
    )) {
        my $pl = @missing > 1 ? 's' : '';
        my $keys = join '", "', @missing;
        $self->error(qq{META.json is missing the required "$keys" key$pl});
        return;
    }

    my $meta_modified = 0;
    # Does the version need normalizing?
    my $normal = SemVer->declare($meta->{version})->normal;
    if ($normal ne $meta->{version}) {
        $meta->{version} = $normal;
        $self->modified($meta_modified = 1);
    }

    # Do the "prereq" versions need normalizing?
    if (my $prereqs = $meta->{prereqs}) {
        for my $phase (values %{ $prereqs }) {
            for my $type ( values %{ $phase }) {
                for my $prereq (keys %{ $type }) {
                    my $v = $type->{$prereq} or next; # 0 is valid.
                    my $norm = SemVer->declare($type->{$prereq})->normal;
                    next if $norm eq $v;
                    $type->{$prereq} = $norm;
                    $self->modified($meta_modified = 1);
                }
            }
        }
    }

    # Do the provides versions need normalizing?
    if (my $provides = $meta->{provides}) {
        for my $ext (values %{ $provides }) {
            my $norm = SemVer->declare($ext->{version})->normal;
            next if $norm eq $ext->{version};
            $ext->{version} = $norm;
            $self->modified($meta_modified = 1);
        }
    }

    # Rewrite JSON if distmeta is modified.
    $self->update_meta if $meta_modified;

    # Is the prefix right?
    (my $meta_prefix = $self->metamemb->fileName) =~ s{/$META_RE}{};
    $meta_prefix //= '';

    my $prefix = "$meta->{name}-$meta->{version}";
    if ($meta_prefix ne $prefix) {
        # Rename all members.
        my $old = quotemeta $meta_prefix;
        for my $mem ($self->zip->members) {
            (my $name = $mem->fileName) =~ s/\A$old/$prefix/;
            $mem->fileName($name);
        }
        $self->modified(1);
    }

    return $self;
}

sub update_meta {
    # Abstract to a CPAN module (and use it in setup_meta() db function, too).
    my $self = shift;
    my $mem  = $self->metamemb;
    my $meta = $self->distmeta;
    $meta->{generated_by} = 'PGXN::Manager ' . PGXN::Manager->VERSION;
    my $encoder = JSON::XS->new->space_after->allow_nonref->indent->canonical;
    $mem->contents( "{\n   " . join(",\n   ", map {
        $encoder->indent( $_ ne 'tags');
        my $v = $encoder->encode($meta->{$_});
        chomp $v;
        $v =~ s/^(?![[{])/   /gm if ref $meta->{$_} && $_ ne 'tags';
        qq{"$_": $v}
    } grep {
        defined $meta->{$_}
    } qw(
        name abstract description version maintainer release_status owner sha1
        license prereqs provides tags resources generated_by no_index
        meta-spec
    )) . "\n}\n");
    return $self;
}

sub zipit {
    my $self = shift;

    my $dest = File::Spec->catdir($self->workdir, 'dest');
    make_path $dest;

    unless ($self->modified) {
        # We can just use the uploaded zip file as-is.
        $self->zipfile($self->upload->path);
        return $self;
    }

    my $meta = $self->distmeta;
    my $zipfile = File::Spec->catfile(
        $dest, "$meta->{name}-$meta->{version}.zip"
    );

    try {
        $self->zip->writeToFileNamed($zipfile);
        $self->zipfile($zipfile);
        return $self;
    } catch {
        $self->error("Error writing new zip file");
        return;
    } or return;
}

after zipfile => sub {
    my $self = shift;
    my $zf = shift or return;
    open my $fh, '<', $zf or die "Cannot open $zf: $!\n";
    my $sha1 = Digest::SHA1->new;
    $sha1->addfile($fh);
    $self->sha1($sha1->hexdigest);
    close $fh or die "Cannot close $zf: $!\n";
    return $self;
};

sub indexit {
    my $self      = shift;
    my $root      = PGXN::Manager->config->{mirror_root};
    my $templates = PGXN::Manager->uri_templates;
    my $meta      = $self->distmeta;
    my $destdir   = File::Spec->catdir($self->workdir, 'dest');
    my @vars      = ( dist => $meta->{name}, version => $meta->{version} );
    my %files;

    PGXN::Manager->conn->run(sub {
        my $sth = $_->prepare('SELECT * FROM add_distribution(?, ?, ?)');
        $sth->execute(
            $self->owner,
            $self->sha1,
            scalar $self->metamemb->contents,
        );
        $sth->bind_columns(\my ($template_name, $subject, $json));

        while ($sth->fetch) {
            my $tmpl  = $templates->{$template_name}
                or die "No $template_name templae found in config\n";

            my ($key) = $template_name =~ /by-(.+)/;
            my $uri   = $tmpl->process(@vars, $key || 'dist' => $subject);
            my $fn    = File::Spec->catfile($destdir, $uri->path_segments);

            make_path dirname $fn;
            open my $fh, '>', $fn or die "Cannot open $fn: $!\n";
            print $fh $json;
            close $fh or die "Cannot close $fn: $!\n";

            $files{$fn} = File::Spec->catfile($root, $uri->path_segments);
        }

        return $self;
    }, catch {
        $self->error($_);
        return;
    }) or return;

    # Copy the README.
    my $prefix = quotemeta "$meta->{name}-$meta->{version}";
    my ($readme) = $self->zip->membersMatching(
        qr{^$prefix/README(?:[.][^.]+)?$}
    );
    if ($readme) {
        my $uri = $templates->{readme}->process(@vars);
        my $fn = File::Spec->catfile($destdir, $uri->path_segments);
        open my $fh, '>', $fn or die "Cannot open $fn: $!\n";
        print $fh $readme->contents;
        close $fh or die "Cannot close $fn: $!\n";
        $files{$fn} = File::Spec->catfile($root, $uri->path_segments);
    }

    # Move the archive to the mirror root.
    my $uri  = $templates->{dist}->process(@vars);
    _mv($self->zipfile, File::Spec->catfile($root, $uri->path_segments));

    # Move all the other files over.
    while (my ($src, $dest) = each %files) {
        _mv($src, $dest);
    }

    return $self;
}

sub _mv {
    my ($src, $dest) = @_;
    make_path dirname $dest;
    move $src, $dest and return;

    # D'oh! Move failed. Try to clean up.
    my $err = $!;
    remove_tree $dest;
    die qq{Failed to move "$src" to "dest": $!\n};
}

sub DEMOLISH {
    my $self = shift;
    if (my $path = $self->workdir) {
        remove_tree $path if -e $path;
    }
}

sub _zip_error_handler {
    given (shift) {
        when (/format error: can't find EOCD signature/) {
            die ['%s doesn’t look like a distribution archive'];
        }
        default { die [$_] }
    }
}

my $CWD = cwd;
sub _ae_error_handler {
    chdir $CWD; # Go back to where we belong.
    given (shift) {
        when (/(?:Cannot determine file type|Unrecognized archive format)/) {
            die ['%s doesn’t look like a distribution archive'];
        }
        default { die [$_] }
    }
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

=head1 Name

PGXN::Manager::Distribution - Manages distributions uploaded to PGXN.

=head1 Synopsis

  use PGXN::Manager::Distribution;
  my $upload = PGXN::Manager::Distribution->new(
      upload => $req->uploads->{distribution}
      owner  => $nickname,
  );
  die "Distribution failure: ", $upload->error unless $upload->is_success;

=head1 Description

This class provides the interface for managing distribution uploads to PGXN.

=head1 Interface

The interface inherits from L<Locale::Maketext> and adds the following
method.

=head2 Constructors

=head3 C<new>

  my $upload = PGXN::Manager::Distribution->new(
      upload => $req->uploads->{distribution}
      owner  => $nickname,
  );

Creates a new uploader object, doing all the work of the upload.

=head2 Instance Methods

=head3 C<process>

=head3 C<extract>

  $upload->extract;

Extracts the archive into a temporary directory. This directory will be
removed when the uploader object is garbage-collected.

=head3 C<read_meta>

=head3 C<normalize>

=head3 C<update_meta>

=head3 C<zipit>

=head3 C<register>

=head3 C<indexit>

=head1 Author

David E. Wheeler <david.wheeler@pgexperts.com>

=head1 Copyright and License

Copyright (c) 2010 David E. Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.
