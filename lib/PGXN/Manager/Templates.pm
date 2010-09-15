package PGXN::Manager::Templates;

use 5.12.0;
use utf8;
use parent 'Template::Declare';
use Template::Declare::Tags;
use PGXN::Manager;
use PGXN::Manager::Locale;

my $l = PGXN::Manager::Locale->get_handle('en');
sub T {
    $l->maketext(@_);
}

BEGIN { create_wrapper wrapper => sub {
    my ($code, $req, $args) = @_;
    $l = PGXN::Manager::Locale->accept($req->env->{HTTP_ACCEPT_LANGUAGE});

    xml_decl { 'xml', version => '1.0' };
    outs_raw '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" '
           . '"http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">';
    html {
        attr {
            xmlns      => 'http://www.w3.org/1999/xhtml',
            'xml:lang' => 'en',
        };
        head {
            meta { attr {
                'http-equiv' => 'Content-Type',
                 content     => 'text/html; charset=UTF-8',
            } };
            title { T 'main_title' };
            meta {
                name is 'generator';
                content is 'PGXN::Manager ' . PGXN::Manager->VERSION;
            };
            meta {
                name is 'description';
                content is $args->{description};
            } if $args->{description};
            meta {
                name    is 'keywords',
                content is $args->{keywords}
            } if $args->{keywords};
            link {
                rel  is 'stylesheet';
                type is 'text/css';
                href is $req->uri_for('/ui/css/screen.css');
            };
            outs_raw "\n  <!--[if IE 6]>";
            link {
                rel  is 'stylesheet';
                type is 'text/css';
                href is $req->uri_for('/ui/css/fix.css');
            };
            outs_raw "\n  <![endif]-->";
            link {
                rel is 'shortcut icon';
                href is $req->uri_for('/ui/img/favicon.png');
            };
        };

        body {
            div {
                id is 'content';
                $code->();
            }; # /div id="content"

            div {
                id is 'sidebar';
                a {
                    id is 'logo';
                    href is $req->uri_for($req->user ? '/auth' : '/');
                    img { src is $req->uri_for('/ui/img/logo.png') };
                };
                h1 { T 'PGXN Manager' };
                h2 { T 'tagline' };

                ul {
                    id is 'menu';
                    my $path = $req->path;
                    for my $item (
                        ($req->user ? (
                            [ '/auth/upload',      'Upload a Distribution' ],
                            [ '/auth/show',        'Show my Files'         ],
                            [ '/auth/permissions', 'Show Permissions'      ],
                            [ '/auth/user',        'Edit Account'          ],
                            [ '/auth/pass',        'Change Password'       ],
                        ) : (
                            [ '/auth' =>  'Log In' ],
                            [ '/request', 'Request Account' ],
                            [ '/reset',   'Reset Password' ],
                        )),
                        [ '/about',   'About' ],
                        [ '/contact', 'Contact' ],
                    ) {
                        li { a {
                            href is $req->uri_for($item->[0]);
                            class is 'active' if $path eq $item->[0];
                            $item->[1];
                        } };
                    }
                }; # /ul id="menu"

            }; # /div id="sidebar"
        }; # /body
    };
} };

template home => sub {
    my ($self, $req, $args) = @_;
    wrapper {
        h1 { T 'Welcome' };
    } $req, $args;
};

1;

=head1 Name

PGXN::Manager::Templates - HTML templates for PGXN::Manager

=head1 Synopsis

  use PGXN::Manager::Templates;
  Template::Declare->init( dispatch_to => ['PGXN::Manager::Templates'] );
  print Template::Declare->show('home', $req, {
      title   => 'PGXN::Manager',
      tagline => 'Release it on PGXN',
  });

=head1 Description

This class defines the HTML templates used by PGXN::Manager. They are used
internally by the controllers to render the UI. They're implemented with
L<Template::Declare>, but interface wise, all you need to do is C<show> them
as in the L</Synopsis>.

=head1 Templates

=head2 Wrapper

=head3 C<wrapper>

Wrapper template called by all page view templates that wraps them in the
basic structure of the site (logo, navigation, footer, etc.). It also handles
the title of the site, and any status message or error message. These must be
stored under the C<title>, C<status_msg>, and C<error_msg> keys in the args
hash, respectively.

=begin comment

XXX Document all parameters.

=end comment

=head2 Full Page Templates

=head3 C<home>

Renders the home page of the app.

=head2 Utility Functions

=head3 C<T>

  h1 { T 'Welcome!' };

Translates the string using L<PGXN::Manager::Locale>.

=head1 Author

David E. Wheeler <david.wheeler@pgexperts.com>

=head1 Copyright and License

Copyright (c) 2010 David E. Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
