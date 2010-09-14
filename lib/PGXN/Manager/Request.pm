package PGXN::Manager::Request;

use 5.12.0;
use utf8;
use parent 'Plack::Request';
use Plack::Response;

sub uri_for {
    my ($self, $path) = (shift, shift);
    my $uri = $self->base;
    my $relpath = ''; # XXX Configure for app mounted elsewhere than root?
    if ($path !~ m{^/}) {
        $relpath = $self->path_info;
        $relpath .= '/' if $relpath !~ s{/$}{};
    }
    $uri->path( $relpath . $path);
    $uri->query_form([@_], ';') if @_;
    $uri;
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

=head1 Author

David E. Wheeler <david.wheeler@pgexperts.com>

=head1 Copyright and License

Copyright (c) 2010 David E. Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
