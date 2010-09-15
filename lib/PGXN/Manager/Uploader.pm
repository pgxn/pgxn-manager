package PGXN::Manager::Uploader;

use 5.12.0;
use utf8;
use Moose;
use PGXN::Manager;
use Archive::Extract;
use Archive::Zip;
use File::Spec;
use File::Path qw(make_path remove_tree);
use namespace::autoclean;

has upload => (is => 'ro', isa => 'Plack::Request::Upload');
has error  => (is => 'ro', isa => 'Str' );
has ae     => (is => 'ro', isa => 'Archive::Extract');

local $Archive::Extract::PREFER_BIN = 1;
my $TMPDIR = File::Spec->catdir(File::Spec->tmpdir, 'pgxn');

make_path $TMPDIR if !-d $TMPDIR;

around BUILDARGS => sub {
    my $orig  = shift;
    my $class = shift;
    return $class->$orig(upload => $_[0]) if @_ == 1 && ! ref $_[0];
    return $class->$orig(@_);
};

sub BUILD {
    my $self = shift;
    # 1. Unpack distro.
    $self->extract;

    # 2. Process its META.json.
    # 3. Zip it up.
    # 4. Seed JSON + SHA1 to server.
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

PGXN::Manager::Uploader - Manages distributions uploaded to PGXN.

=head1 Synopsis

  use PGXN::Manager::Uploader;
  my $upload = PGXN::Manager::Uploader->new($archive_file_name);
  die "Upload failure: ", $upload->error unless $upload->is_success;

=head1 Description

This class provides the interface for managing uploads to PGXN.

=head1 Interface

The interface inherits from L<Locale::Maketext> and adds the following
method.

=head2 Constructors

=head3 C<new>

  my $upload = PGXN::Manager::Uploader->new($archive_file_name);

Creates a new uploader object, doing all the work of the upload.

=head2 Instance Methods

=head3 C<extract>

  $upload->extract;

Extracts the archive into a temporary directory. This directory will be
removed when the uploader object is garbage-collected.

=head1 Author

David E. Wheeler <david.wheeler@pgexperts.com>

=head1 Copyright and License

Copyright (c) 2010 David E. Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.
