package PGXN::Manager::Router;

use 5.12.0;
use utf8;
use Plack::Builder;
use Router::Simple::Sinatraish;
use Plack::App::File;
use aliased 'PGXN::Manager::Controller';
use PGXN::Manager;

# The routing table. Define all new routes here.
get  '/'                    => sub { Controller->home(@_)        };
get  '/about'               => sub { Controller->about(@_)       };
get  '/auth'                => sub { Controller->home(@_)        };
get  '/auth/upload'         => sub { Controller->show_upload(@_) };
post '/auth/upload'         => sub { Controller->upload(@_)      };
get  '/register'            => sub { Controller->request(@_)     };
post '/register'            => sub { Controller->register(@_)    };
get  '/thanks'              => sub { Controller->thanks(@_)      };
get  '/auth/admin/moderate' => sub { Controller->moderate(@_)    };
post '/auth/admin/user/:nick/status' => sub { Controller->set_status(@_) };
get  '/auth/distributions'  => sub { Controller->distributions(@_) };
get  '/auth/distributions/:dist/:version' => sub { Controller->distribution(@_) };

sub app {
    my $router = shift->router;

    builder {
        mount '/ui' => Plack::App::File->new(root => './www/ui/');
        mount '/' => builder {
            enable 'JSONP';
            enable 'Session', store => 'File';
            if (my $mids = PGXN::Manager->instance->config->{middleware}) {
                enable @$_ for @$mids;
            }
            # Authenticate all requests undef /auth
            enable_if {
                shift->{PATH_INFO} =~ m{^/auth\b}
            } 'Auth::Basic', realm => 'PGXN Users Only', authenticator => sub {
                my ($username, $password) = @_;
                PGXN::Manager->conn->run(sub {
                    return ($_->selectrow_array(
                        'SELECT authenticate_user(?, ?)',
                        undef, $username, $password
                    ))[0];
                });
            };
            sub {
                my $env = shift;
                my $route = $router->match($env) or return Controller->respond_with(
                    'notfound',
                    PGXN::Manager::Request->new($env)
                );
                return $route->{code}->($env, $route);
            };
        };
    };
};

1;

=head1 Name

PGXN::Manager::Router - The PGXN::Manager request router.

=head1 Synopsis

  # In app.pgsi
  use PGXN::Manager::Router;
  PGXN::Manager::Router->app;

=head1 Description

This class defines the HTTP request routing table used by PGXN::Manager.
Unless you're modifying the PGXN::Manager routes and controllers, you won't
have to worry about it. Just know that this is the class that Plack uses to
fire up the app.

=head1 Interface

=head2 Class Methods

=head3 C<app>

  PGXN::Manager->app;

Returns the PGXN::Manager Plack app. See F<bin/pgxn_manager.pgsgi> for an
example usage. It's not much to look at. But Plack uses the returned code
reference to power the application.

=head1 Author

David E. Wheeler <david.wheeler@pgexperts.com>

=head1 Copyright and License

Copyright (c) 2010 PostgreSQL Experts and David E. Wheeler.

This module is free software; you can redistribute it and/or modify it under
the L<PostgreSQL License|http://www.opensource.org/licenses/postgresql>.

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
