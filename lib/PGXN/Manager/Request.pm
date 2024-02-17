package PGXN::Manager::Request;

use 5.10.0;
use utf8;
use parent 'Plack::Request';
use Plack::Response;
use HTTP::Negotiate;
use PGXN::Manager;
use HTTP::Body '1.08'; # required for proper upload mime type detection.
use namespace::autoclean;
use Encode;

our $VERSION = v0.32.1;

my $CHECK = Encode::FB_CROAK | Encode::LEAVE_SRC;
my $SCRIPT_NAME = PGXN::Manager->config->{uri_script_name_key} || 'SCRIPT_NAME';

sub uri_for {
    my $req = shift;
    my $uri = $req->base;
    $uri->path($req->env->{$SCRIPT_NAME} . ($_[0] =~ m{^/} ? '' : '/') . shift);
    $uri->query_form([@_], ';') if @_;
    $uri;
}

my $variants = [
    #  ID     QS  Content-Type         Encoding  Charset  Lang  Size
    ['text',  1, 'text/plain',           undef,   undef, undef, 1000 ],
    ['json',  1, 'application/json',     undef,   undef, undef, 2000 ],
    ['atom',  1, 'application/atom+xml', undef,   undef, undef, 3000 ],
    ['html',  1, 'text/html',            undef,   undef, undef, 4000 ],
];

sub respond_with {
    choose $variants, shift->headers;
}

sub user_is_admin {
    my $self = shift;
    return $self->{pgxn_admin} if exists $self->{pgxn_admin};

    # Authenticated?
    my $u = $self->user or return $self->{pgxn_admin} = 0;

    # Look up the user.
    return $self->{pgxn_admin} = PGXN::Manager->conn->run(sub {
        shift->selectcol_arrayref(
            'SELECT is_admin FROM users WHERE nickname = ?',
            undef, $u
        )->[0];
    });
}

sub is_xhr {
    no warnings 'uninitialized';
    shift->env->{HTTP_X_REQUESTED_WITH} eq 'XMLHttpRequest';
}

sub address     {
    my $env = $_[0]->env;
    return $env->{HTTP_X_FORWARDED_FOR} || $env->{REMOTE_ADDR};
}

sub remote_host {
    my $env = $_[0]->env;
    return $env->{HTTP_X_FORWARDED_HOST} || $env->{REMOTE_HOST};
}

sub _query_parameters {
    my $self = shift;
    my $enc = $self->headers->content_type_charset || 'UTF-8';
    [ map { decode $enc, $_, $CHECK } @{ $self->SUPER::_query_parameters } ]
}

sub _body_parameters {
    my $self = shift;
    my $enc = $self->headers->content_type_charset || 'UTF-8';
    [ map { decode $enc, $_, $CHECK } @{ $self->SUPER::_body_parameters } ]
}

1;

=head1 Name

PGXN::Manager::Request - Enhanced HTTP Request object

=head1 Synopsis

  use PGXN::Manager::Request;
  my $req = PGXN::Manager::Request->new($env);

=head1 Description

This class subclasses L<Plack::Request> to add additional methods used by
PGXN::Manager.

=head1 Interface

=head2 Instance Method

=head3 C<uri_for>

  my $uri = $req->uri_for('/foo', bar => 'baz');

Creates and returns a L<URI> for the specified URI path and query parameters.
The path is assumed to be an absolute path and to be properly escaped. It will
be appended to the base path for the app as defined by the script name.

If a proxy server fronting tea app hosts it under a different path, configure
the proxy to pass that path in a header and tell PGXN::Manager what header to
look for by setting the `uri_script_name_key` configuration variable. For
example, if hosting under `/pgxn`, you  might configure the proxy to pass that
value in the `X-Forwarded-Script-Name` header and set the configuration to

  "uri_script_name_key": "HTTP_X_FORWARDED_SCRIPT_NAME",

=head3 C<respond_with>

  my $type = $req->respond_with;
  say   $type eq 'html' ? '<h1>Hi</h1>'
      : $type eq 'text' ? 'Hi' 
      : $type eq 'atom' ? '<feed><title>hi</title></feed>'
      : $type eq 'json' ? '{ "title": "hi" }'
      :                   die "Unknown type $type";

This method uses L<HTTP::Negotiate> to select and return a preferred response
type based on the request accept headers. It supports and can return one of
four different types:

=over

=item C<html>: text/html

=item C<json>: application/json

=item C<atom>: application/xml+atom

=item C<text>: text/plain

=back

In scalar context, only the preferred response type identifier is returned
(C<html>, C<json>, C<atom>, or C<text>). In list context, it returns a list of
C<[variant identifier, calculated quality, content-size]> tuples. The values
are sorted by quality, highest quality first. For example:

  ['html', 1, 4000], ['json', 0.3, 2000], ['atom', 0.3, 3000]

Note that also zero quality variants are included in the return list even if
these should never be served to the client. So if you're trying to chose the
base variant, exclude those with zero quality.

=head3 C<user_is_admin>

  say 'Hey there admin' if $req->user_is_admin;

Returns true if the requested is authenticated and the user is a PGXN admin.
Otherwise returns false.

=head3 C<is_xhr>

  if ($req->is_xhr) {
      # Respond to Ajax request.
  } else {
      # Respond to normal request.
  }

Returns true if the request is an C<XMLHttpRequest> request and false if not.
This is specific to L<jQuery|https://jquery.org> sending the
C<X-Requested-With> header.

=head3 C<address>

Returns the (possibly forwarded) IP address of the client (C<X_FORWARDED_FOR>
or C<REMOTE_ADDR>).

=head3 C<remote_host>

Returns the (possibly forwarded) remote host (C<X_FORWARDED_HOST> or
C<REMOTE_HOST>) of the client. It may be empty, in which case you have to get
the IP address using C<address> method and resolve on your own.

=head3 C<query_parameters>

=head3 C<body_parameters>

=head3 C<parameters>

These methods decode all parameters to Perl's internal representation. Tries
to use the encoding specified by the request or, if there is none, assumes
UTF-8. This should be safe as browsers will submit in the same encoding as
the form was rendered in.

=head1 Author

David E. Wheeler <david@justatheory.com>

=head1 Copyright and License

Copyright (c) 2010-2024 David E. Wheeler.

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
