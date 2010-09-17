package PGXN::Manager::Controller;

use 5.12.0;
use utf8;
use PGXN::Manager::Request;
use PGXN::Manager::Templates;
use aliased 'PGXN::Manager::Distribution';

Template::Declare->init( dispatch_to => ['PGXN::Manager::Templates'] );

sub render {
    my $self = shift;
    my $res = $_[1]->new_response(200);
    $res->content_type('text/html; charset=UTF-8');
    $res->body(Template::Declare->show(@_));
    return $res->finalize;
}

sub home {
    my $self = shift;
    my $req = PGXN::Manager::Request->new(shift);
    return $self->render('/home', $req);
}

sub auth {
    my $self = shift;
    my $req = PGXN::Manager::Request->new(shift);
    return $self->render('/home', $req);
}

sub upload {
    my $self = shift;
    my $req  = PGXN::Manager::Request->new(shift);
    my $dist = Distribution->new(
        upload => $req->uploads->{distribution},
        owner  => $req->remote_user,
    );
}

1;

=head1 Name

PGXN::Manager::Controller - The PGXN::Manager request controller

=head1 Synopsis

  # in PGXN::Manager::Router:
  use aliased 'PGXN::Manager::Controller';
  get '/' => sub { Root->home(shift) };

=head1 Description

This class defines controller actions for PGXN::Requests. Right now
it doesn't do much, but it's a start.

=head1 Interface

=head2 Actions

=head3 C<home>

  PGXN::Manager::Controller->home($env);

Displays the HTML for the home page.

=head3 C<auth>

  PGXN::Manager::Controller->auth($env);

Displays the HTML for the authorized user home page.

=head3 C<upload>

  PGXN::Manager::Controller->upload($env);

Handles uploads to PGXN.

=head2 Methods

=head3 C<render>

  $root->render('/home', $req, @template_args);

Renders the output for an action.

=head1 Author

David E. Wheeler <david.wheeler@pgexperts.com>

=head1 Copyright and License

Copyright (c) 2010 David E. Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.
