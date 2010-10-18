package PGXN::Manager::Controller;

use 5.12.0;
use utf8;
use PGXN::Manager;
use aliased 'PGXN::Manager::Request';
use PGXN::Manager::Locale;
use PGXN::Manager::Templates;
use aliased 'PGXN::Manager::Distribution';
use HTML::Entities;
use Email::MIME;
use Email::Sender::Simple;
use JSON::XS;
use Encode;
use namespace::autoclean;

Template::Declare->init( dispatch_to => ['PGXN::Manager::Templates'] );

my %message_for = (
    success    => q{Success},
    forbidden  => q{Sorry, you do not have permission to access this resource.},
    notfound   => q{Resource not found.},
    notallowed => q{The requted method is not allowed for the resource.},
    conflict   => q{There is a conflict in the current state of the resource.}, # Bleh
    gone       => q{The resource is no longer available.},
);

my %code_for = (
    success    => 200,
    seeother   => 303,
    forbidden  => 403,
    notfound   => 404,
    notallowed => 405,
    conflict   => 409,
    gone       => 410,
);

sub render {
    my ($self, $template, $p) = @_;
    my $req = $p->{req} ||= Request->new($p->{env});
    my $res = $req->new_response($p->{code} || 200);
    $res->content_type($p->{type} || 'text/html; charset=UTF-8');
    $res->body(encode_utf8 +Template::Declare->show($template, $p->{req}, $p->{vars}));
    return $res->finalize;
}

sub redirect {
    my ($self, $uri, $req, $code) = @_;
    my $res = $req->new_response;
    $res->redirect($req->uri_for($uri), $code || $code_for{see_other});
    return $res->finalize;
}

sub missing {
    my ($self, $env, $data) = @_;
    my $res = $self->respond_with(
        $data->{code} == 404 ? 'notfound' : 'notallowed',
        PGXN::Manager::Request->new($env),
    );
    push @{ $res->[1] }, @{ $data->{headers} };
    return $res;
}

sub respond_with {
    my ($self, $status, $req, $err) = @_;
    my $code = $code_for{$status} or die qq{No error code for status "$status"};

    return $self->render("/$status", {
        req  => $req,
        code => $code,
        vars => { maketext => $err }
    }) unless $req->is_xhr;

    my $l = PGXN::Manager::Locale->accept($req->env->{HTTP_ACCEPT_LANGUAGE});
    my $msg = do {
        if (ref $err) {
            $l->maketext(@$err);
        } else {
            my $txt = $message_for{ $status } or die qq{No message for status "$status"};
            $l->maketext($txt);
        }
    };

    my $type;
    given (scalar $req->respond_with) {
        when ('html') {
            $msg = '<p class="error">' . encode_utf8 encode_entities($msg) . '</p>';
            $type = 'text/html; charset=UTF-8';
        } when ('json') {
            $msg = encode_json { message => $msg };
            $type = 'application/json';
        }
        when ('atom') {
            # XXX WTF to do here?
            $type = 'text/plain; charset=UTF-8';
            $msg = encode_utf8 $msg;
        }
        default {
            # Text is just text.
            $type = 'text/plain';
            $msg = encode_utf8 $msg;
        }
    }
    return [$code, ['Content-Type' => $type], [$msg]];
}

sub root {
    my $self = shift;
    return $self->redirect('/pub/', Request->new(shift));
}

sub home {
    my $self = shift;
    return $self->render('/home', { env => shift });
}

sub about {
    my $self = shift;
    return $self->render('/about', { env => shift });
}

sub contact {
    my $self = shift;
    return $self->render('/contact', { env => shift });
}

sub request {
    my $self = shift;
    return $self->render('/request', { env => shift });
}

