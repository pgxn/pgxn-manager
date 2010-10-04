package PGXN::Manager::Controller;

use 5.12.0;
use utf8;
use PGXN::Manager;
use aliased 'PGXN::Manager::Request';
use PGXN::Manager::Locale;
use PGXN::Manager::Templates;
use aliased 'PGXN::Manager::Distribution';
use HTML::Entities;
use JSON::XS;
use Encode;
use namespace::autoclean;

Template::Declare->init( dispatch_to => ['PGXN::Manager::Templates'] );

my %message_for = (
    success   => q{Success},
    forbidden => q{Sorry, you do not have permission to access this resource.},
    notfound  => q{Resource not found.},
    conflict  => q{There is a conflict in the current state of the resource.}, # Bleh
);

my %code_for = (
    success   => 200,
    seeother  => 303,
    forbidden => 403,
    notfound  => 404,
    conflict  => 409,
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

sub respond_with {
    my ($self, $status, $req, $err) = @_;
    my $code = $code_for{$status} or die qq{No error code for status "$status"};

    return $self->render("/$status", { req => $req, code => $code, maketext => $err })
        unless $req->is_xhr;

    my $l  = PGXN::Manager::Locale->accept($req->env->{HTTP_ACCEPT_LANGUAGE});
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

sub home {
    my $self = shift;
    return $self->render('/home', { env => shift });
}

sub about {
    my $self = shift;
    return $self->render('/about', { env => shift });
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
                name
                email
                why
                twitter
            )}, $params->{uri} || undef,
        );

        # Success!
        return $self->respond_with('success', $req) if $req->is_xhr;

        # XXX Consider returning 201 and URI to the user profile?
        $req->session->{name} = $req->param('nickname');
        return $self->redirect('/thanks', $req);

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
            SELECT nickname, full_name, email, uri, why
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

    # XXX Send the user an email on failure. Maybe require a note to be
    # entered by the admin?

    # XXX On success, reset the user's password and send an email.

    # Simple response for XHR request.
    return $self->respond_with('success', $req) if $req->is_xhr;

    # Redirect for normal request.
    return $self->redirect('/auth/admin/moderate', $req);
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
            "/auth/distributions/$meta->{name}/$meta->{version}",
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

=head2 Methods

=head3 C<render>

  $root->render('/home', $req, @template_args);

Renders the response to the request using L<PGXN::Manager::Templates>.

=head3 C<redirect>

  $root->render('/home', $req);

Redirect the request to a new page.

=head3 C<respond_with>

  $root->respond_with('forbidden', $req);

Returns simple response to the requester. This method detects the preferred
response data type and responds accordingly. A simple status message is
included in the body of the response. The currently-supported responses are:

=over

=item C<success>

=item C<forbidden>

=item C<notfound>

=back

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
