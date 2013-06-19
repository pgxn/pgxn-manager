package PGXN::Manager::Router;

use 5.10.0;
use utf8;
use Router::Resource;
use Plack::Builder;
use Plack::App::File;
use Plack::Session::Store::File;
use PGXN::Manager::Controller;
use PGXN::Manager;

our $VERSION = v0.15.1;

sub app {
    builder {
        my $controller = PGXN::Manager::Controller->new;
        my $sessdir = File::Spec->catdir(
            File::Spec->tmpdir,
            'pgxn-session-' . ($ENV{PLACK_ENV} || 'test')
        );
        mkdir $sessdir unless -e $sessdir;
        my $store = Plack::Session::Store::File->new( dir => $sessdir );
        my $mids  = PGXN::Manager->instance->config->{middleware} || [];
        my $files = Plack::App::File->new(root => './www/ui/');

        # First app is simple redirect to /pub.
        mount '/'   => sub { $controller->root(@_) };

        # Public app.
        mount '/pub' => builder {
            my $router = router {
                missing { $controller->missing(@_) };
                resource '/' => sub {
                    GET { $controller->home(@_) };
                };

                resource '/error' => sub {
                    GET { $controller->server_error(@_) };
                };

                resource '/about' => sub {
                    GET { $controller->about(@_) };
                };

                resource '/contact' => sub {
                    GET { $controller->contact(@_) };
                };

                resource '/howto' => sub {
                    GET { $controller->howto(@_) };
                };

                resource '/account/register' => sub {
                    GET  { $controller->request(@_)  };
                    POST { $controller->register(@_) };
                };

                resource '/account/forgotten' => sub {
                    GET  { $controller->forgotten(@_)  };
                    POST { $controller->send_reset(@_) };
                };

                resource '/account/thanks' => sub {
                    GET { $controller->thanks(@_) };
                };
            };
            mount '/ui' => $files;
            mount '/'   => builder {
                enable 'Session', store => $store;
                enable @{ $_ } for @{ $mids };
                sub { $router->dispatch(shift) };
            };
        };

        # Authenticated app.
        mount '/auth' => builder {
            my $router = router {
                missing { $controller->missing(@_) };
                resource '/' => sub {
                    GET { $controller->home(@_) };
                };

                resource '/error' => sub {
                    GET { $controller->server_error(@_) };
                };

                resource '/about' => sub {
                    GET { $controller->about(@_) };
                };

                resource '/contact' => sub {
                    GET { $controller->contact(@_) };
                };

                resource '/howto' => sub {
                    GET { $controller->howto(@_) };
                };

                resource  '/account' => sub {
                    GET  { $controller->show_account(@_)   };
                    POST { $controller->update_account(@_) };
                };

                resource  '/account/password' => sub {
                    GET  { $controller->show_password(@_)   };
                    POST { $controller->update_password(@_) };
                };

                resource '/account/reset/:tok' => sub {
                    GET  { $controller->reset_form(@_) };
                    POST { $controller->reset_pass(@_) };
                };

                resource  '/account/changed' => sub {
                    GET { $controller->pass_changed(@_) };
                };

                resource '/upload' => sub {
                    GET  { $controller->show_upload(@_) };
                    POST { $controller->upload(@_)      };
                };

                resource '/permissions' => sub {
                    GET { $controller->show_perms(@_) };
                };

                resource '/admin/moderate' => sub {
                    GET { $controller->moderate(@_) };
                };

                resource '/admin/user/:nick/status' => sub {
                    POST { $controller->set_status(@_) };
                };

                resource '/admin/users' => sub {
                    GET { $controller->show_users(@_) };
                };

                resource '/admin/mirrors' => sub {
                    GET  { $controller->show_mirrors(@_) };
                    POST { $controller->insert_mirror(@_) };
                };

                resource '/admin/mirrors/new' => sub {
                    GET { $controller->new_mirror(@_) };
                };

                resource '/admin/mirrors/*' => sub {
                    GET    { $controller->get_mirror(@_)    };
                    PUT    { $controller->update_mirror(@_) };
                    DELETE { $controller->delete_mirror(@_) };
                };

                resource '/distributions' => sub {
                    GET { $controller->distributions(@_) };
                };

                resource '/distributions/:dist/:version' => sub {
                    GET { $controller->distribution(@_) };
                };
            };
            mount '/ui' => $files;
            mount '/'   => builder {
                enable 'MethodOverride';
                enable 'Session', store => $store;
                enable @{ $_ } for @{ $mids };

                # Authenticate all requests.
                enable_if {
                    shift->{PATH_INFO} !~ m{^/account/(?:reset/|changed)}
                } 'Auth::Basic', realm => 'PGXN Users Only', authenticator => sub {
                    my ($username, $password) = @_;
                    PGXN::Manager->conn->run(sub {
                        return ($_->selectrow_array(
                            'SELECT authenticate_user(?, ?)',
                            undef, $username, $password
                        ))[0];
                    });
                };
                sub { $router->dispatch(shift) };
            };
        };
    };
};

STACKTRACE: {
    package PGXN::Manager::StackTrace;
    use Devel::StackTrace;
    use Scalar::Util 'blessed';
    use namespace::autoclean;

    # Override Plack::Middleware::StackTrace's trace class setting.
    use Plack::Middleware::StackTrace;
    my $StackTraceClass = $Plack::Middleware::StackTrace::StackTraceClass;
    $Plack::Middleware::StackTrace::StackTraceClass = __PACKAGE__;

    sub new {
        my $class = shift;
        my %p = @_;
        my $err = $p{message};

        # Use the original stack trace if we have one.
        if (blessed $err) {
            if (my $meth = $err->can('trace') || $err->can('stack_trace')) {
                my $trace = $err->$meth;
                $trace->{message} = $err->as_string; # Ack!
            }
        }
        # Otherwise generate a new one.
        return $StackTraceClass->new(@_, ignore_package => __PACKAGE__);
    }
}

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

Copyright (c) 2010-2011 David E. Wheeler.

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
