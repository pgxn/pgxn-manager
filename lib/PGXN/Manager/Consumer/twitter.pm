package PGXN::Manager::Consumer::twitter;

use 5.10.0;
use utf8;
use Moose;
use Try::Tiny;
use Net::Twitter::Lite::WithAPIv1_1;
use Moose::Util::TypeConstraints;
use Encode qw(encode_utf8);
use strict;
use warnings;
use constant name => 'twitter';
use namespace::autoclean;

our $VERSION = v0.30.1;

subtype MaybeTwitterAPI => as maybe_type class_type 'Net::Twitter::Lite';

has verbose => (is => 'ro', required => 1, isa => 'Int', default => 0);
has client  => (is => 'ro', required => 1, isa => 'Net::Twitter::Lite');

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;

    # Make sure we have the API credentials.
    my $cfg = $args{config} || {};
    my @params = map {
        my $v = $cfg->{$_} or die "Missing Twitter API $_\n"; $_ => $v
    } qw(
        consumer_key
        consumer_secret
        access_token
        access_token_secret
    );

    # Set up the client.
    my $client = Net::Twitter::Lite::WithAPIv1_1->new(
        ssl              => 1,
        legacy_lists_api => 0,
        @params,
    );

    # Continue!
    return $class->$orig(%args, client => $client);
};

sub handle {
    my ($self, $channel, $meta) = @_;
    return unless $channel eq 'release';
    my $client = $self->client or return;
    my $pgxn = PGXN::Manager->instance;

    my $nick = $pgxn->conn->run(sub {
        shift->selectcol_arrayref(
            'SELECT twitter FROM users WHERE nickname = ?',
            undef, $meta->{user}
        )->[0];
    });

    $nick = $nick ? "\@$nick" : $meta->{user};

    my $url = URI::Template->new($pgxn->config->{release_permalink})->process({
        dist    => lc $meta->{name},
        version => lc $meta->{version},
    });
    $client->update( "$meta->{name} $meta->{version} released by $nick: $url" );
}

1;
__END__

=head1 Name

PGXN::Manager::Consumer::twitter - Tweet PGXN Manager events

=head1 Synopsis

Configuration:

  "consumers": [
      {
          "type": "twitter",
          "events": ["release"],
          "consumer_key": "KEY",
          "consumer_secret": "SECRET",
          "access_token": "TOKEN",
          "access_token_secret": "TOKEN SECRET"
      }
  ]

Execution:

  use PGXN::Manager::Consumer;
  PGXN::Manager::Consumer->go;

=head1 Description

This module implements a PGXN event handler to tweet releases. It currently
responds only to C<release> events.

=head1 Class Interface

=head2 Constructor

=head3 C<new>

  my $twitter = PGXN::Manager::Consumer::twitter->new(%params);

Creates and returns a new PGXN::Manager::Consumer::twitter object. The
supported parameters are:

=over

=item C<config>

A hash reference corresponding to the C<consumers/twitter> section of the
configuration file.

=back

=head1 Instance Interface

=head2 Instance Methods

=head3 C<handle>

  $twitter->handle($channel, $payload);

Handles a PGXN Manager event. The first argument is type of the event, and
the second is a hash reference containing the message payload. For example,
when a new release is made, C<$type> will be "release" and C<$payload> will
be the distribution metadata.

=head2 Instance Accessors

=head3 C<name>

Returns the name of this handler, "twitter". Read-only.

=head3 C<client>

The L<Net::Twitter::Lite> used to post to Twitter.

=head1 Author

David E. Wheeler <david@justatheory.com>

=head1 Copyright and License

Copyright (c) 2011-2023 David E. Wheeler.

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
