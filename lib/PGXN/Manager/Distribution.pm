package PGXN::Manager::Distribution;

use 5.12.0;
use utf8;
use Moose;
use PGXN::Manager;
use PGXN::Manager::Locale;
use Archive::Extract;
use Archive::Zip qw(:ERROR_CODES);
use File::Basename qw(dirname);
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

has archive  => (is => 'ro', required => 1, isa => 'Str');
has basename => (is => 'ro', required => 1, isa => 'Str');
has owner    => (is => 'ro', required => 1, isa => 'Str');
has error    => (is => 'rw', required => 0, isa => 'ArrayRef', auto_deref => 1);
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

    # Set up the working directory.
    my $workdir = $self->workdir;
    remove_tree $workdir if -e $workdir;
    make_path $workdir;

    # If upload extension matches dist template suffix, it's a Zip file.
    my ($ext) = lc($self->basename) =~ /([.][^.]+)$/;
    try {
        if ($ext =~ $EXT_RE) {
            # It's a zip acrhive.
            my $zip = Archive::Zip->new;
            $zip->read($self->archive);
            $self->zip($zip);
        } else {
            # It's something else. Extract it and then zip it up.
            my $ae = do {
                my $extract_dir = File::Spec->catdir($workdir, 'source');
                local $Archive::Extract::WARN = 1;
                local $Archive::Extract::PREFER_BIN = 1;
                # local $Archive::Extract::DEBUG = 1;
                local $SIG{__WARN__} = \&_ae_error_handler;
                my $ae = Archive::Extract->new(archive => $self->archive);
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
        die $_ unless ref $_ eq 'ARRAY';
        $self->error([@{ $_ }, $self->basename]);
        return;
    };
    return $self;
}

sub read_meta {
    my $self    = shift;
    my $zip     = $self->zip;

    my ($member) = $zip->membersMatching($META_RE);
    unless ($member) {
        $self->error([
            'Cannot find a “[_1]” in “[_2]”', 'META.json', $self->basename
        ]);
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
        $self->error([
            'Cannot parse JSON from “[_1]”: [_2]',
            $member->fileName,
            $err
        ]);
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
        $self->error([
            '“[_1]” is missing the required [numerate,_2,key] [qlist,_3]',
            $self->metamemb->fileName,
            scalar @missing,
            \@missing,
        ]);
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
    $self->_update_meta if $meta_modified;

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

sub _update_meta {
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
        $self->zipfile($self->archive);
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
        $self->error(['Error writing new zip file']);
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
    }, sub {
        die $_ if $_->state ne 'P0001' && $_->state ne 'XX000';
        (my $err = $_->errstr) =~ s/^[[:upper:]]+:\s+//;
        my @params;
        my $i = 0;
        $err =~ s{“([^”]+)”}{
            push @params => $1;
            '“[_' . ++$i . ']”';
        }gesm;
        $self->error([$err, @params]);
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
        print $fh scalar $readme->contents;
        close $fh or die "Cannot close $fn: $!\n";
        $files{$fn} = File::Spec->catfile($root, $uri->path_segments);
    }

    # Move the archive to the mirror root.
    my $uri  = $templates->{dist}->process(@vars);
    PGXN::Manager->move_file(
        $self->zipfile,
        File::Spec->catfile($root, $uri->path_segments)
    );

    # Move all the other files over.
    while (my ($src, $dest) = each %files) {
        PGXN::Manager->move_file($src, $dest);
    }

    return $self;
}

sub localized_error {
    PGXN::Manager::Locale->get_handle->maketext(shift->error);
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
            die ['“[_1]” doesn’t look like a distribution archive'];
        }
        default { die [$_] }
    }
}