sub register {
    my $self   = shift;
    my $req    = Request->new(shift);
    my $params = $req->body_parameters;

    if ($params->{nickname} && $params->{email} && (!$params->{why} || $params->{why} !~ /\w+/ || length $params->{why} < 5)) {
        delete $params->{why};
        return $self->render('/request', { req => $req, code => $code_for{conflict}, vars => {
            %{ $params },
            highlight => 'why',
            error => [
                q{You forgot to tell us why you want an account. Is it because you're such a rockin PostgreSQL developer that we just can't do without you? Don't be shy, toot your own horn!}
            ],
        }});
    }

    PGXN::Manager->conn->run(sub {
        $_->do(
            q{SELECT insert_user(
                nickname  := ?,
                password  := rand_str_of_len(5),
                full_name := ?,
                email     := ?,
                why       := ?,
                twitter   := ?,
                uri       := ?
            );},
            undef,
            @{ $params }{qw(
                nickname
                full_name
                email
                why
                twitter
                uri
            )}
        );

        # Success! Notify the admins.
        my $host = $req->remote_host || $req->address;
        my $name = $params->{full_name} ? "     Name: $params->{full_name}\n" : '';
        my $twit = $params->{twitter}   ? "  Twitter: http://twitter.com/$params->{twitter}\n" : '';
        my $uri  = $params->{uri}       ? "      URI: $params->{uri}\n" : '';
        (my $why = $params->{why}) =~ s/^/> /g;
        my $email = Email::MIME->create(
            header     => [
                From => PGXN::Manager->config->{admin_email},
                To   => PGXN::Manager->config->{alert_email},
                Subject => "New User Request for $params->{nickname}",
            ],
            attributes => {
                content_type => 'text/plain',
                charset      => 'UTF-8',
            },
            body => "A new PGXN account has been requted from $host:\n\n"
                  . $name
                  . " Nickname: $params->{nickname}\n"
                  . "    Email: $params->{email}\n"
                  . $uri
                  . $twit
                  . "   Reason:\n\n$why\n"
        );
        Email::Sender::Simple->send($email, {
            transport => PGXN::Manager->email_transport
        });

        return $self->respond_with('success', $req) if $req->is_xhr;

        # XXX Consider returning 201 and URI to the user profile?
        $req->session->{name} = $req->param('nickname');
        return $self->redirect('/pub/account/thanks', $req);

    }, sub {
        # Failure!
        my $err = shift;
        my ($msg, $highlight);
        given ($err->state) {
            when ('23505') {
                # Unique constraint violation.
                if ($err->errstr =~ /\busers_pkey\b/) {
                    $highlight = 'nickname';
                    $msg = [
                        'The Nickname “[_1]” is already taken. Sorry about that.',
                        delete $params->{nickname}
                    ];
                } else {
                    if ($req->respond_with eq 'html') {
                        $msg = [
                            'Looks like you might already have an account. Need to <a href="[_1]">reset your password</a>?',
                            $req->uri_for('/reset', email => delete $params->{email}),
                        ];
                    } else {
                        $msg = ['Looks like you might already have an account. Need to reset your password?'];
                        delete $params->{email},
                    }
                }
            } when ('23514') {
                # Domain label violation.
                given ($err->errstr) {
                    when (/\blabel_check\b/) {
                    $highlight = 'nickname';
                        $msg = [
                            'Sorry, the nickname “[_1]” is invalid. Your nickname must start with a letter, end with a letter or digit, and otherwise contain only letters, digits, or hyphen. Sorry to be so strict.',
                            encode_entities delete $params->{nickname},
                        ];
                    } when (/\bemail_check\b/) {
                        $highlight = 'email';
                        $msg = [
                            q{Hrm, “[_1]” doesn't look like an email address. Care to try again?},
                            encode_entities delete $params->{email},
                        ];
                    } when (/\buri_check\b/) {
                        $highlight = 'uri';
                        $msg = [
                            q{Hrm, “[_1]” doesn't look like a URI. Care to try again?},
                            encode_entities delete $params->{uri},
                        ];
                    } default {
                        die $err;
                    }
                }
            }
            default {
                die $err;
            }
        }

        # Respond with error code for XHR request.
        return $self->respond_with('conflict', $req, $msg) if $req->is_xhr;

        $self->render('/request', { req => $req, code => $code_for{conflict}, vars => {
            %{ $params },
            highlight => $highlight,
            error     => $msg,
        }});
    });
}

sub forgotten {
    my $self = shift;
    return $self->render('/forgotten', { env => shift });
}

sub send_reset {
    my $self = shift;
    my $req  = Request->new(shift);
    my $who  = $req->body_parameters->{who};

    my $token = PGXN::Manager->conn->run(sub {
        my $sql = $who =~ /@/
            ? 'SELECT forgot_password(nickname) FROM users WHERE email = ?'
            : 'SELECT forgot_password(?)';
        shift->selectcol_arrayref($sql, undef, $who)->[0];
    });

    if ($token) {
        my $uri = $req->uri_for("/account/reset/$token->[0]");
        # Create and send the email.
        my $email = Email::MIME->create(
            header     => [
                From => PGXN::Manager->config->{admin_email},
                To   => $token->[1],
                Subject => 'Reset Your Password',
            ],
            attributes => {
                content_type => 'text/plain',
                charset      => 'UTF-8',
            },
            body => "Click the link below to reset your PGXN password. But do it soon!\n"
                  . "This link will expire in 24 hours:\n\n"
                  . "    $uri\n\n"
                  . "Best,\n\n"
                  . "PGXN Management\n"
        );
        Email::Sender::Simple->send($email, {
            transport => PGXN::Manager->email_transport
        });
    }

    # Simple response for XHR request.
    return $self->respond_with('success', $req) if $req->is_xhr;

    # Redirect for normal request.
    $req->session->{reset_sent} = 1;
    return $self->redirect('/', $req);
}

sub reset_form {
    my $self = shift;
    return $self->render('/reset_form', { env => shift });
}

sub reset_pass {
    my $self  = shift;
    my $req   = Request->new(shift);
    my $token = shift->{tok};

    my $new_pass = $req->body_parameters->{new_pass};
    if ($new_pass ne $req->body_parameters->{verify}) {
        return $self->render('/reset_form', { req => $req, vars => { nomatch => 1 } });
    }

    PGXN::Manager->conn->run(sub {
        shift->selectcol_arrayref(
            'SELECT reset_password(?, ?)',
            undef, $token, $new_pass
        )->[0];
    }) or return $self->respond_with(
        'gone',
        $req,
        ['Sorry, but that password reset token has expired.']
    );

    # Simple response for XHR request.
    return $self->respond_with('success', $req) if $req->is_xhr;

    # Redirect for normal request.
    return $self->redirect('/pub/account/changed', $req);
}

sub pass_changed {
    my $self = shift;
    return $self->render('/pass_changed', { env => shift });
}

sub thanks {
    my $self = shift;
    my $req  = Request->new(shift);
    return $self->render('/thanks', {req => $req, vars => {
        name => delete $req->session->{name}
    }});
}

sub moderate {
    my $self = shift;
    my $req  = Request->new(shift);
    return $self->respond_with('forbidden', $req) unless $req->user_is_admin;

    my $sth = PGXN::Manager->conn->run(sub {
        shift->prepare(q{
            SELECT nickname::text, full_name::text, email::text, uri::text, why
              FROM users
             WHERE status = 'new'
             ORDER BY nickname
        });
    });
    $sth->execute;
    $self->render('/moderate', { req => $req, vars => { sth => $sth }});
}

sub set_status {
    my $self = shift;
    my $req  = Request->new(shift);
    return $self->respond_with('forbidden', $req) unless $req->user_is_admin;
    my $params = shift;
    my $status = $req->body_parameters->{status};

    PGXN::Manager->conn->run(sub {
        shift->selectcol_arrayref(
            'SELECT set_user_status(?, ?, ?)',
            undef, $req->user, $params->{nick}, $status
        )->[0];
    }) or return $self->respond_with('notfound', $req);

    my ($to, $subj, $body);
    if ($status eq 'active') {
        # Generate a password-changing token.
        my $token = PGXN::Manager->conn->run(sub {
            shift->selectcol_arrayref(
                'SELECT forgot_password(?)',
                undef, $params->{nick}
            )->[0];
        });

        my $uri = $req->uri_for("/account/reset/$token->[0]");
        $to   = $token->[1];
        $subj = 'Welcome to PGXN!';
        $body = "Your PGXN account request has been approved. Ready to get started?\n"
              . "Great! Just click this link to set your password and get going:\n\n"
              . "    $uri\n\n"
              . "Best,\n\n"
              . "PGXN Management\n";
    } else {
        # XXX Maybe require a note to be entered by the admin?
        $to   = PGXN::Manager->conn->run(sub {
            shift->selectcol_arrayref(
                'SELECT email FROM users WHERE nickname = ?',
                undef, $params->{nick}
            )->[0];
        });
        $subj = 'Account Request Rejected';
        $body = "I'm sorry to report that your request for a PGXN account has been\n"
              . "rejected. If you think there has been an error, please reply to this\n"
              . "message\n\n"
              . "Best,\n\n"
              . "PGXN Management\n";
    }

    # Create and send the email.
    my $email = Email::MIME->create(
        header     => [
            From => PGXN::Manager->config->{admin_email},
            To   => Email::Address->new( $params->{nick}, $to ),
            Subject => $subj,
        ],
        attributes => {
            content_type => 'text/plain',
            charset      => 'UTF-8',
        },
        body => $body,
    );
    Email::Sender::Simple->send($email, {
        transport => PGXN::Manager->email_transport
    });

    # Simple response for XHR request.
    return $self->respond_with('success', $req) if $req->is_xhr;

    # Redirect for normal request.
    return $self->redirect('/admin/moderate', $req);
}

sub show_upload {
    my $self = shift;
    return $self->render('/show_upload', { env => shift });
}

sub upload {
    my $self = shift;
    my $req  = Request->new(shift);
    my $upload = $req->uploads->{archive};
    my $dist = Distribution->new(
        archive  => $upload->path,
        basename => $upload->basename,
        owner    => $req->user,
    );

    if ($dist->process) {
        # Success!
        return $self->respond_with('success', $req) if $req->is_xhr;
        $req->session->{success} = 1;
        my $meta = $dist->distmeta;
        return $self->redirect(
            "/distributions/$meta->{name}/$meta->{version}",
            $req
        );
    }

    # Error.
    return $self->respond_with(
        'conflict', $req, scalar $dist->error
    ) if $req->is_xhr;

    # Re-display the form.
    return $self->render('/show_upload', {
        req => $req,
        code => $code_for{conflict},
        vars => { error => scalar $dist->error }
    });
}

sub distributions {
    my $self = shift;
    my $req  = Request->new(shift);

    my $sth = PGXN::Manager->conn->run(sub {
        shift->prepare(q{
            SELECT name, version, relstatus,
                   to_char(created_at, 'IYYY-MM-DD') AS date
              FROM distributions
             WHERE owner = ?
             ORDER BY name, version USING <
        });
    });
    $sth->execute($req->user);
    $self->render('/distributions', { req => $req, vars => { sth => $sth }});
}

sub distribution {
    my $self = shift;
    my $req  = Request->new(shift);
    my $p    = shift;

    my $dist = PGXN::Manager->conn->run(sub {
        shift->selectrow_hashref(q{
            SELECT name::text, version, abstract, description, relstatus, owner,
                   sha1, meta, extensions, tags::text[], owner = ? AS is_owner
              FROM distribution_details
             WHERE name    = ?
               AND version = ?
        }, undef, $req->user, $p->{dist}, $p->{version});
    }) or return $self->respond_with('notfound', $req);

    return $self->respond_with('forbidden', $req) unless $dist->{is_owner};

    $self->render('/distribution', { req => $req, vars => { dist => $dist }});
}

sub show_account {
    my $self = shift;
    my $req  = Request->new(shift);

    my $user = PGXN::Manager->conn->run(sub {
        shift->selectrow_hashref(q{
            SELECT nickname::text, email::text, uri::text, full_name::text,
                   twitter::text
              FROM users
             WHERE nickname = ?
        }, undef, $req->user);
    });

    return $self->render('/show_account', { req => $req, vars => $user });
}

sub update_account {
    my $self   = shift;
    my $req    = Request->new(shift);
    my $params = $req->body_parameters;

    PGXN::Manager->conn->run(sub {
        $_->do(
            q{SELECT update_user(
                nickname  := ?,
                full_name := ?,
                email     := ?,
                twitter   := ?,
                uri       := ?
            );},
            undef,
            $req->user,
            @{ $params }{qw(
                full_name
                email
                twitter
                uri
            )}
        );

        # Success!
        return $self->respond_with('success', $req) if $req->is_xhr;

        $req->session->{updated} = 1;
        return $self->redirect($req->path_info, $req);

    }, sub {
        # Failure!
        my $err = shift;
        my ($msg, $highlight);
        given ($err->state) {
            when ('23505') {
                # Unique constraint violation.
                $msg = [
                    'Do you have two accounts? Because the email address “[_1]” is associated with another account.',
                    delete $params->{email}
                ];
                $params->{email} = PGXN::Manager->conn->run(sub{
                    shift->selectcol_arrayref(
                        'SELECT email FROM users WHERE nickname = ?',
                        undef, $req->user
                    )->[0];
                });
            } when ('23514') {
                # Domain label violation.
                given ($err->errstr) {
                    when (/\bemail_check\b/) {
                        $highlight = 'email';
                        $msg = [
                            q{Hrm, “[_1]” doesn't look like an email address. Care to try again?},
                            encode_entities delete $params->{email},
                        ];
                    } when (/\buri_check\b/) {
                        $highlight = 'uri';
                        $msg = [
                            q{Hrm, “[_1]” doesn't look like a URI. Care to try again?},
                            encode_entities delete $params->{uri},
                        ];
                    } default {
                        die $err;
                    }
                }
            }
            default {
                die $err;
            }
        }

        # Respond with error code for XHR request.
        return $self->respond_with('conflict', $req, $msg) if $req->is_xhr;

        $self->render('/show_account', { req => $req, code => $code_for{conflict}, vars => {
            %{ $params },
            highlight => $highlight,
            error     => $msg,
        }});
    });
}

sub show_password {
    my $self = shift;
    return $self->render('/show_password', { env => shift });
}

sub update_password {
    my $self   = shift;
    my $req    = Request->new(shift);
    my $params = $req->body_parameters;

    my $err;
    if ($params->{new_pass} ne $params->{new_pass2}) {
        $err = q{D'oh! The passwords you typed in don't match. Would you mind trying again? Thanks.};
    } elsif (length $params->{new_pass} < 4) {
        $err = q{So sorry! Passwords must be at least four characters long.};
    }

    if ($err) {
        return $self->respond_with('conflict', $req, [$err]) if $req->is_xhr;
        return $self->render('/show_password', {
            req => $req,
            code => $code_for{conflict},
            vars => { error => [ $err ] }
        });
    }

    my $ret = PGXN::Manager->conn->run(sub {
        shift->selectcol_arrayref(
            'SELECT change_password(?, ?, ?)',
            undef, $req->user, $params->{old_pass}, $params->{new_pass}
        )->[0];
    });

    if ($ret) {
        # Simple response for XHR request.
        return $self->respond_with('success', $req) if $req->is_xhr;

        # Redirect for normal request.
        $req->session->{password_reset} = 1;
        return $self->redirect($req->path_info, $req);
    }

    # Failed.
    my $err = [
        q{I don't think that was really your existing password. Care to try again?}
    ];
    return $self->respond_with('conflict', $req, $err) if $req->is_xhr;

    return $self->render('/show_password', {
        req => $req,
        code => $code_for{conflict},
        vars => { error => $err }
    });
}

sub show_perms {
    my $self = shift;
    return $self->render('/show_perms', { env => shift });
}

sub show_users {
    my $self = shift;
    return $self->render('/show_users', { env => shift });
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

=head3 C<root>

  PGXN::Manager::Controller->root($env);

Handles request for /, redirecting to C</pub>.

=head3 C<home>

  PGXN::Manager::Controller->home($env);

Displays the HTML for the home page.

=head3 C<about>

  PGXN::Manager::Controller->about($env);

Displays the HTML for the "About" page.

=head3 C<contact>

  PGXN::Manager::Controller->contact($env);

Displays the HTML for the "Contact" page.

=head3 C<auth>

  PGXN::Manager::Controller->auth($env);

Displays the HTML for the authorized user home page.

=head3 C<upload>

  PGXN::Manager::Controller->upload($env);

Handles uploads to PGXN.

=head3 C<request>

Handles requests for a form to to request a user account.

=head3 C<register>

Handles requests to register a user account.

=head3 C<thanks>

Thanks the user for registering for an account.

=head3 C<moderate>

Administrative interface for moderating user requests.

=head3 C<set_status>

Accepts C<POST>s for an administrator to change the status of a user.

=head3 C<show_upload>

Shows the form for uploading a distribution archive.

=head3 C<distributions>

Shows list of distributions owned by a user.

=head3 C<distribution>

Shows details of a single distribution.

=head3 C<forgotten>

Shows for for user to fill out when password forgotten.

=head3 C<send_reset>

Handles POST from C<forgotten> form. Generates a reset token and sends a reset
email.

=head3 C<reset_form>

Displays the form for a user to change her password.

=head3 C<reset_pass>

Handles the POST with a token for a user to change her password.

=head3 C<pass_changed>

Displays a page when a user has successfully reset her password.

=head3 C<show_account>

Shows a user's account information in a form for updating.

=head3 C<update_account>

Handles a POST request to update an account.

=head3 C<show_password>

Shows a user's password information in a form for updating.

=head3 C<update_password>

Handles a POST request to update an password.

=head3 C<show_perms>

Shows a user's extension permissions.

=head3 C<show_users>

Shows interface for administering users.

=head2 Methods

=head3 C<render>

  $controller->render('/home', $req, @template_args);

Renders the response to the request using L<PGXN::Manager::Templates>.

=head3 C<redirect>

  $controller->render('/home', $req);

Redirect the request to a new page.

=head3 C<respond_with>

  $controller->respond_with('forbidden', $req);

Returns simple response to the requester. This method detects the preferred
response data type and responds accordingly. A simple status message is
included in the body of the response. The currently-supported responses are:

=head3 C<missing>

  $controller->missing($env, $data);

Handles 404 and 405 errors from Router::Resource.

=over

=item C<success>

=item C<forbidden>

=item C<notfound>

=back

=head1 Author

David E. Wheeler <david.wheeler@pgexperts.com>

=head1 Copyright and License

Copyright (c) 2010 David E. Wheeler.

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
