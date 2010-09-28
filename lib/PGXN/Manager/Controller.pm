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

sub render {
    my ($self, $template, $p) = @_;
    my $req = $p->{req} ||= Request->new($p->{env});
    my $res = $req->new_response($p->{code} || 200);
    $res->content_type($p->{type} || 'text/html; charset=UTF-8');
    $res->body(encode_utf8 +Template::Declare->show($template, $p->{req}, $p->{vars}));
    return $res->finalize;
}

sub redirect {
    my ($self, $uri, $req) = @_;
    my $res = $req->new_response;
    $res->redirect($uri);
    return $res->finalize;
}

my %message_for = (
    success   => q{Success},
    forbidden => q{Sorry, you do not have permission to access this resource.},
    notfound  => q{Resource not found.},
);

my %code_for = (
    success   => 200,
    forbidden => 403,
    notfound  => 404,
);

sub respond_with {
    my ($self, $status, $req) = @_;
    my $code = $code_for{$status} or die qq{No error code for status "$status"};

    return $self->render("/$status", { req => $req, code => $code })
        unless $req->is_xhr;

    my $l    = PGXN::Manager::Locale->accept($req->env->{HTTP_ACCEPT_LANGUAGE});
    my $msg  = $message_for{ $status } or die qq{No message for status "$status"};
    $msg     = $l->maketext($msg);

    my $type;
    given (scalar $req->respond_with) {
        when ('html') {
            $msg = '<p class="error">' . encode_entities(encode_utf8 $msg) . '</p>';
            $type = 'text/html; charset=UTF-8';
        } when ('json') {
            $msg = encode_json { message => $msg };
            $type = 'application/json';
        }
        when ('atom') {
            # XXX WTF to do here?
            $type = 'text/plain';
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
        return $self->render('/request', { req => $req, code => 409, vars => {
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
                uri       := ?
            );},
            undef,
            @{ $params }{qw(
                nickname
                name
                email
                why
            )}, $params->{uri} || undef,
        );

        # Success!
        # XXX Consider returning 201 and URI to the user profile.
        $req->session->{name} = $req->param('name') || $req->param('nickname');
        $self->redirect('/thanks', $req);

    }, sub {
        # Failure!
        my $err = shift;
        my ($msg, $code, $highlight);
        given ($err->state) {
            when ('23505') {
                # Unique constraint violation.
                $code = 409;
                if ($err->errstr =~ /\busers_pkey\b/) {
                    $highlight = 'nickname';
                    $msg = [
                        'The Nickname “[_1]” is already taken. Sorry about that.',
                        delete $params->{nickname}
                    ];
                } else {
                    $msg = [
                        'Looks like you might already have an account. Need to <a href="/reset?email=[_1]">reset your password</a>?',
                        encode_entities delete $params->{email},
                    ];
                }
            } when ('23514') {
                # Domain label violation.
                $code = 409;
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

        $self->render('/request', { req => $req, code => $code, vars => {
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

sub accept {
    my $ret = shift->_set_status(@_, 'active');
    # XXX Reset the user's password and send an email.
    return $ret;
}

sub reject {
    my $ret = shift->_set_status(@_, 'deleted');
    # XXX Send the user an email. Maybe require a note to be entered by the
    # admin?
    return $ret;
}

sub _set_status {
    my $self = shift;
    my $req  = Request->new(shift);
    my ($params, $status) = @_;
    return $self->respond_with('forbidden', $req) unless $req->user_is_admin;

    PGXN::Manager->conn->run(sub {
        shift->selectcol_arrayref(
            'SELECT set_user_status(?, ?, ?)',
            undef, $req->user, $params->{nick}, $status
        )->[0];
    }) or return $self->respond_with('notfound', $req);

    # Simple response for XHR request.
    return $self->respond_with('success', $req) if $req->is_xhr;

    # Redirect for normal request.
    return $self->redirect('/auth/admin/moderate', $req);
}

sub upload {
    # my $self = shift;
    # my $req  = Request->new(shift);
    # my $upload = $req->uploads->{distribution};
    # my $dist = Distribution->new(
    #     archive  => $upload->path,
    #     basename => $upload->basename,
    #     owner    => $req->remote_user,
    # );
    # $dist->process or $self->respond_with('XXX', $req, $dist->error);
    # $self->render('/done', { req => $req });
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

=head3 C<accept>

Accepts a user account request.

=head3 C<reject>

Rejects a user account request.

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

Copyright (c) 2010 David E. Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.
