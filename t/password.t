#!/usr/bin/env perl

use 5.12.0;
use utf8;

use Test::More tests => 280;
#use Test::More 'no_plan';
use Plack::Test;
use HTTP::Request::Common;
use PGXN::Manager;
use PGXN::Manager::Router;
use HTTP::Message::PSGI;
use Test::XML;
use Test::XPath;
use MIME::Base64;
use lib 't/lib';
use TxnTest;
use XPathTest;

my $app  = PGXN::Manager::Router->app;
my $mt   = PGXN::Manager::Locale->accept('en');
my $uri  = '/auth/account/password';
my $head = {
    h1            => 'Change Your Password',
    validate_form => '#passform',
    page_title    => 'Change your password',
};

# Connect without authenticating.
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET $uri), "GET $uri";
    is $res->code, 401, 'Should get 401 response';
    like $res->content, qr/Authorization required/,
        'The body should indicate need for authentication';
};

# Connect as authenticated user.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb   = shift;
    my $user = TxnTest->user;
    my $req  = GET $uri, Authorization => 'Basic ' . encode_base64("$user:****");

    ok my $res = $cb->($req), "Get $uri with auth token";
    ok $res->is_success, 'Response should be success';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($req));
    $req->env->{REMOTE_USER} = $user;
    XPathTest->test_basics($tx, $req, $mt, $head);

    $tx->ok('/html/body/div[@id="content"]', 'Look at the content', sub {
        $tx->is('count(./*)', 3, '... It should have three subelements');
        $tx->is(
            './p',
            $mt->maketext(q{There's nothing better than the smell of a fresh password in the morning, don't you agree?}),
            '... Intro paragraph should be set'
        );
    });

    # Now examine the form.
    $tx->ok('/html/body/div[@id="content"]/form[@id="passform"]', sub {
        for my $attr (
            [action  => $req->uri_for('/auth/account/password')],
            [enctype => 'application/x-www-form-urlencoded; charset=UTF-8'],
            [method  => 'post']
        ) {
            $tx->is(
                "./\@$attr->[0]",
                $attr->[1],
                qq{... Its $attr->[0] attribute should be "$attr->[1]"},
            );
        }
        $tx->is('count(./*)', 2, '... It should have two subelements');
        $tx->ok('./fieldset', '... Test fieldset', sub {
            $tx->is('./@id', 'accpass', '...... It should have the proper id');
            $tx->is('count(./*)', 7, '...... It should have 7 subelements');
            $tx->is(
                './legend',
                $mt->maketext('Password'),
                '...... Its legend should be correct'
            );
            my $i = 0;
            for my $spec (
                {
                    id    => 'old_pass',
                    title => $mt->maketext(q{What's your current password?}),
                    label => $mt->maketext('Old Password'),
                    type  => 'password',
                    class => 'required',
                },
                {
                    id    => 'new_pass',
                    title => $mt->maketext(q{What would you like your new password to be?}),
                    label => $mt->maketext('New Password'),
                    type  => 'password',
                    class => 'required',
                },
                {
                    id    => 'new_pass2',
                    title => $mt->maketext(q{What was that again?}),
                    label => $mt->maketext('Verify Password'),
                    type  => 'password',
                    class => 'required',
                },
            ) {
                ++$i;
                $tx->ok("./label[$i]", "...... Test $spec->{id} label", sub {
                    $_->is('./@for', $spec->{id}, '......... Check "for" attr' );
                    $_->is('./@title', $spec->{title}, '......... Check "title" attr' );
                    $_->is('./text()', $spec->{label}, '......... Check its value');
                });
                $tx->ok("./input[$i]", "...... Test $spec->{id} input", sub {
                    $_->is('./@id', $spec->{id}, '......... Check "id" attr' );
                    $_->is('./@name', $spec->{id}, '......... Check "name" attr' );
                    $_->is('./@type', $spec->{type}, '......... Check "type" attr' );
                    $_->is('./@title', $spec->{title}, '......... Check "title" attr' );
                    $_->is('./@class', $spec->{class}, '......... Check "class" attr' );
                });
            }
        });
        $tx->ok('./input[@type="submit"]', '... Test input', sub {
            for my $attr (
                [id => 'submit'],
                [name => 'submit'],
                [class => 'submit'],
                [value => $mt->maketext('Ch-ch-ch-ch-change it!')],
            ) {
                $_->is(
                    "./\@$attr->[0]",
                    $attr->[1],
                    qq{...... Its $attr->[0] attribute should be "$attr->[1]"},
                );
            }
        });
    });
};

# Okay, let's submit the form.
test_psgi $app => sub {
    my $cb     = shift;
    my $user   = TxnTest->user;
    ok my $res = $cb->(POST(
        $uri,
        Authorization => 'Basic ' . encode_base64("$user:****"),
        Content       => [
            old_pass  => '****',
            new_pass  => 'whatevs',
            new_pass2 => 'whatevs',
        ],
    )), "POST update to $uri";
    ok $res->is_redirect, 'It should be a redirect response';
    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    is $res->headers->header('location'), $req->uri_for($uri),
        "Should redirect to $uri";

    # And the user's password should be updated.
    PGXN::Manager->conn->run(sub {
        ok $_->selectcol_arrayref(
            'SELECT authenticate_user(?, ?)',
            undef, $user, 'whatevs'
        )->[0], 'The password should have been changed';
    });
};

# Try an update via an XMLHttpRequest.
test_psgi $app => sub {
    my $cb     = shift;
    my $user   = TxnTest->user;
    ok my $res = $cb->(POST(
        $uri,
        Authorization => 'Basic ' . encode_base64("$user:whatevs"),
        'X-Requested-With' => 'XMLHttpRequest',
        Content       => [
            old_pass  => 'whatevs',
            new_pass  => 'dood',
            new_pass2 => 'dood',
        ],
    )), "POST XMLHttpRequest update to $uri";
    ok $res->is_success, 'It should be a success';
    is $res->content, 'Success', 'And the content should say so';

    # And the user's password should be updated.
    PGXN::Manager->conn->run(sub {
        ok $_->selectcol_arrayref(
            'SELECT authenticate_user(?, ?)',
            undef, $user, 'dood'
        )->[0], 'The password should have been changed';
    });
};

# Awesome. Try mismatched passwords.
test_psgi $app => sub {
    my $cb     = shift;
    my $user   = TxnTest->user;
    ok my $res = $cb->(POST(
        $uri,
        Authorization => 'Basic ' . encode_base64("$user:dood"),
        Content       => [
            old_pass  => '****',
            new_pass  => 'whatevs',
            new_pass2 => 'whatever',
        ],
    )), "POST password mismatch update to $uri";
    ok !$res->is_success, 'It should not be a success';
    is $res->code, 409, 'It should return code 409';

    # So check the content.
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{REMOTE_USER} = $user;
    XPathTest->test_basics($tx, $req, $mt, $head);

    # Make sure we've got an error message.
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 4, '... It should have four subelements');
        my $err = $mt->maketext(q{D'oh! The passwords you typed in don't match. Would you mind trying again? Thanks.});
        $tx->is('./p[@class="error"]', $err, '... Error paragraph should be set');
    });

    # And the user's password should be updated.
    PGXN::Manager->conn->run(sub {
        ok $_->selectcol_arrayref(
            'SELECT authenticate_user(?, ?)',
            undef, $user, 'dood'
        )->[0], 'The password should not have been changed';
    });
};

