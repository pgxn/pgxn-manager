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
            my $title = PGXN::Manager->config->{name} || 'PGXN Manager';
            if (my $page = $args->{page_title}) {
                $title .= ' — ' . T $page;
            }
            title { $title };
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
            if ($args->{js} || $args->{with_jquery} || $args->{validate_form}) {
                script {
                    # http://docs.jquery.com/Downloading_jQuery#CDN_Hosted_jQuery
                    type is 'text/javascript';
                    src is 'http://code.jquery.com/jquery-1.4.2.min.js';
                };
                script {
                    type is 'text/javascript';
                    src  is $req->uri_for('/ui/js/lib.js');
                };
                if (my $js = $args->{js}) {
                    script {
                        type is 'text/javascript';
                        outs_raw $js;
                    }
                }
                if (my $id = $args->{validate_form}) {
                    script {
                        # http://bassistance.de/jquery-plugins/jquery-plugin-validation/
                        type is 'text/javascript';
                        src  is 'http://ajax.microsoft.com/ajax/jquery.validate/1.7/jquery.validate.pack.js';
                    };
                    script {
                        type is 'text/javascript';
                        outs_raw "PGXN.validate_form('$id')";
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
                            [ '/auth/upload',           'Upload a Distribution', 'upload'      ],
                            [ '/auth/distributions',    'Your Distributions',    'dists'       ],
                            [ '/auth/permissions',      'Show Permissions',      'permissions' ],
                            [ '/auth/account',          'Edit Account',          'account'     ],
                            [ '/auth/account/password', 'Change Password',       'passwd'      ],
                        ) : (
                            [ '/auth',              'Log In',          'login'   ],
                            [ '/account/register',  'Request Account', 'request' ],
                            [ '/account/forgotten', 'Reset Password',  'reset'   ],
                        )),
                    ) {
                        li { a {
                            id is $item->[2];
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
                            [ '/auth/admin/moderate', 'Moderate Requests',   'moderate' ],
                            [ '/auth/admin/users',    'User Administration', 'users'    ],
                        ) {
                            li { a {
                                id is $item->[2];
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
                        [ '/about',   'About',   'about'   ],
                        [ '/contact', 'Contact', 'contact' ],
                    ) {
                        li { a {
                            id is $item->[2];
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
        if (delete $req->session->{reset_sent}) {
            p {
                class is 'success';
                T q{Okay, we've emailed instructions for resetting your password. So go check your email! We'll be here when you get back.};
            };
        }
        p {
            outs T q{PGXN Manger is a Webapp that allows you to upload PostgreSQL extension distributions and have them be distributed to the PostgreSQL Extension Network.};
            a {
                href is $req->uri_for('/about');
                T q{See "About" for details on how to get started.};
            };
        };

    } $req, { page_title => 'home_page_title', $args ? %{ $args } : () };
};

# XXX Move to a static file?
template about => sub {
    my ($self, $req, $args) = @_;
    wrapper {
        h1 { T 'About PGXN Manager' };
        p { T 'PGXN, the PostgreSQL Extension network, is a central distribution system for open-source PostgreSQL extension libraries. As of this writing, it consists of:' };
        ul {
            li { T 'An upload and distribution infrastructure for extension developers.' };
            li { T 'A centralized index and API of distribution metadata.' };
        };
        p { T q{This Webapp handles the management of these parts of the infrastructure. So if you'd like to develop and release PostgreSQL estensions, you've come to the right place! Here's how to get started:} };
        ul {
            li {
                a {
                    href is $req->uri_for('/account/register');
                    T 'Register for an acount.';
                };
            };
            li {
                outs T q{Once your account has been approved, you'll be notified via email.};
                a {
                    href is $req->uri_for('/auth');
                    T 'Go ahead and login.';
                };
            };
            li {
                outs T q{Prepare your extension for distribution by creating a META.json file.};
                a {
                    href is 'http://github.com/theory/pgxn/wiki/PGXN-Meta-Spec';
                    T 'See the PGXN Meta Spec.';
                };
            };
            li {
                outs T q{Package up your distribution into an archive file (zip, tarball, etc.).};
                a {
                    href is $req->uri_for('/auth/upload');
                    T 'Upload it to release!';
                };
            };
        };
    } $req, { page_title => 'about_page_title', $args ? %{ $args } : () };
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
            action  is $req->uri_for('/account/register');
            # Browser should send us UTF-8 if that's what we ask for.
            # http://www.unicode.org/mail-arch/unicode-ml/Archives-Old/UML023/0450.html
            enctype is 'application/x-www-form-urlencoded; charset=UTF-8';
            method  is 'post';

            fieldset {
                id is 'reqessentials';
                legend { T 'The Essentials' };
                for my $spec (
                    [qw(name     Name     text),  'Barack Obama', T 'What does your mother call you?'    ],
                    [qw(email    Email    email), 'you@example.com', T('Where can we get hold of you?'), 'required email' ],
                    [qw(uri      URI      url),   'http://blog.example.com/', T 'Got a blog or personal site?'  ],
                    [qw(nickname Nickname text),  'bobama', T('By what name would you like to be known? Letters, numbers, and dashes only, please.'), 'required' ],
                    [qw(twitter  Twitter   text),   '@barackobama', T 'Got a Twitter account? Tell us the username and your uploads will be tweeted!'  ],
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
        validate_form => '#reqform',
        page_title    => 'Request an account and start releasing distributions',
        $args ? %{ $args } : ()
    }
};

template thanks => sub {
    my ($self, $req, $args) = @_;
    wrapper {
        h1 { T 'Thanks' };
        p { T q{Thanks for requesting a PGXN account, [_1]. We'll get back to you once the hangover has worn off.}, $args->{name} };
    } $req, { %{ $args }, page_title => 'Thanks for registering for an account' };
};

template forbidden => sub {
    my ($self, $req, $args) = @_;
    wrapper {
        h1 { T 'Permission Denied' };
        p {
            class is 'error';
            T q{Sorry, you do not have permission to access this resource.};
        };
    } $req, { page_title => q{Whoops! I don't think you belong here} };
};

template notfound => sub {
    my ($self, $req, $args) = @_;
    wrapper {
        h1 { T 'Not Found' };
        p {
            class is 'warning';
            T q{Resource not found.};
        };
    } $req, $args;
};

template conflict => sub {
    my ($self, $req, $args) = @_;
    my $msg = $args->{maketext}
        || [q{Sorry, there is a conflict in that resource. Please fix and resubmit}];
    wrapper {
        h1 { T 'Confflict' };
        p {
            class is 'error';
            T @{ $msg };
        };
    } $req, $args;
};

template moderate => sub {
    my ($self, $req, $args) = @_;
    wrapper {
        h1 { T 'Moderate Account Requests' };
        p {
            T q{Thanks for moderating user requests, [_1]. Here's how:}, $req->user;
        };
        ul {
            li { T q{Hit the green ▶ to review a requestor's reasons for wanting an account.}};
            li { T q{Hit the blue ✔ to approve an account request.}};
            li { T q{Hit the red ▬ to deny an account request.}};
        };
        table {
            id is 'userlist';
            summary is T 'List of requests for users accounts';
            thead {
                row {
                    th { scope is 'col'; class is 'nobg'; T 'Requests' };
                    th { scope is 'col'; T 'Name'    };
                    th { scope is 'col'; T 'Email'   };
                    th { scope is 'col'; T 'Actions' };
                };
            };
            tbody {
                my $i = 0;
                while (my $user = $args->{sth}->fetchrow_hashref) {
                    row {
                        class is ++$i % 2 ? 'spec' : 'specalt';
                        my $name = $user->{full_name} || T '~[none given~]';
                        th {
                            scope is 'row';
                            a {
                                class is 'userplay';
                                href is '#';
                                title is T q{Review [_1]'s }, $user->{nickname};
                                img { src is $req->uri_for('/ui/img/play.png' ) };
                                outs $user->{nickname};
                            };
                            div {
                                class is 'userinfo';
                                id is "$user->{nickname}_why";
                                div {
                                    class is 'why';
                                    p { T q{[_1] says:}, $user->{nickname}};
                                    blockquote {
                                        p { $user->{why} };
                                    };
                                };
                            };
                        };
                        cell {
                            if (my $uri = $user->{uri}) {
                                title is T q{Visit [_1]'s site}, $user->{nickname};
                                a { href is $uri; $name };
                            } else {
                                $name;
                            }
                        };
                        cell {
                            title is T 'Send email to [_1]', $user->{nickname};
                            a {
                                href is "mailto:$user->{email}";
                                $user->{email};
                            };
                        };
                        cell {
                            class is 'actions';
                            for my $spec (
                                [accept => 'active' ],
                                [reject => 'deleted' ],
                            ) {
                                form {
                                    class is $spec->[0];
                                    action  is $req->uri_for("/auth/admin/user/$user->{nickname}/status");
                                    enctype is 'application/x-www-form-urlencoded; charset=UTF-8';
                                    method  is 'post';
                                    input {
                                        type  is 'hidden';
                                        name  is 'status';
                                        value is $spec->[1];
                                    };
                                    input {
                                        class is 'button';
                                        type is 'image';
                                        name is 'submit';
                                        src is $req->uri_for("/ui/img/$spec->[0].png")
                                    };
                                };
                            }
                        };
                    }
                }
                unless ($i) {
                    # Oops, no users.
                    row {
                        class is 'spec';
                        cell {
                            colspan is 4;
                            T 'No pending requests. Time for a beer?';
                        };
                    };
                }
            }
        };
    } $req, {
        page_title => 'User account moderation',
        with_jquery => 1,
        js => 'PGXN.init_moderate()',
        $args ? %{ $args } : (),
    };
};

template 'show_upload' => sub {
    my ($self, $req, $args) = @_;
    wrapper {
        h1 { T 'Upload a Distribution' };
        p { T q{So you've developed a PGXN extension and what to distribute it on PGXN. This is the place to upload it! Just find your distribution archive (.zip, .tgz, etc.) in the upload field below and you'll be good to go.} };
        if (my $err = $args->{error}) {
            p {
                class is 'error';
                outs_raw T @{ $err };
            };
        }
        form {
            id      is 'upform';
            action  is $req->uri_for('/auth/upload');
            enctype is 'multipart/form-data';
            method  is 'post';
            fieldset {
                id is 'uploadit';
                legend { T 'Upload a Distribution Archive' };
                label {
                    attr { for => 'archive', title => T 'Select an archive file to upload.' };
                    T 'Archive';
                };
                input {
                    id    is 'archive';
                    class is 'uploader';
                    name  is 'archive';
                    type  is 'file';
                    title is T 'Upload your distribution archive file here.';
                };
            };
            input {
                class is 'submit';
                type  is 'submit';
                name  is 'submit';
                id    is 'submit';
                value is T 'Release It!';
            };
        };
    } $req, {
        description   => 'Upload an archive file with your PGXN extensions in it. It will be distributed on PGXN and mirrored to all the networks.',
        keywords      => 'pgxn,postgresql,distribution,upload,release,archive,extension,mirror,network',
        page_title => 'Release a distribution archive on the network',
        $args ? %{ $args } : ()
    }
};

template distributions => sub {
    my ($self, $req, $args) = @_;
    wrapper {
        h1 { T 'Your Distributions' };
        table {
            id is 'distlist';
            summary is T 'List of distributions owned by [_1]', $req->user;
            thead {
                row {
                    th { scope is 'col'; class is 'nobg'; T 'Distributions' };
                    th { scope is 'col'; T 'Status'   };
                    th { scope is 'col'; T 'Released' };
                };
            };
            tbody {
                my $i = 0;
                my $forward = $req->uri_for('/ui/img/forward.png');
                while (my $row = $args->{sth}->fetchrow_hashref) {
                    row {
                        class is ++$i % 2 ? 'spec' : 'specalt';
                        th {
                            scope is 'row';
                            a {
                                my $name = "$row->{name}-$row->{version}";
                                class is 'show';
                                title is T q{See [_1]'s details}, $name;
                                href  is $req->uri_for("/auth/distributions/$row->{name}/$row->{version}");
                                img { src is $forward; };
                                outs $name;
                            };
                        };
                        cell { T $row->{relstatus} };
                        cell { $row->{date} };
                    }
                }
                unless ($i) {
                    # No distributions.
                    row {
                        class is 'spec';
                        cell {
                            colspan is 3;
                            outs T q{You haven't uploaded a distribution yet.};
                            a {
                                id is 'iupload';
                                href is $req->uri_for('/auth/upload');
                                T 'Release one now!';
                            };
                        };
                    };
                }
            }
        };
    } $req, {
        page_title => 'Your distributions',
        $args ? %{ $args } : (),
    };
};

template distribution => sub {
    my ($self, $req, $args) = @_;
    my $dist = $args->{dist};
    my $name = "$dist->{name}-$dist->{version}";
    $name .= " ($dist->{relstatus})" if $dist->{relstatus} ne 'stable';
    my $uri_templates = PGXN::Manager->uri_templates;
    my $mirror_uri    = PGXN::Manager->config->{mirror_uri};
    my @uri_vars      = (
        dist => $dist->{name},
        version => $dist->{version},
    );

    wrapper {
        h1 { $name };
        p { class is 'abstract'; $dist->{abstract} };
        ul {
            id is 'distlinks';
            li {
                a {
                    my $uri = URI->new($mirror_uri . $uri_templates->{dist}->process_to_string(
                        @uri_vars
                    ));
                    href is $uri;
                    title is T 'Download [_1].', $name;
                    img { src is $req->uri_for('/ui/img/download.png') };
                    span { T 'Archive' };
                };
            };
            if (-e File::Spec->catdir(
                PGXN::Manager->config->{mirror_root},
                $uri_templates->{readme}->process(@uri_vars)
            )) {
                li {
                    a {
                        my $uri = URI->new($mirror_uri . $uri_templates->{readme}->process_to_string(
                            @uri_vars
                        ));
                        href is $uri;
                        title is T 'Download the [_1] README.', $name;
                        img { src is $req->uri_for('/ui/img/warning.png') };
                        span { T 'README' };
                    };
                };
            }
            li {
                a {
                    my $uri = URI->new($mirror_uri . $uri_templates->{meta}->process_to_string(
                        @uri_vars
                    ));
                    href is $uri;
                    title is T 'Download the [_1] Metadata.', $name;
                    img { src is $req->uri_for('/ui/img/info.png') };
                    span { T 'Metadata' };
                };
            };
        };
        if (delete $req->session->{success}) {
            p {
                class is 'success dist';
                T 'Congratulations! This distribution has been released on PGXN.';
            };
        }
        dl {
            if (my $desc = $dist->{description}) {
                dt { T 'Description' };
                dd { p { $desc } };
            }
            dt { T 'Owner' };
            dd { p { $dist->{owner} } };
            dt { T 'Status' };
            dd { p { $dist->{relstatus} } };
            dt { T 'SHA1' };
            dd { p { $dist->{sha1} } };
            dt { T 'Extensions' };
            dd {
                ul {
                    li { p{ "$_->[0] $_->[1]" } } for @{ $dist->{extensions } };
                };
            };
            if (my $tags = $dist->{tags}) {
                dt { T 'Tags' };
                dd { ul { li { $_ } for @{ $tags } } };
            }
        };
    } $req, {
        page_title => $name,
        $args ? %{ $args } : (),
    }
};

template forgotten => sub {
    my ($self, $req, $args) = @_;
    wrapper {
        h1 { T 'Forgot Your Password?' };
        p { T q{Please type your email address or PGXN nickname below.} };
        form {
            id      is 'forgotform';
            action  is $req->uri_for('/account/forgotten');
            enctype is 'application/x-www-form-urlencoded; charset=UTF-8';
            method  is 'post';

            fieldset {
                legend { T 'Who Are You?' };
                input {
                    type is 'text';
                    name is 'who';
                    id   is 'who';
                    placeholder is 'bobama@pgxn.org';
                };
            };
            input {
                class is 'submit';
                type  is 'submit';
                name  is 'submit';
                id    is 'submit';
                value is T 'Send Instructions';
            };
        };
    } $req, {
        page_title => 'Forgot your password? Reset it here',
        $args ? %{ $args } : (),
    };
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
