package PGXN::Manager v0.0.1;

use 5.12.0;
use utf8;
use MooseX::Singleton;
use DBIx::Connector;
use Exception::Class::DBI;
use File::Spec;
use JSON::XS ();

=head1 Name

PGXN::Manager - Interface for managing extensions on PGXN

=head1 Synopsis

  use PGXN::Manager;
  my $pgxn = PGXN::Manager->instance;

=head1 Description

This application provides a Web interface and REST API for extension owners to
upload and manage extensions on PGXN. It also provides an administrative
interface for PGXN administrators.

This class is implemented as a singleton. the C<instance> method will always
return the same object. This is to make it easy and efficient to access global
configuration data and the database connection from anywhere in the app.

=head1 Interface

=head2 Constructor

=head3 C<instance>

  my $app = PGXN::Manager->instance;

Returns the singleton instance of PGXN::Manager. This is the recommended way
to get the PGXN::Manager object.

=head2 Attributes

=head3 C<config>

  my $config = $pgxn->config;

Returns a hash reference of configuration information. This information is
parsed from the configuration file F<conf/test.json>, which is determined by
the C<--context> option to C<perl Build.PL> at build time.

=cut

has config => (is => 'ro', isa => 'HashRef', default => sub {
    my $fn = 'conf/test.json';
    open my $fh, '<', $fn or die "Cannot open $fn: $!\n";
    local $/;
    JSON::XS->new->decode(<$fh>);
});

=head3 C<conn>

  my $conn = $pgxn->conn;

Returns the database connection for the app. It's a L<DBIx::Connection>, safe
to use pretty much anywhere.

=cut

has conn => (is => 'ro', lazy => 1, isa => 'DBIx::Connector', default => sub {
    DBIx::Connector->new( @{ shift->config->{dbi} }{qw(dsn username password)}, {
        PrintError     => 0,
        RaiseError     => 0,
        HandleError    => Exception::Class::DBI->handler,
        AutoCommit     => 1,
        pg_enable_utf8 => 1,
    });
});

=head2 Instance Methods

=head3 C<init_root>

  $pgxn->init_root;

Initializes the PGXN mirror root. If the root directory, specified by the
C<mirror_root> key in the configuration file, does not exist, it will be
created. If the F<index.json> file does not exist, it too will be created and
populated with the contents of the C<uri_templates> section of the
configuration file.

B<Note:> Once the network has gone live and clients are usig it, the
F<index.json> file's URI templates must not be modified! Otherwise clients
won't be able to find metadata or distributions upladed before the
modification. So leave this file alone!

=cut

sub init_root {
    my $self = shift;
    my $root = $self->config->{mirror_root};
    if (!-e $root) {
        require File::Path;
        File::Path::make_path($root);
    }

    my $index = File::Spec->catfile($root, 'index.json');
    if (!-e $index) {
        open my $fh, '>', $index or die qq{Cannot open "$index": $!\n};
        print $fh JSON::XS->new->indent->space_after->canonical->encode(
            $self->config->{uri_templates}
        );
        close $fh or die qq{Cannot close "$index": $!\n};
    }

    return $self;
}

__PACKAGE__->meta->make_immutable;

=head1 Author

David E. Wheeler <david.wheeler@pgexperts.com>

=head1 Copyright and License

Copyright (c) 2010 David E. Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
