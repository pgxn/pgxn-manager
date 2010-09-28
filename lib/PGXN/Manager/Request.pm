package PGXN::Manager::Request;

use 5.12.0;
use utf8;
use parent 'Plack::Request';
use Plack::Response;
use HTTP::Negotiate;
use PGXN::Manager;
use namespace::autoclean;
use Encode;

my $CHECK = Encode::FB_CROAK | Encode::LEAVE_SRC;

sub uri_for {
    my ($self, $path) = (shift, shift);
    my $uri = $self->base;
    my $relpath = $self->script_name;
    if ($path !~ m{^/}) {
        $relpath = $self->path_info;
        $relpath .= '/' if $relpath !~ s{/$}{};
    }
    $uri->path( $relpath . $path);
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
        (shift->selectrow_array(
            'SELECT is_admin FROM users WHERE nickname = ?',
            undef, $u
        ))[0];
    });
}

sub is_xhr {
    shift->env->{HTTP_X_REQUESTED_WITH} eq 'XMLHttpRequest';
}

sub query_parameters {
    my $self = shift;
    $self->{decoded_query_params} ||= Hash::MultiValue->new(
        $self->_decode($self->uri->query_form)
    );
}

sub body_parameters {
    my $self = shift;
    $self->{decoded_body_params} ||= Hash::MultiValue->new(
        $self->_decode($self->SUPER::body_parameters->flatten)
    );
}

sub _decode {
    my $enc = shift->headers->content_type_charset || 'UTF-8';
    map { decode $enc, $_, $CHECK } @_;
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

  my $uri = $req->uri_for('foo', bar => 'baz');

Creates and returns a L<URI> for the specified URI path and query parameters.
If the path begins with a slash, it is assumed to be an absolute path.
Otherwise it is assumed to be relative to the current request path. For
example, if the current request is to C</foo>:

  my $rel = $req->uri_for('bar');  # http://localhost/foo/bar
  my $abs = $req->uri_for('/yow'); # http://localhost/yow

=head3 C<respond_with>

  given ($req->respond_with) {
      say '<h1>Hi</h1>'                    when 'html';
      say 'Hi'                             when 'text';
      say '<feed><title>hi</title></feed>' when 'atom';
      say '{ "title": "hi" }'              when 'json';
  }

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
This is specific to L<jQuery|http://jquery.org> sending the
C<X-Requested-With> header.

=head3 C<query_parameters>

=head3 C<body_parameters>

These two methods override the versions from L<Plack::Request> to decode all
parameters to Perl's internal representation. Tries to use the encoding
specified by the request or, if there is none, assumes UTF-8. This should be
safe as browsers will submit in the same encoding as the form was rendered in.

=head1 Author

David E. Wheeler <david.wheeler@pgexperts.com>

=head1 Copyright and License

Copyright (c) 2010 David E. Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
