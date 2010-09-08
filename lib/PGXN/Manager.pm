package PGXN::Manager v0.0.1;

use feature ':5.12';
use utf8;
use MooseX::Singleton;
use DBIx::Connector;
use Exception::Class::DBI;
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

1;

=head1 Author

David E. Wheeler <david.wheeler@pgexperts.com>

=head1 Copyright and License

Copyright (c) 2010 David E. Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
