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
                    href is $req->uri_for('/');
                    img { src is $req->uri_for('/ui/img/logo.png') };
                };
                h1 { T 'PGXN Manager' };
                h2 { T 'tagline' };

                my $path = $req->path;
                ul {
                    class is 'menu';
                    if ($req->user) {
                        id is 'usermenu';
                    } else {
                        id is 'publicmenu';
                        li { a {
                            id is 'login';
                            href is $req->auth_uri;
                            T 'Log In';
                        } };
                    }
                    for my $item (
                        ($req->user ? (
                            [ '/upload',           'Upload a Distribution', 'upload'      ],
                            [ '/distributions',    'Your Distributions',    'dists'       ],
                            [ '/permissions',      'Show Permissions',      'permissions' ],
                            [ '/account',          'Edit Account',          'account'     ],
                            [ '/account/password', 'Change Password',       'passwd'      ],
                        ) : (
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
                    hr {};
                    ul {
                        class is 'menu';
                        id is 'adminmenu';
                        for my $item (
                            [ '/admin/moderate', 'Moderate Requests',     'moderate' ],
                            [ '/admin/users',    'User Administration',   'users'    ],
                            [ '/admin/mirrors',  'Mirror Administration', 'mirrors'  ],
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

                hr {};
                ul {
                    class is 'menu';
                    id is 'allmenu';
                    for my $item (
                        [ '/about',   'About',   'about'   ],
                        [ '/howto',   'How To',  'howto'   ],
                        [ '/contact', 'Contact', 'contact' ],
                    ) {
                        li { a {
                            id is $item->[2];
                            my $uri = 
                            href is $req->uri_for($item->[0]);
                            class is 'active' if $path eq $item->[0];
                            T $item->[1];
                        } };
                    }
                }; # /ul id="allmenu"
            }; # /div id="sidebar"
            div {
                id is 'footer';
                p {
                    outs 'PGXN::Manager ' . PGXN::Manager->VERSION;
                    outs_raw '. <a href="http://github.com/theory/pgxn-manager">Distributed</a> under the <a href="http://www.opensource.org/licenses/postgresql">PostgreSQL License</a>.';
                };
            };
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
        p { T q{This Webapp handles the management of these parts of the infrastructure. So if you'd like to develop and release PostgreSQL estensions, you've come to the right place! For the impatient, here's how to get started:} };
        ul {
            li {
                if ($req->user) {
                    T q{Register for an account. But it looks like you've already done that, [_1].},
                      $req->user;
                } else {
                    a {
                        href is $req->uri_for('/account/register');
                        T 'Register for an acount.';
                    };
                }
            };
            unless ($req->user) {
                li {
                    outs T q{Once your account has been approved, you'll be notified via email.};
                    a {
                        href is $req->auth_uri;
                        T 'Go ahead and login.';
                    };
                };
            }
            li {
                outs T q{Create an extension and package it up for distribution. Basically, that means using };
                a {
                    href is 'http://www.postgresql.org/docs/current/static/xfunc-c.html#XFUNC-C-PGXS';
                    T 'PGXS'
                };
                outs T q{ to build your extension, and creating a};
                code { 'META.json' };
                outs T q{ file according to the};
                a {
                    href is 'http://pgxn.org/meta/spec.html';
                    T 'PGXN Meta Spec';
                };
                outs '.';
            };
            li {
                outs T q{Package up your distribution into an archive file (zip, tarball, etc.).};
                a {
                    href is $req->auth_uri_for('/upload');
                    T 'Upload it to release';
                };
                outs T '!';
            };
        };
        p {
            outs T q{For a more detailed discussion on creating PGXN distributions, please read the};
            a {
                href is $req->uri_for('/howto');
                T 'How To';
            };
            outs '.';
        };

        div {
            id is 'credits';
            h3 { T 'Credits' };
            dl {
                dt { T 'Coding' };
                dd {
                    a {
                        href is 'http://justatheory.com/';
                        'David E. Wheeler';
                    };
                };
                dt { T 'Logo' };
                dd {
                    a {
                        href is 'http://strongrrl.com/';
                        'Strongrrl';
                    };
                };
                dt { T 'Site Design' };
                dd {
                    a {
                        href is 'http://andreasviklund.com/';
                        'Andreas Viklund';
                    };
                    outs ', ';
                    a {
                        href is 'http://jasoncole.ca';
                        'Jason Cole';
                    };
                    outs ', and ';
                    a {
                        href is 'http://justatheory.com/';
                        'David E. Wheeler';
                    };
                };
                dt { T 'Funding' };
                dd {
                    a {
                        href is 'http://pgxn.org/contributors.html';
                        T 'Our generous sponsors';
                    };
                };
            };
        };
    } $req, { page_title => 'about_page_title', $args ? %{ $args } : () };
};

template contact => sub {
    my ($self, $req, $args) = @_;
    wrapper {
        h1 { T 'Contact Us' };
        p { T q{Noticed an issue with PGXN? Got a bug to report? Just want to send kudos or complaints? Here's how.}};
        dl{
            dt { T 'Bugs' };
            dd {
                p {
                    outs T 'Please send bug reports to the';
                    a {
                        href is 'http://github.com/theory/pgxn-manager/issues';
                        T 'PGXN Manager Issue Tracker.';
                    };
                };
            };
            dt { T 'Download' };
            dd {
                p {
                    outs T 'PGXN Manager is released under the';
                    a {
                        href is 'http://www.opensource.org/licenses/postgresql';
                        T 'PostgreSQL License';
                    };
                    outs '. ';
                    outs T 'Download PGXN Manager releases from';
                    a {
                        href is 'http://github.com/theory/pgxn-manager/downloads';
                        T 'GitHub Downloads';
                    };
                    outs '.';
                };
            };
            dt { T 'Source' };
            dd {
                p {
                    outs T 'The PGXN Manager source is availabe in a Git reposotory';
                    a {
                        href is 'http://github.com/theory/pgxn-manager';
                        T 'on GitHub';
                    };
                    outs '. ';
                    outs T 'Fork and enjoy.';
                };
            };
        };
    } $req, { page_title => 'contact_page_title', $args ? %{ $args } : () };
};

template howto => sub {
    my ($self, $req, $args) = @_;
    wrapper {
        h1 { T 'PGXN How To' };
        outs_raw T 'howto_body';
    } $req, { page_title => 'howto_page_title', $args ? %{ $args } : () };
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

            show 'essentials', $req, { id => 'reqessentials', %{ $args } };

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
                p { class is 'hint'; $why };
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

template notallowed => sub {
    my ($self, $req, $args) = @_;
    wrapper {
        h1 { T 'Not Allowed' };
        p {
            class is 'error';
            T q{Sorry, but the [_1] method is not allowed on this resource.},
                $req->method;
        };
    } $req, $args;
};

template conflict => sub {
    my ($self, $req, $args) = @_;
    my $msg = $args->{maketext}
        || [q{Sorry, there is a conflict in that resource. Please fix and resubmit}];
    wrapper {
        h1 { T 'Conflict' };
        p {
            class is 'error';
            T @{ $msg };
        };
    } $req, $args;
};

template gone => sub {
    my ($self, $req, $args) = @_;
    wrapper {
        h1 { T 'Resource Gone' };
        p {
            class is 'error';
            T $args->{maketext}
                ? @{ $args->{maketext} }
                : 'Sorry, the resource you requested is gone';
        };
    } $req, {
        page_title => 'Resource Gone',
        $args ? %{ $args } : (),
    };
};

template servererror => sub {
    my ($self, $req, $args) = @_;
    wrapper {
        h1 { T 'Ow ow ow ow ow ow…' };
        p {
            class is 'error';
            T q{Whoops! Some sort of error occurred. We apologise for the fault in the server. Those responsible have been sacked. Mynd you, elephänt bites kan be pretty nasti…Please do try again.};
        };
    } $req, {
        page_title => 'Internal Server Error',
        $args ? %{ $args } : (),
    };
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
                                [remove => 'deleted' ],
                            ) {
                                form {
                                    class is $spec->[0];
                                    action  is $req->uri_for("/admin/user/$user->{nickname}/status");
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
        p {
            outs T q{Don't know what this means? Want to know how to create great PostgreSQL extensions and distribute them to your fellow PostgreSQL enthusiasts via PGXN? Take a gander at our};
            a {
                href is $req->uri_for('/howto');
                T 'How to';
            };
            outs T q{ for all the juicy details. It's not hard, we promise.};
        };
        if (my $err = $args->{error}) {
            p {
                class is 'error';
                outs_raw T @{ $err };
            };
        }
        form {
            id      is 'upform';
            action  is $req->uri_for('/upload');
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
                                href  is $req->uri_for("/distributions/$row->{name}/$row->{version}");
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
                                href is $req->uri_for('/upload');
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
        page_title => 'Forgot your password? Request a reset link',
        $args ? %{ $args } : (),
    };
};

template reset_form => sub {
    my ($self, $req, $args) = @_;
    wrapper {
        h1 { T 'Reset Your PGXN Password' };
        p { T q{Please choose a password to use for your PGXN account.} };
        if ($args->{nomatch}) {
            p {
                class is 'error';
                outs T 'Passwords do not match. Please try again';
            };
        }
        form {
            id      is 'changeform';
            action  is $req->uri_for($req->path_info);
            enctype is 'application/x-www-form-urlencoded; charset=UTF-8';
            method  is 'post';

            fieldset {
                legend { T 'Change Password' };
                my $title = T 'Must be at least four charcters long.';
                label {
                    attr { for => 'new_pass', title => $title };
                    T 'New Password';
                };
                input {
                    type  is 'password';
                    name  is 'new_pass';
                    id    is 'new_pass';
                    title is $title;
                };
                $title = T 'Must be the same as the new password.';
                label {
                    attr { for => 'verify', title => $title };
                    T 'Verify Password';
                };
                input {
                    type  is 'password';
                    name  is 'verify';
                    id    is 'verify';
                    title is $title;
                };
            };
            input {
                class is 'submit';
                type  is 'submit';
                name  is 'submit';
                id    is 'submit';
                value is T 'Change';
            };
        };
    } $req, {
        page_title => 'Reset Your Password',
        $args ? %{ $args } : (),
    };
};

template pass_changed => sub {
    my ($self, $req, $args) = @_;
    wrapper {
        h1 { T 'Password Changed' };
        p {
            class is 'success';
            outs T 'W00t! Your password has been changed. So what are you waiting for?';
            a {
                href is $req->auth_uri;
                T 'Go log in!'
            }
        };
    } $req, { page_title => 'Password Changed' };
};

template show_account => sub {
    my ($self, $req, $args) = @_;
    $args ||= {};
    $args->{highlight} //= '';
    wrapper {
        h1 { T 'Edit Your Account' };
        p { T q{Keep your account info up-to-date!} };
        if (my $err = $args->{error}) {
            p {
                class is 'error';
                outs_raw T @{ $err };
            };
        }
        form {
            id      is 'accform';
            action  is $req->uri_for('/account');
            # Browser should send us UTF-8 if that's what we ask for.
            # http://www.unicode.org/mail-arch/unicode-ml/Archives-Old/UML023/0450.html
            enctype is 'application/x-www-form-urlencoded; charset=UTF-8';
            method  is 'post';

            show 'essentials', $req, { id => 'accessentials', nonick => 1, %{ $args } };
            input {
                class is 'submit';
                type  is 'submit';
                name  is 'submit';
                id    is 'submit';
                value is T 'Make it so!';
            };
        };
    } $req, {
        validate_form => '#accform',
        page_title    => 'Edit your account information',
        %{ $args },
    }
};

template essentials => sub {
    my ($self, $req, $args) = @_;
    fieldset {
        id is $args->{id};
        class is 'essentials';
        legend { T 'The Essentials' };
        for my $spec (
            [qw(full_name Name     text),  'Barack Obama', T 'What does your mother call you?'    ],
            [qw(email     Email    email), 'you@example.com', T('Where can we get hold of you?'), 'required email' ],
            [qw(uri       URI      url),   'http://blog.example.com/', T 'Got a blog or personal site?'  ],
            ($args->{nonick} ? () : [qw(nickname  Nickname text),  'bobama', T('By what name would you like to be known? Letters, numbers, and dashes only, please.'), 'required' ]),
            [qw(twitter   Twitter   text),   '@barackobama', T 'Got a Twitter account? Tell us the username and your uploads will be tweeted!'  ],
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
            p { class is 'hint'; $spec->[4] };
        }
    };
};

template show_password => sub {
    my ($self, $req, $args) = @_;
    $args ||= {};
    wrapper {
        h1 { T 'Change Your Password' };
        if (delete $req->session->{password_reset}) {
            p {
                class is 'success';
                T q{Rock on! Your password has been successfully reset.};
            };
        }
        p { T q{There's nothing better than the smell of a fresh password in the morning, don't you agree?} };
        if (my $err = $args->{error}) {
            p {
                class is 'error';
                outs_raw T @{ $err };
            };
        }
        form {
            id      is 'passform';
            action  is $req->uri_for('/account/password');
            enctype is 'application/x-www-form-urlencoded; charset=UTF-8';
            method  is 'post';

            fieldset {
                id is 'accpass';
                legend { T 'Password' };
                for my $spec (
                    ['old_pass', 'Old Password', 'password', T q{What's your current password?} ],
                    ['new_pass', 'New Password', 'password', T q{What would you like your new password to be?}    ],
                    ['new_pass2', 'Verify Password', 'password', T q{What was that again?} ],
                ) {
                    label {
                        attr { for => $spec->[0], title => $spec->[3] };
                        no warnings 'uninitialized';
                        class is 'highlight' if $args->{highlight} eq $spec->[0];
                        T $spec->[1];
                    };
                    input {
                        id    is $spec->[0];
                        name  is $spec->[0];
                        type  is $spec->[2];
                        title is $spec->[3];
                        class is 'required';
                        value is $args->{$spec->[0]} || '';
                    };
                }
            };

            input {
                class is 'submit';
                type  is 'submit';
                name  is 'submit';
                id    is 'submit';
                value is T 'Ch-ch-ch-ch-change it!'
            };
        };
    } $req, {
        validate_form => '#passform',
        page_title    => 'Change your password',
        %{ $args },
    }
};

template show_perms => sub {
    my ($self, $req, $args) = @_;
    wrapper {
        h1 { T 'Your Extension Permissions' };
        p {
            class is 'info';
            T 'Not yet implemented. Sorry. Do come again';
        };
    } $req, { page_title => 'View and edit your extension permissions' };
};

template show_users => sub {
    my ($self, $req, $args) = @_;
    wrapper {
        h1 { T 'User Administration' };
        p {
            class is 'info';
            T 'Not yet implemented. Sorry. Do come again';
        };
    } $req, { page_title => 'Edit user settings' };
};

template show_mirrors => sub {
    my ($self, $req, $args) = @_;
    wrapper {
        h1 { T 'Mirrors' };
        p {
            T q{Thanks for administering rsync mirrors, [_1]. Here's how:}, $req->user;
        };
        ul {
            li { T q{Hit the green ✚ add a new mirror.}};
            li { T q{Hit the green ➔ to edit an existing mirror.}};
            li { T q{Hit the red ▬ to delete an existing mirror.}};
        };
        table {
            id is 'mirrorlist';
            summary is T 'List of project mirrors';
            thead {
                row {
                    th {
                        scope is 'col'; class is 'nobg'; outs T 'Mirrors';
                        span {
                            class is 'control';
                            a {
                                href is $req->uri_for('/admin/mirrors/new');
                                title is T 'Create a new Mirror';
                                img { src is $req->uri_for('/ui/img/add.png') };
                                outs T 'Add';
                            };
                        };
                    };
                    th { scope is 'col'; T 'Frequency' };
                    th { scope is 'col'; T 'Contact'   };
                    th { scope is 'col'; T 'Delete'    };
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
                                class is 'show';
                                title is T q{See details for [_1]}, $row->{uri};
                                href  is $req->uri_for("/admin/mirrors/$row->{uri}");
                                img { src is $forward; };
                                outs $row->{uri};
                            };
                        };
                        cell { T $row->{frequency} };
                        cell {
                            a {
                                href  is URI->new("mailto:$row->{email}")->canonical;
                                title is T q{Email [_1]}, $row->{organization};
                                $row->{organization};
                            };
                        };
                        cell {
                            class is 'actions';
                            form {
                                class is 'delete';
                                action  is $req->uri_for(
                                    "/admin/mirrors/$row->{uri}",
                                    'x-tunneled-method' => 'DELETE',
                                );
                                enctype is 'application/x-www-form-urlencoded; charset=UTF-8';
                                method  is 'post';
                                input {
                                    class is 'button';
                                    type is 'image';
                                    name is 'submit';
                                    src is $req->uri_for("/ui/img/remove.png")
                                };
                            };
                        };
                    }
                }
                unless ($i) {
                    # No distributions.
                    row {
                        class is 'spec';
                        cell {
                            colspan is 3;
                            outs T q{No mirrors yet.};
                            a {
                                id is 'addmirror';
                                href is $req->uri_for('/admin/mirrors/new');
                                T 'Add one now!';
                            };
                        };
                    };
                }
            }
        };
    } $req, {
        page_title => 'Administer project rsync mirrors',
        js => 'PGXN.init_mirrors()',
        $args ? %{ $args } : (),
    };
};

template show_mirror => sub {
    my ($self, $req, $args) = @_;
    my %highlight = map { $_ => 1 } @{ $args->{highlight} || [] };
    my $update = $args->{update};
    wrapper {
        h1 { T $update ? 'Edit Mirror' : 'New Mirror' };
        p { T 'All fields except "Note" are required. Thanks for keeping the rsync mirror index up-to-date!' };
        if (my $err = $args->{error}) {
            p {
                class is 'error';
                outs_raw T @{ $err };
            };
        }
        form {
            id      is 'mirrorform';
            if ($update) {
                # We don't want the "/auth" bit, but do want the rest of the
                # path, as it has the URL being edited.
                (my $path = join '/', $req->uri->path_segments) =~ s{^/auth}{};
                action is $req->uri_for($path, 'x-tunneled-method' => 'put');
            } else {
                action  is $req->uri_for('/admin/mirrors');
            }
            enctype is 'application/x-www-form-urlencoded; charset=UTF-8';
            method  is 'post';

            fieldset {
                id is 'mirroressentials';
                class is 'essentials';
                legend { T 'The Essentials' };
                for my $spec (
                    [qw(uri       URI      url),   'http://example.com/pgxn', T('What is the base URI for the mirror?'), 'required url' ],
                    [qw(organization Organization text),   'Full Organization Name', T('Whom should we blame when the mirror dies?'), 'required' ],
                    [qw(email Email email),   'pgxn@example.com', T('Where can we get hold of the responsible party?'), 'required email' ],
                    [qw(frequency Frequency text),   'daily/bidaily/.../weekly', T('How often is the mirror updated?'), 'required' ],
                    [qw(location Location text),   'city, (area?, )country, continent (lon lat)', T('Where can we find this mirror, geographically speaking?'), 'required' ],
                    ['timezone', 'TZ', 'text',   'area/Location zoneinfo tz', T('In what time zone can we find the mirror?'), 'required' ],
                    [qw(bandwidth Bandwidth text),   '1Gbps, 100Mbps, DSL, etc.', T('How big is the pipe?'), 'required' ],
                    [qw(src Source url),   'rsync://from.which.host/is/this/site/mirroring/from/', T('From what source is the mirror syncing?'), 'required' ],
                    [qw(rsync Rsync url),   'rsync://where.your.host/is/offering/a/mirror/', T('Is there a public rsync interface from which other hosts can mirror?') ],
                ) {
                    label {
                        attr { for => $spec->[0], title => $spec->[4] };
                        class is 'highlight' if $highlight{$spec->[0]};
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
                                          ($highlight{$spec->[0]} ? 'highlight' : ()),
                                      );
                        class is $class if $class;
                        placeholder is $spec->[3];
                    };
                    p { class is 'hint'; $spec->[4] };
                }
            };

            fieldset {
                id is 'mirrornotes';
                legend { T 'Notes' };
                my $hint = T 'Anything else we should know about this mirror?';
                label {
                    attr { for => 'notes', title => $hint };
                    T 'Notes';
                };
                textarea {
                    id    is 'notes';
                    name  is 'notes';
                    title is $hint;
                    $args->{notes} || '';
                };
                p { class is 'hint'; $hint };
            };


            input {
                class is 'submit';
                type  is 'submit';
                name  is 'submit';
                id    is 'submit';
                value is T 'Mirror, Mirror';
            };
        };
    } $req, {
        page_title => 'Enter the mirror information provided by the contact',
        validate_form => '#mirrorform',
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
