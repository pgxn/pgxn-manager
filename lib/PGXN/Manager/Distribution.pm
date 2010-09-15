package PGXN::Manager::Distribution;

use 5.12.0;
use utf8;
use Moose;
use PGXN::Manager;
use Archive::Extract;
use Archive::Zip;
use File::Spec;
use File::Path qw(make_path remove_tree);
use namespace::autoclean;

has upload => (is => 'ro', required => 1, isa => 'Plack::Request::Distribution');
has owner  => (is => 'ro', required => 1, isa => 'Str');
has error  => (is => 'ro', required => 0, isa => 'Str');
has ae     => (is => 'ro', required => 0, isa => 'Archive::Extract');

local $Archive::Extract::PREFER_BIN = 1;
my $TMPDIR = File::Spec->catdir(File::Spec->tmpdir, 'pgxn');

make_path $TMPDIR if !-d $TMPDIR;

sub process {
    my $self = shift;
    # 1. Unpack distro.
    $self->extract;

    # 2. Process its META.json.
    # 3. Zip it up.
    # 4. Send JSON + SHA1 to server.
    # 5. If fail, return with failure.
    # 6. Otherwise, index.
}

sub extract {
    my $self = shift;
    my $ae = Archive::Extract->new(archive => $self->upload->path);
    $ae->extract(to => $TMPDIR);
    $self->ae($ae);
    return $self;
}

sub read_meta {
}

sub zipit {
}

sub register {
}

sub index {
}

sub DEMOLISH {
    my $self = shift;
    if (my $ae = $self->ae) {
        if (my $path = $ae->extract_path) {
            remove_tree $path if -e $path;
        }
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

=head3 C<zipit>

=head3 C<register>

=head3 C<index>

=head1 Author

David E. Wheeler <david.wheeler@pgexperts.com>

=head1 Copyright and License

Copyright (c) 2010 David E. Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.