# Try it again with an XMLHttpRequest.
test_psgi $app => sub {
    my $cb     = shift;
    my $user   = TxnTest->user;
    ok my $res = $cb->(POST(
        $uri,
        Authorization => 'Basic ' . encode_base64("$user:dood"),
        'X-Requested-With' => 'XMLHttpRequest',
        Content       => [
            old_pass  => '****',
            new_pass  => 'whatevs',
            new_pass2 => 'whatever',
        ],
    )), "POST password mismatch XMLHttpRequest to $uri";
    ok !$res->is_success, 'It should not be a success';
    is $res->code, 409, 'It should return code 409';
    my $err = $mt->maketext(q{D'oh! The passwords you typed in don't match. Would you mind trying again? Thanks.});
    is $res->decoded_content, $err, 'And the content should say why';

    # And the user's password should be updated.
    PGXN::Manager->conn->run(sub {
        ok $_->selectcol_arrayref(
            'SELECT authenticate_user(?, ?)',
            undef, $user, 'dood'
        )->[0], 'The password still should not have been changed';
    });
};

# Now try passwords that are too short.
test_psgi $app => sub {
    my $cb     = shift;
    my $user   = TxnTest->user;
    ok my $res = $cb->(POST(
        $uri,
        Authorization => 'Basic ' . encode_base64("$user:dood"),
        Content       => [
            old_pass  => '****',
            new_pass  => 'hi',
            new_pass2 => 'hi',
        ],
    )), "POST short passwords to $uri";
    ok !$res->is_success, 'It should not be a success';
    is $res->code, 409, 'It should return code 409';

    # So check the content.
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{REMOTE_USER} = $user;
    XPathTest->test_basics($tx, $req, $mt, $head);

    # Make sure we've got an error message.
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 4, '... It should have four subelements');
        my $err = $mt->maketext(q{So sorry! Passwords must be at least four characters long.});
        $tx->is('./p[@class="error"]', $err, '... Error paragraph should be set');
    });

    # And the user's password should be updated.
    PGXN::Manager->conn->run(sub {
        ok $_->selectcol_arrayref(
            'SELECT authenticate_user(?, ?)',
            undef, $user, 'dood'
        )->[0], 'The password should not have been changed';
    });
};

