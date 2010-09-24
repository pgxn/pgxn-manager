package PGXN::Manager::Controller;

use 5.12.0;
use utf8;
use PGXN::Manager;
use aliased 'PGXN::Manager::Request';
use PGXN::Manager::Templates;
use aliased 'PGXN::Manager::Distribution';
use HTML::Entities;
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
    return $self->render('/403', { req => $req, code => 403 })
        unless $req->user_is_admin;
    my $sth = PGXN::Manager->conn->run(sub {
        shift->prepare(q{
            SELECT nickname, full_name, email, uri, why
              FROM users
             WHERE status = 'new'
        });
    });
    $sth->execute;
    $self->render('/moderate', { req => $req, vars => { sth => $sth }});
}

sub upload {
    my $self = shift;
    my $req  = Request->new(shift);
    my $upload = $req->uploads->{distribution};
    my $dist = Distribution->new(
        archive  => $upload->path,
        basename => $upload->basename,
        owner    => $req->remote_user,
    );
    $dist->process or $self->render_error($dist->error);
    $self->render('/done', { req => $req });
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

=head2 Methods

=head3 C<render>

  $root->render('/home', $req, @template_args);

Renders the response to the request using L<PGXN::Manager::Templates>.

=head3 C<redirect>

  $root->render('/home', $req);

Redirect the request to a new page.

=head1 Author

David E. Wheeler <david.wheeler@pgexperts.com>

=head1 Copyright and License

Copyright (c) 2010 David E. Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.
