package PGXN::Manager;

use 5.10.0;
use utf8;
use MooseX::Singleton;
use Moose::Util::TypeConstraints;
use DBIx::Connector;
use Exception::Class::DBI;
use File::Spec;
use JSON::XS ();
use URI::Template;
use File::Copy qw(move copy);
use File::Path qw(make_path remove_tree);
use File::Basename qw(dirname);
use Email::MIME::Creator;
use Try::Tiny;
use Net::Twitter::Lite::WithAPIv1_1;
use Email::Sender::Simple;
use Encode;
use namespace::autoclean;

our $VERSION = v0.31.0;

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

=head2 Class Method

=head3 C<version_string>

  say 'PGXN::Manager ', PGXN::Manager->version_string;

Returns a string representation of the PGXN::Manager version.

=cut

sub version_string {
    sprintf 'v%vd', $VERSION;
}

=head2 Attributes

=head3 C<config>

  my $config = $pgxn->config;

Returns a hash reference of configuration information. This information is
parsed from the configuration file F<conf/test.json>, which is determined by
the C<--context> option to C<perl Build.PL> at build time.

=cut

has config => (is => 'ro', isa => 'HashRef', default => sub {
    my $fn = 'conf/' . ($ENV{PLACK_ENV} || 'test') . '.json';
    open my $fh, '<:raw', $fn or die "Cannot open $fn: $!\n";
    local $/;
    # XXX Verify presence of required keys.
    JSON::XS->new->decode(<$fh>);
});

=head3 C<conn>

  my $conn = $pgxn->conn;

Returns the database connection for the app. It's a L<DBIx::Connection>, safe
to use pretty much anywhere.

=cut

has conn => (is => 'ro', lazy => 1, isa => 'DBIx::Connector', default => sub {
    $_[0]->_connect;
});

# Utility method for connecting, so that other classes can add parameters. For
# example see Consumer.pm passing callback configuration.
sub _connect {
    my ($self, $params) = @_;
    $params ||= {};
    my $name = $params->{pg_application_name} || 'pgxn_manager';
    my @conn_args = @{ $self->config->{dbi} }{ qw(dsn username password) };
    $conn_args[0] .= ";application_name=$name";

    my $c = DBIx::Connector->new(@conn_args, {
        PrintError        => 0,
        RaiseError        => 0,
        HandleError       => Exception::Class::DBI->handler,
        AutoCommit        => 1,
        pg_enable_utf8    => 1,
        pg_server_prepare => 0,
        %{ $params },
    });
    $c->mode('fixup');
    return $c;
}

=head3 C<uri_templates>

  my $templates = $pgxn->uri_templates;

Returns a hash reference of the URI templates for the various files stored in
the mirror root. The keys are the names of the templates, and the values are
L<URI::Template> objects.

=cut

has uri_templates => (is => 'ro', isa => 'HashRef', lazy => 1, default => sub {
    my $tmpl = shift->config->{uri_templates};
    return { map { $_ => URI::Template->new($tmpl->{$_}) } keys %{ $tmpl } };
});

=head3 C<email_transport>

  Email::Sender::Simple->send($email, {
      transport => PGXN::Manager->email_transport
  });

An Email::Sender::Transport object, constructed from the C<email_transport>
and C<email_transport_params> configuration options. The former is a class
name, such as L<Email::Sender::Transport::SMTP>, while the latter is the
parameters to pass to its constructor. Example configuration:

    "email_transport": "Email::Sender::Transport::SMTP",
    "email_transport_params": {
        "host": "localhost",
        "port": 25
    },

Should be used wherever mail is sent, so that the transport is consistent.

=cut

has email_transport => (
    is     => 'ro',
    isa    => maybe_type(role_type('Email::Sender::Transport')),
    lazy   => 1,
    default => sub {
        my $config = shift->config;
        my $class  = $config->{email_transport} or return;
        eval "require $class" or die $@;
        return $class->new($config->{email_transport_params} || {});
    }
);

=head2 Instance Methods

=head3 C<init_root>

  $pgxn->init_root;

Initializes the PGXN mirror root. If the root directory, specified by the
C<mirror_root> key in the configuration file, does not exist, it will be
created. If the F<index.json> file does not exist, it too will be created and
populated with the contents of the C<uri_templates> section of the
configuration file.

B<Note:> Once the network has gone live and clients are using it, the
F<index.json> file's URI templates must not be modified! Otherwise clients
won't be able to find metadata or distributions uploaded before the
modification. So leave this file alone!

=cut

sub init_root {
    my $self = shift;
    my $root = $self->config->{mirror_root};
    if (!-e $root) {
        require File::Path;
        File::Path::make_path($root);
    }

    # Output the root index.json file.
    my $index = File::Spec->catfile($root, 'index.json');
    if (!-e $index) {
        open my $fh, '>', $index or die qq{Cannot open "$index": $!\n};
        print $fh JSON::XS->new->indent->space_after->canonical->encode(
            $self->config->{uri_templates}
        );
        close $fh or die qq{Cannot close "$index": $!\n};
        chmod 0644, $index;
    }

    # Output the spec.
    my $src = File::Spec->catfile(qw(doc spec.txt));
    my $spec = File::Spec->catfile(
        $root,
        $self->uri_templates->{spec}->process(format => 'txt')->path_segments
    );
    if (!-e $spec || (stat $src)[9] > (stat $spec)[9]) {
        make_path dirname $spec;
        copy $src, $spec or do {
            # D'oh! Move failed. Try to clean up.
            my $err = $!;
            remove_tree $spec;
            die qq{Failed to copy "$src" to "spec": $!\n};
        };
        chmod 0644, $spec;
    }

    return $self;
}

=head3 C<move_file>

  $pgxn->move_file($src, $dest);

Moves a file to a new location. Both arguments must be full file names, not
directories. In the event of an error, C<move_file()> will do its best to
clean up any partially-moved file before throwing an exception. On success,
the file will have its permissions set to 0644.

=cut

sub move_file {
    my ($self, $src, $dest) = @_;
    make_path dirname $dest;
    move $src, $dest or do {
        # D'oh! Move failed. Try to clean up.
        my $err = $!;
        remove_tree $dest;
        die qq{Failed to move "$src" to "dest": $!\n};
    };
    chmod 0644, $dest;
}

=head3 C<send_email>

    $pgxn->send_email({
        to      => $to,
        from    => $from,
        subject => $subject,
        body    => $body,
    });

Send an email. All four parameters are required.

=cut

# XXX Fork this off?
sub send_email {
    my ($self, $p) = @_;
    my $email = Email::MIME->create(
        header     => [
            From    => encode_utf8 $p->{from},
            To      => encode_utf8 $p->{to},
            Subject => encode_utf8 $p->{subject}
        ],
        attributes => {
            content_type => 'text/plain',
            charset      => 'UTF-8',
        },
        body => encode_utf8 $p->{body},
    );

    Email::Sender::Simple->send($email, {
        transport => $self->email_transport
    });
    return $self;
}

__PACKAGE__->meta->make_immutable;

=head1 Author

David E. Wheeler <david@justatheory.com>

=head1 Copyright and License

Copyright (c) 2010-2023 David E. Wheeler.

This module is free software; you can redistribute it and/or modify it under
the L<PostgreSQL License|https://www.opensource.org/licenses/postgresql>.

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
