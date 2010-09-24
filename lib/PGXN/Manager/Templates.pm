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
                content is T $args->{description};
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
            if ($args->{with_jquery} || $args->{validate_form}) {
                script {
                    type is 'text/javascript';
                    src  is $req->uri_for('/ui/js/jquery-1.4.2.min.js');
                };
                if (my $id = $args->{validate_form}) {
                    script {
                        type is 'text/javascript';
                        src  is $req->uri_for('/ui/js/jquery.validate.min.js');
                    };
                    # XXX Consider moving this to a function.
                    script {
                        type is 'text/javascript';
                        outs_raw qq{\$(document).ready(function(){ \$('#$id').validate({errorClass: 'invalid', wrapper: 'div', highlight: function(e) {\$(e).addClass('highlight'); \$(e.form).find('label[for=' + e.id + ']').addClass('highlight');}, unhighlight: function(e) {\$(e).removeClass('highlight'); \$(e.form).find('label[for=' + e.id + ']').removeClass('highlight');}, errorPlacement: function (er, el) { \$(el).before(er) } }); });}
                    };
                }
            }
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

                my $path = $req->path;
                ul {
                    class is 'menu';
                    id is $req->user ? 'usermenu' : 'publicmenu';
                    for my $item (
                        ($req->user ? (
                            [ '/auth/upload',      'Upload a Distribution' ],
                            [ '/auth/show',        'Show my Files'         ],
                            [ '/auth/permissions', 'Show Permissions'      ],
                            [ '/auth/user',        'Edit Account'          ],
                            [ '/auth/pass',        'Change Password'       ],
                        ) : (
                            [ '/auth',    'Log In'          ],
                            [ '/request', 'Request Account' ],
                            [ '/reset',   'Reset Password'  ],
                        )),
                    ) {
                        li { a {
                            href is $req->uri_for($item->[0]);
                            class is 'active' if $path eq $item->[0];
                            T $item->[1];
                        } };
                    }
                }; # /ul id="usermenu|publicmenu"

                if ($req->user_is_admin) {
                    h3 { T 'Admin Menu' };
                    ul {
                        class is 'menu';
                        id is 'adminmenu';
                        for my $item (
                            [ '/auth/admin/requests', 'Moderate Requests' ],
                        ) {
                            li { a {
                                href is $req->uri_for($item->[0]);
                                class is 'active' if $path eq $item->[0];
                                T $item->[1];
                            } };
                        }
                }; # /ul id="allmenu"
                }

                ul {
                    class is 'menu';
                    id is 'allmenu';
                    for my $item (
                        [ '/about',   'About' ],
                        [ '/contact', 'Contact' ],
                    ) {
                        li { a {
                            href is $req->uri_for($item->[0]);
                            class is 'active' if $path eq $item->[0];
                            T $item->[1];
                        } };
                    }
                }; # /ul id="allmenu"

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

template request => sub {
    my ($self, $req, $args) = @_;
    $args->{highlight} //= '';
    wrapper {
        h1 { T 'Request an Account' };
        p { T q{Want to distribute your PostgreSQL extensions on PGXN? Register here to request an account. We'll get it approved post haste.} };
        if (my $err = $args->{error}) {
            p {
                class is 'error';
                outs_raw T @{ $err };
            };
        }
        form {
            id      is 'reqform';
            action  is '/register';
            enctype is 'application/x-www-form-urlencoded';
            method  is 'post';

            fieldset {
                id is 'reqessentials';
                legend { T 'The Essentials' };
                for my $spec (
                    [qw(name     Name     text),  'Barack Obama', T 'What does your mother call you?'    ],
                    [qw(email    Email    email), 'you@example.com', T('Where can we get hold of you?'), 'required email' ],
                    [qw(uri      URI      url),   'http://blog.example.com/', T 'Got a blog or personal site?'  ],
                    [qw(nickname Nickname text),  'bobama', T('By what name would you like to be known? Letters, numbers, and dashes only, please.'), 'required' ],
                ) {
                    label {
                        attr { for => $spec->[0], title => $spec->[4] };
                        class is 'highlight' if $args->{highlight} eq $spec->[0];
                        T $spec->[1];
                    };
                    input {
                        id    is $spec->[0];
                        name  is $spec->[0];
                        type  is $spec->[2];
                        title is $spec->[4];
                        value is $args->{$spec->[0]} || '';
                        my $class = join( ' ',
                            ($spec->[5] ? $spec->[5] : ()),
                            ($args->{highlight} eq $spec->[0] ? 'highlight' : ()),
                        );
                        class is $class if $class;
                        placeholder is $spec->[3];
                    };
                }
            };

            fieldset {
                id is 'reqwhy';
                legend { T 'Your Plans' };
                my $why = T 'So what are your plans for PGXN? What do you wanna release?';
                label {
                    attr { for => 'why', title => $why };
                    class is 'highlight' if $args->{highlight} eq 'why';
                    T 'Why';
                };
                textarea {
                    id    is 'why';
                    name  is 'why';
                    title is $why;
                    class is 'required' . ($args->{highlight} eq 'why' ? ' highlight' : '');
                    placeholder is T "I would like to release the following killer extensions on PGXN:\n\n* foo\n* bar\n* baz";
                    $args->{why} || '';
                };
            };

            input {
                class is 'submit';
                type  is 'submit';
                name  is 'submit';
                id    is 'submit';
                value is T 'Pretty Please!';
            };
        };
    } $req, {
        description   => 'Request a PGXN Account and start distributing your PostgreSQL extensions!',
        keywords      => 'pgxn,postgresql,distribution,register,account,user,nickname',
        validate_form => 'reqform',
        $args ? %{ $args } : ()
    }
};

template thanks => sub {
    my ($self, $req, $args) = @_;
    wrapper {
        h1 { T 'Thanks' };
        p { T q{Thanks for requesting a PGXN account, [_1]. We'll get back to you once the hangover has worn off.}, $args->{name} };
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
