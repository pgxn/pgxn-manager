package PGXN::Manager::Consumer::mastodon;

use 5.10.0;
use utf8;
use Moose;
use LWP::UserAgent;
use LWP::Protocol::https;
use Try::Tiny;
use Encode qw(encode_utf8);
use JSON::XS;
use POSIX ();
use strict;
use warnings;
use constant name => 'mastodon';
use namespace::autoclean;

our $VERSION = v0.32.0;

has server  => (is => 'ro', required => 1, isa => 'Str');
has ua      => (is => 'ro', required => 1, isa => 'LWP::UserAgent');
has delay   => (is => 'ro', required => 0, isa => 'Int', default => 0);
has logger  => (is => 'ro', required => 1, isa => 'PGXN::Manager::Consumer::Log');

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    # Make sure we have the API URL and the token.
    my $cfg = delete $args{config} || {};
    my $server = $cfg->{server} || die 'Missing Mastodon API server URL';
    my $tok    = $cfg->{token}  || die 'Missing Mastodon API token';
    $args{delay} ||= $cfg->{delay} if exists $cfg->{delay};

    # Set up the user agent.
    my $ua = LWP::UserAgent->new;
    $ua->timeout(60);
    $ua->agent(__PACKAGE__ . '/' . __PACKAGE__->VERSION);
    $ua->ssl_opts(verify_hostname => 1);
    $ua->default_headers->header(
        Authorization => "Bearer $tok",
        'Content-Type' => 'application/json',
    );

    # Continue!
    return $class->$orig(%args, server => $server, ua => $ua);
};

my %EMOJI = (
    send => [qw(🚀 📦 🏹 🎯 🚚 🚛 🛻 🔨 🛠️ ⚒️ 🔧 🪛 🪚 🗜️ ⛏️ 🧰 🔩 ⚙️ ✈️ 🦅 🛫 🛬 🥏 🦇 🚁 🚊 🚞 🚂 🚆 🚄 🚅 🚃 🚇 🚟 🚝 🚋 🚈)],
    user => [qw(😍 😊 😁 🤣 😉 😀 🤪 😜 🤔 🙂 😄 🥳 😏 😆 😃 🤩 🤯 🤠 🌞)],
    info => [qw(ℹ️ 📄 📃 📜 📚 📖 ‼️ 📢 📣 🎙️ 🗣️)],
);

sub handle {
    my ($self, $type, $meta) = @_;
    if ($type ne 'release') {
        $self->logger->log(DEBUG => "Mastodon skiping $type notification");
        return;
    };

    my $release = lc "$meta->{name}-$meta->{version}";
    $self->logger->log(INFO => "Posting $release to Mastodon");

    my $link = PGXN::Manager->instance->config->{release_permalink};
    my $url = URI::Template->new($link)->process({
        dist    => lc $meta->{name},
        version => lc $meta->{version},
    });

    my $status = $meta->{release_status} eq 'stable' ? ''
        : " ($meta->{release_status})";

    my %emo = map { $_ => $EMOJI{$_}[rand @{ $EMOJI{$_} }] } keys %EMOJI;
    $self->toot($release, join("\n\n",
        "$emo{send} Released: $meta->{name} $meta->{version}$status",
        "$emo{info} $meta->{abstract}",
        "$emo{user} By $meta->{user}",
        $url,
    ));
}

sub toot {
    my ($self, $release, $body) = @_;

    my $res = $self->ua->post(
        $self->server . '/api/v1/statuses',
        Content => encode_json {
            status => $body,
            $self->scheduled_at,
        },
    );
    return 1 if $res->is_success;

    $self->logger->log(ERROR => sprintf(
        "Error posting %s to Mastodon (status %d): %s",
        $release, $res->code, $res->decoded_content,
    ));
}

sub scheduled_at {
    my $delay = shift->delay or return;
    return scheduled_at => POSIX::strftime '%Y-%m-%dT%H:%M:%SZ', gmtime time + $delay;
}

1;
__END__

=head1 Name

PGXN::Manager::Consumer::mastodon - Post PGXN Manager events to Mastodon

=head1 Synopsis

Configuration:

  "consumers": [
      {
          "type": "mastodon",
          "events": ["release"],
          "server": "https://mstdn.example.org",
          "token": "ABCDefgh123456789x0x0x0x0x0x0x0x0x0x0x0",
          "delay": 300
      }
  ]

Execution:

  use PGXN::Manager::Consumer;
  PGXN::Manager::Consumer->go;

=head1 Description

This module implements a PGXN event consumer to post release announcements
to Mastodon. It currently responds only to C<release> events.

=head1 Class Interface

=head2 Constructor

=head3 C<new>

  my $mastodon = PGXN::Manager::Consumer::mastodon->new(%params);

Creates and returns a new PGXN::Manager::Consumer::mastodon object. The
supported parameters are:

=over

=item C<config>

A hash reference corresponding to the C<consumers/mastodon> section of the
configuration file. It supports the following keys:

=over

=item C<server>

The base URL for the Mastodon server. Required.

=item C<token>

The Mastodon API access token. Required.

=item C<delay>

The number of seconds to delay posting the status. Defaults to 0, and
otherwise must be at least 300, according to the
L<Mastodon API docs|https://docs.joinmastodon.org/methods/statuses/#create>.

=back

=back

=head1 Instance Interface

=head2 Instance Methods

=head3 C<handle>

  $mastodon->handle($type, $payload);

Handles a PGXN Manager event. The first argument is type of the event, and
the second is a hash reference containing the message payload. For example,
when a new release is made, C<$type> will be "release" and C<$payload> will
be the distribution metadata.

=head3 C<toot>

  my $handlers = $mastodon->toot($body);

Posts a message to Mastodon. C<$body> contains the post text.

=head3 C<scheduled_at>

Returns the key and value pair for the Mastodon API C<scheduled_at>
parameter. Returns an empty list if C<delay> is zero.

=head2 Instance Accessors

=head3 C<name>

Returns the name of this handler, "mastodon". Read-only.

=head3 C<ua>

The L<LWP::UserAgent> used to post to Mastodon.

=head3 C<server>

The base URL of the Mastodon server to post to.

=head3 C<delay>

The number of seconds to delay posting the status.

=head1 Author

David E. Wheeler <david@justatheory.com>

=head1 Copyright and License

Copyright (c) 2011-2024 David E. Wheeler.

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