my $CWD = cwd;
sub _ae_error_handler {
    chdir $CWD; # Go back to where we belong.
    die ['“[_1]” doesn’t look like a distribution archive'];
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

=head1 Name

PGXN::Manager::Distribution - Manages distributions uploaded to PGXN.

=head1 Synopsis

  use PGXN::Manager::Distribution;
  my $dist = PGXN::Manager::Distribution->new(
      archive  => $path_to_archive_file,
      basename => File::Spec->basename($path_to_archive_file),
      owner    => $nickname,
  );
  die "Distribution failure: ", $dist->error unless $dist->process;

=head1 Description

This class provides the interface for managing distribution archives uploaded
to PGXN. Its interface is quite simple, really. Give it a path to an archive
file and the nickname of the user uploading it and call C<process()> and it
will do the rest.

User-visible exceptions will be caught and stored in the C<error> attribute.
If C<process> returns false, you'll want to display the contents of this
attribute to users.

System exceptions will not be caught; the caller needs to handle them. For
the app, they should simply be logged and a generic error page returned to
the user.q

=head1 Interface

=head2 Constructor

=head3 C<new>

  my $dist = PGXN::Manager::Distribution->new(
      archive  => $path_to_archive_file,
      basename => File::Spec->basename($path_to_archive_file),
      owner    => $nickname,
  );

Creates a new distribution object. The supported parameters are:

=over

=item C<archive>

The path to a an archive file. The format of this archive can be anything
supported by L<Archive::Extract>, although Zip files are preferred (because
then we might not have to repack them).

=item C<basename>

The base file name of the archive.

=item C<owner>

The nickname of the user uploading the distribution.

=back

=head2 Instance Attributes

=head3 C<archive>

  my $archive = $dist->archive;

The path to the uploaded distribution archive file.

=head3 C<basename>

  my $basename = $dist->basename;

The base name of the archive file.

=head3 C<owner>

  my $owner = $dist->owner;

The nickname of the user uploading the distribution archive.

=head3 C<error>

  $dist->process or die PGXN::Manager::Locale->get_handle($dist->error);

User-visible error message formatted as an array suitable for passing to
L<PGXN::Manager::Locale> for localization. Returns the error as an array
reference in scalar context and as a list in list context. Be sure to check
this attribute if C<process()> returns false.

=head2 Instance Methods

=head3 C<process>

  $dist->process or die $dist->localized_error;

Processes the distribution, indexes it, and updates the mirror root as
appropriate. This is really just a bit of sugar so you don't have to call all
the processing methods yourself. It simply calls the following methods and
returns false if any of them returns false:

=over

=item C<extract>

=item C<read_meta>

=item C<normalize>

=item C<zipit>

=item C<indexit>

See below for what each of these methods actually does, though you will likely
never call them directly.

=back

=head3 C<extract>

  $dist->extract or die $dist->localized_error;

If the archive is a zip file, this method loads it up into an L<Archive::Zip>
object, although it doesn't extract it.

If the archive is not a zip file, this method extracts it into a temporary
directory and then loads it into an L<Archive::Zip> object.

In the event of an error, C<extract> stores the error message in C<error> and
returns false.

=head3 C<read_meta>

  $dist->read_meta or die $dist->localized_error;

Loads and parses the archive's C<META.json> file. If the file does not exist
or cannot be parsed, C<read_meta> stores an error message in C<erro> and
returns false.

=head3 C<normalize>

  $dist->normalize or die $dist->localized_error;

Examines the metadata loaded by C<read_meta>. If any required keys are
missing, it says so in C<error> and returns false. Otherwise, it parses all of
the version numbers in the metadata and attempts to normalize any that are not
valid semantic versions using the L<C<< SemVer->declare >>|SemVer/declare>.

And finally, it examines the directory prefix of the archive. If it is not
equal to C<$dist_name-$dist_version>, it will be rewritten as such.

=head3 C<zipit>

  $dist->zipit or die $dist->localized_error;

Zips the archive up into a new zip file. If the original archive was already
a zip file and the C<normalize> method made no modifications, a new zip
file will not be written, but the original one will be used.

=head3 C<indexit>

  $dist->indexit or die $dist->localized_error;

Indexes the distribution archive and places it in the mirror root. All
necessary F<.json> files will be written to the mirror, as well, as will the
F<README>, if one exists.

Most of this metadata content is generated by the database
C<add_distribution()> function. This function also performs validation of the
distribution, such as ensuring that the user is a valid owner of the
extensions in the distribution. In the event that such validation fails, an
error message will be stored in C<error> as usual and C<indexit()> will return
false.

=head3 C<localized_error>

  $dist->process or die $dist->localized_error;

Convenience method that localizes an error. Basically just:

 PGXN::Manager::Locale->get_handle( shift->error );

=head1 Author

David E. Wheeler <david.wheeler@pgexperts.com>

=head1 Copyright and License

Copyright (c) 2010 David E. Wheeler.

This module is free software; you can redistribute it and/or modify it under
the L<PostgreSQL License|http://www.opensource.org/licenses/postgresql>.

Permission to use, copy, modify, and distribute this software and its
documentation for any purpose, without fee, and without a written agreement is
hereby granted, provided that the above copyright notice and this paragraph
and the following two paragraphs appear in all copies.

In no event shall David E. Wheeler be liable to any party for direct,
indirect, special, incidental, or consequential damages, including lost
profits, arising out of the use of this software and its documentation, even
if David E. Wheeler has been advised of the possibility of such damage.

David E. Wheeler specifically disclaims any warranties, including, but not
limited to, the implied warranties of merchantability and fitness for a
particular purpose. The software provided hereunder is on an "as is" basis,
and David E. Wheeler has no obligations to provide maintenance, support,
updates, enhancements, or modifications.

=cut