# Try it again with an XMLHttpRequest.
test_psgi $app => sub {
    my $cb     = shift;
    my $user   = TxnTest->user;
    ok my $res = $cb->(POST(
        $uri,
        Authorization => 'Basic ' . encode_base64("$user:dood"),
        'X-Requested-With' => 'XMLHttpRequest',
        Content       => [
            old_pass  => '****',
            new_pass  => 'hi',
            new_pass2 => 'hi',
        ],
    )), "POST short passwords via XMLHttpRequest to $uri";
    ok !$res->is_success, 'It should not be a success';
    is $res->code, 409, 'It should return code 409';
    my $err = $mt->maketext(q{So sorry! Passwords must be at least four characters long.});
    is $res->decoded_content, $err, 'And the content should say why';

    # And the user's password should be updated.
    PGXN::Manager->conn->run(sub {
        ok $_->selectcol_arrayref(
            'SELECT authenticate_user(?, ?)',
            undef, $user, 'dood'
        )->[0], 'The password still should not have been changed';
    });
};

# And finally, we have an invalid old password.
test_psgi $app => sub {
    my $cb     = shift;
    my $user   = TxnTest->user;
    ok my $res = $cb->(POST(
        $uri,
        Authorization => 'Basic ' . encode_base64("$user:dood"),
        Content       => [
            old_pass  => '****',
            new_pass  => 'hihi',
            new_pass2 => 'hihi',
        ],
    )), "POST invalid old password to $uri";
    ok !$res->is_success, 'It should not be a success';
    is $res->code, 409, 'It should return code 409';

    # So check the content.
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{REMOTE_USER} = $user;
    XPathTest->test_basics($tx, $req, $mt, $head);

    # Make sure we've got an error message.
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 4, '... It should have four subelements');
        my $err = $mt->maketext(q{I don't think that was really your existing password. Care to try again?});
        $tx->is('./p[@class="error"]', $err, '... Error paragraph should be set');
    });

    # And the user's password should be updated.
    PGXN::Manager->conn->run(sub {
        ok $_->selectcol_arrayref(
            'SELECT authenticate_user(?, ?)',
            undef, $user, 'dood'
        )->[0], 'The password should not have been changed';
    });
};

# Reset the transaction and try again with an XMLHttpRequest.
TxnTest->restart;
test_psgi $app => sub {
    my $cb     = shift;
    my $user   = TxnTest->user;
    ok my $res = $cb->(POST(
        $uri,
        Authorization => 'Basic ' . encode_base64("$user:****"),
        'X-Requested-With' => 'XMLHttpRequest',
        Content       => [
            old_pass  => 'dood',
            new_pass  => 'hihi',
            new_pass2 => 'hihi',
        ],
    )), "POST invalid old password via XMLHttpRequest to $uri";
    ok !$res->is_success, 'It should not be a success';
    is $res->code, 409, 'It should return code 409';
    my $err = $mt->maketext(q{I don't think that was really your existing password. Care to try again?});
    is $res->decoded_content, $err, 'And the content should say why';

    # And the user's password should be updated.
    PGXN::Manager->conn->run(sub {
        ok $_->selectcol_arrayref(
            'SELECT authenticate_user(?, ?)',
            undef, $user, '****'
        )->[0], 'The password still should not have been changed';
    });
};

