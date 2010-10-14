package PGXN::Manager::Router;

use 5.12.0;
use utf8;
use Plack::Builder;
use Router::Resource;
use Plack::App::File;
use Plack::Session::Store::File;
use aliased 'PGXN::Manager::Controller';
use PGXN::Manager;

# The routing table. Define all new routes here.
resource '/' => sub {
    GET { Controller->root(@_) };
};

resource '/pub' => sub {
    GET { Controller->home(@_) };
};

resource '/pub/about' => sub {
    GET { Controller->about(@_) };
};

resource '/pub/contact' => sub {
    GET { Controller->contact(@_) };
};

resource '/pub/account/register' => sub {
    GET  { Controller->request(@_)  };
    POST { Controller->register(@_) };
};

resource '/pub/account/forgotten' => sub {
    GET  { Controller->forgotten(@_)  };
    POST { Controller->send_reset(@_) };
};

resource '/pub/account/thanks' => sub {
    GET { Controller->thanks(@_) };
};

resource '/pub/account/reset/:tok' => sub {
    GET  { Controller->reset_form(@_) };
    POST { Controller->reset_pass(@_) };
};

resource  '/pub/account/changed' => sub {
    GET { Controller->pass_changed(@_) };
};

resource '/auth' => sub {
    GET { Controller->home(@_) };
};

resource  '/auth/account' => sub {
    GET  { Controller->show_account(@_)   };
    POST { Controller->update_account(@_) };
};

resource  '/auth/account/password' => sub {
    GET  { Controller->show_password(@_)   };
    POST { Controller->update_password(@_) };
};

resource '/auth/upload' => sub {
    GET  { Controller->show_upload(@_) };
    POST { Controller->upload(@_)      };
};

resource '/auth/permissions' => sub {
    GET { Controller->show_perms(@_) };
};

resource '/auth/admin/moderate' => sub {
    GET { Controller->moderate(@_) };
};

resource '/auth/admin/user/:nick/status' => sub {
    POST { Controller->set_status(@_) };
};

resource '/auth/admin/users' => sub {
    GET { Controller->show_users(@_) };
};

resource '/auth/distributions' => sub {
    GET { Controller->distributions(@_) };
};

resource '/auth/distributions/:dist/:version' => sub {
    GET { Controller->distribution(@_) };
};

sub app {
    my $router = shift->router;

    builder {
        mount '/ui' => Plack::App::File->new(root => './www/ui/');
        mount '/' => builder {
            my $sessdir = File::Spec->catdir(
                File::Spec->tmpdir,
                'pgxn-session-' . ($ENV{PLACK_ENV} || 'test')
            );
            mkdir $sessdir unless -e $sessdir;

            enable 'Session', store => Plack::Session::Store::File->new(
                dir => $sessdir
            );
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
                return $route->();
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
