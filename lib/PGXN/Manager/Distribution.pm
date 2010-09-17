package PGXN::Manager::Distribution;

use 5.12.0;
use utf8;
use Moose;
use PGXN::Manager;
use Archive::Extract;
use Archive::Zip qw(:ERROR_CODES);
use File::Spec;
use Try::Tiny;
use File::Path qw(make_path remove_tree);
use Cwd;
use JSON::XS;
use SemVer;
use namespace::autoclean;

has upload   => (is => 'ro', required => 1, isa => 'Plack::Request::Upload');
has owner    => (is => 'ro', required => 1, isa => 'Str');
has error    => (is => 'rw', required => 0, isa => 'Str');
has zip      => (is => 'rw', required => 0, isa => 'Archive::Zip');
has deldir   => (is => 'rw', required => 0, isa => 'Str');
has metamemb => (is => 'rw', required => 0, isa => 'Archive::Zip::FileMember');
has distmeta => (is => 'rw', required => 0, isa => 'HashRef');
has modified => (is => 'rw', required => 0, isa => 'Bool', default => 0);

my $TMPDIR = File::Spec->catdir(File::Spec->tmpdir, 'pgxn');
my $EXT_RE = do {
    my ($ext) = lc(PGXN::Manager->config->{uri_templates}{dist}) =~ /[.]([^.]+)$/;
    qr/[.](?:$ext|zip)$/
};
my $META_RE = qr/\bMETA[.]json$/;

make_path $TMPDIR if !-d $TMPDIR;
Archive::Zip::setErrorHandler(\&_zip_error_handler);

sub process {
    my $self = shift;

    # 1. Unpack distro.
    $self->extract or return;

    # 2. Process its META.json.
    $self->read_meta or return;

    # 3. Normalize it.
    $self->normalize;

    # 4. Zip it up.
    # 5. Send JSON + SHA1 to server.
    # 6. Index it.

}

sub extract {
    my $self   = shift;
    my $upload = $self->upload;

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
                local $Archive::Extract::WARN = 1;
                local $Archive::Extract::PREFER_BIN = 1;
                # local $Archive::Extract::DEBUG = 1;
                local $SIG{__WARN__} = \&_ae_error_handler;
                my $ae = Archive::Extract->new(archive => $upload->path);
                $ae->extract(to => $TMPDIR);
                $ae;
            };

            # Create the zip.
            my $dir = (File::Spec->splitdir($ae->extract_path))[-1];
            my $zip = Archive::Zip->new;
            $zip->addTree($ae->extract_path, $dir);
            $self->zip($zip);
            $self->deldir($ae->extract_path);
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
}

sub register {
}

sub index {
}

sub DEMOLISH {
    my $self = shift;
    if (my $path = $self->delpath) {
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

=head3 <update_meta>

=head3 C<zipit>

=head3 C<register>

=head3 C<index>

=head1 Author

David E. Wheeler <david.wheeler@pgexperts.com>

=head1 Copyright and License

Copyright (c) 2010 David E. Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.
