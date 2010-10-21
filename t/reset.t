#!/usr/bin/env perl -w

use 5.12.0;
use utf8;
BEGIN { $ENV{EMAIL_SENDER_TRANSPORT} = 'Test' }

use Test::More tests => 275;
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

my $app      = PGXN::Manager::Router->app;
my $mt       = PGXN::Manager::Locale->accept('en');

# Fetch the forgotten form.
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET '/pub/account/forgotten'), 'Fetch /account/forgotten';
    ok $res->is_success, 'Should get a successful response';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{SCRIPT_NAME} = '/pub';
    XPathTest->test_basics($tx, $req, $mt, {
        h1 => 'Forgot Your Password?',
        page_title => 'Forgot your password? Request a reset link',
    });

    # Check out the content.
    $tx->ok('/html/body/div[@id="content"]', 'Look at the content', sub {
        $tx->is('count(./*)', 3, '... Should have three subelements');
        $tx->is(
            './p',
            $mt->maketext('Please type your email address or PGXN nickname below.'),
            '... Should have intro paragraph'
        );

        # Check out the form.
        $tx->ok('./form[@id="forgotform"]', '... Test change form', sub {
            for my $attr (
                [action  => $req->uri_for('/account/forgotten')],
                [enctype => 'application/x-www-form-urlencoded; charset=UTF-8'],
                [method  => 'post']
            ) {
                $tx->is(
                    "./\@$attr->[0]",
                    $attr->[1],
                    qq{...... Its $attr->[0] attribute should be "$attr->[1]"},
                );
            }
            $tx->is('count(./*)', 2, '...... Should have two subelements');
            $tx->ok('./fieldset', '...... Test fieldset', sub {
                $tx->is('count(./*)', 2, '......... Should have two subelements');
                $tx->is(
                    './legend',
                    $mt->maketext('Who Are You?'),
                    '......... Should have legend'
                );
                $tx->ok('./input[@id="who"]', '......... Test "who" field', sub {
                    $tx->is('./@type', 'text', '............ Should be type "text"');
                    $tx->is('./@name', 'who', '............ Should be name "who"');
                    $tx->is(
                        './@placeholder',
                        'bobama@pgxn.org',
                        '............ Should have placeholder'
                    );
                });
            });
            $tx->ok('./input[@id="submit"]', '...... Test submit button', sub {
                $tx->is('./@class', 'submit', '......... Should have class "submit"');
                $tx->is('./@type', 'submit', '......... Should have id "submit"');
                $tx->is('./@name', 'submit', '......... Should have id "submit"');
                $tx->is(
                    './@value',
                    $mt->maketext('Send Instructions'),
                    '......... Should have value'
                );
            });
        })
    });
};

# Now submit a password change. First for non-existent user.
test_psgi $app => sub {
    my $cb = shift;

    my $mock = Test::MockModule->new('PGXN::Manager::Request');
    my $sess = {};
    $mock->mock( session => sub { $sess });

    ok my $res = $cb->(POST '/pub/account/forgotten', [
        who => 'nobody',
    ]), 'POST nobody to /account/forgotten';

    ok $res->is_redirect, 'Should get a redirect response';
    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{SCRIPT_NAME} = '/pub';
    is $res->headers->header('location'), $req->uri_for('/'),
        "Should redirect to home";
    ok $sess->{reset_sent},
        'The "reset_sent" key should have been set in the session';

    is @{ Email::Sender::Simple->default_transport->deliveries },
        0, 'But no email should have been sent'
};

# Now submit for an actual user.
my $tok;
test_psgi $app => sub {
    my $cb = shift;

    my $mock = Test::MockModule->new('PGXN::Manager::Request');
    my $sess = {};
    $mock->mock( session => sub { $sess });

    my $user = TxnTest->user;
    ok my $res = $cb->(POST '/pub/account/forgotten', [
        who => $user,
    ]), "POST $user to /account/forgotten";

    ok $res->is_redirect, 'Should get a redirect response';
    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{SCRIPT_NAME} = '/pub';
    is $res->headers->header('location'), $req->uri_for('/'),
        "Should redirect to home";
    ok $sess->{reset_sent},
        'The "reset_sent" key should have been set in the session';

    ok my $deliveries = Email::Sender::Simple->default_transport->deliveries,
        'Should have email deliveries.';
    is @{ $deliveries }, 1, 'Should have one message';
    is @{ $deliveries->[0]{successes} }, 1, 'Should have been successfully delivered';

    my $email = $deliveries->[0]{email};
    is $email->get_header('Subject'), 'Reset Your Password',
        'The subject should be set';
    is $email->get_header('From'), PGXN::Manager->config->{admin_email},
        'From header should be set';
    is $email->get_header('To'), 'user@pgxn.org', 'To header should be set';
    like $email->get_body, qr{Click the link below to reset your PGXN password[.] But do it soon!
This link will expire in 24 hours:

    http://localhost/auth/account/reset/\w{4,}

Best,

PGXN Management}ms,
        'Should have reset body';
    ($tok) = $email->get_body =~ m{http://localhost/auth/account/reset/(\w{4,})};
    Email::Sender::Simple->default_transport->clear_deliveries;
};

# Try again with email address and an xhr request.
my $tok2;
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb     = shift;
    my $req    = POST(
        '/pub/account/forgotten',
        'X-Requested-With' => 'XMLHttpRequest',
        Content => [who => 'user@pgxn.org'],
    );

    ok my $res = $cb->($req), 'Send XMLHttpRequest POST forgotten for user again';
    ok $res->is_success, 'Response should be success';
    is $res->content, $mt->maketext('Success'),
        'And the content should say so';

    ok my $deliveries = Email::Sender::Simple->default_transport->deliveries,
        'Should have email deliveries.';
    is @{ $deliveries }, 1, 'Should have one message';
    is @{ $deliveries->[0]{successes} }, 1, 'Should have been successfully delivered';

    my $email = $deliveries->[0]{email};
    is $email->get_header('Subject'), 'Reset Your Password',
        'The subject should be set';
    is $email->get_header('From'), PGXN::Manager->config->{admin_email},
        'From header should be set';
    is $email->get_header('To'), 'user@pgxn.org', 'To header should be set';
    like $email->get_body, qr{Click the link below to reset your PGXN password[.] But do it soon!
This link will expire in 24 hours:

    http://localhost/auth/account/reset/\w{4,}

Best,

PGXN Management}ms,
        'Should have reset body';
    Email::Sender::Simple->default_transport->clear_deliveries;

    # Grab the token for resetting the password below.
    ($tok2) = $email->get_body =~ m{http://localhost/auth/account/reset/(\w{4,})};
};

# Let's see what the reset form looks like, eh?
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET "/auth/account/reset/$tok"), "Fetch /account/reset/$tok";
    ok $res->is_success, 'Should get a successful response';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{SCRIPT_NAME} = '/auth';
    XPathTest->test_basics($tx, $req, $mt, {
        h1 => 'Reset Your PGXN Password',
        page_title => 'Reset Your Password'
    });

    # Check out the content.
    $tx->ok('/html/body/div[@id="content"]', 'Look at the content', sub {
        $tx->is('count(./*)', 3, '... Should have three subelements');
        $tx->is(
            './p',
            $mt->maketext('Please choose a password to use for your PGXN account.'),
            '... Should have intro paragraph'
        );

        # Check out the form.
        $tx->ok('./form[@id="changeform"]', '... Test change form', sub {
            for my $attr (
                [action  => $req->uri_for("/account/reset/$tok")],
                [enctype => 'application/x-www-form-urlencoded; charset=UTF-8'],
                [method  => 'post']
            ) {
                $tx->is(
                    "./\@$attr->[0]",
                    $attr->[1],
                    qq{...... Its $attr->[0] attribute should be "$attr->[1]"},
                );
            }
            $tx->is('count(./*)', 2, '...... Should have two subelements');

            $tx->ok('./fieldset', '...... Test fieldset', sub {
                $tx->is('count(./*)', 5, '......... Should have five subelements');
                $tx->is(
                    './legend',
                    $mt->maketext('Change Password'),
                    '......... Should have legend',
                );

                my $title = $mt->maketext('Must be at least four charcters long.');
                $tx->ok('./label[@for="new_pass"]', '......... Test new_pass label', sub {
                    $tx->is(
                        './@title',
                        $title,
                        '............ Should have title'
                    );
                    $tx->is(
                        './text()',
                        $mt->maketext('New Password'),
                        'Should have text'
                    );
                });

                $tx->ok('./input[@id="new_pass"]', '......... Test "new_pass" field', sub {
                    $tx->is('./@type', 'password', '............ Should be type "password"');
                    $tx->is('./@name', 'new_pass', '............ Should be name "new_pass"');
                    $tx->is('./@title', $title, '............ Should have title');
                });

                $title = $mt->maketext('Must be the same as the new password.');
                $tx->ok('./label[@for="verify"]', '......... Test verify label', sub {
                    $tx->is(
                        './@title',
                        $title,
                        '............ Should have title'
                    );
                    $tx->is(
                        './text()',
                        $mt->maketext('Verify Password'),
                        'Should have text'
                    );
                });
                $tx->ok('./input[@id="verify"]', '......... Test "verify" field', sub {
                    $tx->is('./@type', 'password', '............ Should be type "password"');
                    $tx->is('./@name', 'verify', '............ Should be name "verify"');
                    $tx->is('./@title', $title, '............ Should have title');
                });
            });
            $tx->ok('./input[@id="submit"]', '...... Test submit button', sub {
                $tx->is('./@class', 'submit', '......... Should have class "submit"');
                $tx->is('./@type', 'submit', '......... Should have id "submit"');
                $tx->is('./@name', 'submit', '......... Should have id "submit"');
                $tx->is(
                    './@value',
                    $mt->maketext('Change'),
                    '......... Should have value'
                );
            });
        });
    });
};

test_psgi $app => sub {
    my $cb = shift;

    my $mock = Test::MockModule->new('PGXN::Manager::Request');
    my $sess = {};
    $mock->mock( session => sub { $sess });

    ok my $res = $cb->(POST "/auth/account/reset/$tok", [
        new_pass => 'whatever',
        verify   => 'whatever',
    ]), "Send POST to /account/reset/$tok";

    ok $res->is_redirect, 'Should get a redirect response';
    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{SCRIPT_NAME} = '/auth';
    is $res->headers->header('location'), $req->uri_for('/account/changed'),
        "Should redirect to /account/changed";
};

# With the password changed, we should now be able to authenticate.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb   = shift;
    my $user = TxnTest->user;
    my $req  = GET '/auth/', Authorization => 'Basic ' . encode_base64("$user:whatever");
    ok my $res = $cb->($req), "Get with auth token";
    ok $res->is_success, 'Response should be success';
};

# Cool. Now see what it looks like with an expired token.
test_psgi $app => sub {
    my $cb = shift;

    my $mock = Test::MockModule->new('PGXN::Manager::Request');
    my $sess = {};
    $mock->mock( session => sub { $sess });

    ok my $res = $cb->(POST "/auth/account/reset/$tok", [
        new_pass => 'whatever',
        verify   => 'whatever',
    ]), 'Send POST to /account/reset/expired';

    ok !$res->is_success, 'Should not get success response';
    is $res->code, 410, 'Should get 410 response';

    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{SCRIPT_NAME} = '/auth';
    XPathTest->test_basics($tx, $req, $mt, {
        h1 => 'Resource Gone',
        page_title => 'Resource Gone',
    });

    $tx->ok('/html/body/div[@id="content"]', 'Look at the content', sub {
        $tx->is('count(./*)', 2, '... Should have two subelements');
        $tx->is(
            './p[@class="error"]',
            $mt->maketext(q{Sorry, but that password reset token has expired.}),
            '... Should have the error message'
        );
    });
};

# Try again with an XMLHttpRequest.
test_psgi $app => sub {
    my $cb = shift;

    my $mock = Test::MockModule->new('PGXN::Manager::Request');
    my $sess = {};
    $mock->mock( session => sub { $sess });

    ok my $res = $cb->(POST(
        "/auth/account/reset/$tok",
        'X-Requested-With' => 'XMLHttpRequest',
        Content => [
            new_pass => 'whatever',
            verify   => 'whatever',
        ]
    )), 'Send XHR POST toe /account/reset/expired';

    ok !$res->is_success, 'Should not get success response';
    is $res->code, 410, 'Should get 410 response';
    is $res->content,
        $mt->maketext(q{Sorry, but that password reset token has expired.}),
        'And the content should say why';
};

# Send a successful XMLHttRequest
test_psgi $app => sub {
    my $cb = shift;

    my $mock = Test::MockModule->new('PGXN::Manager::Request');
    my $sess = {};
    $mock->mock( session => sub { $sess });

    ok my $res = $cb->(POST(
        "/auth/account/reset/$tok2",
        'X-Requested-With' => 'XMLHttpRequest',
        Content => [
            new_pass => 'fünkmusic',
            verify   => 'fünkmusic',
        ]
    )), 'Send XHR POST toe /account/reset/expired';

    ok $res->is_success, 'Should get success response';
    is $res->content, $mt->maketext(q{Success}), 'And the content should say why';
};

# With the password changed again, we should now be able to authenticate.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb   = shift;
    my $user = TxnTest->user;
    no utf8;
    my $req  = GET '/auth/', Authorization => 'Basic ' . encode_base64("$user:fünkmusic");
    ok my $res = $cb->($req), "Get with auth token";
    ok $res->is_success, 'Response should be success';
};

# Have a look at /account/changed.
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET '/auth/account/changed'), 'Fetch /account/changed';
    ok $res->is_success, 'Should get a successful response';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{SCRIPT_NAME} = '/auth';
    XPathTest->test_basics($tx, $req, $mt, {
        h1 => 'Password Changed',
        page_title => 'Password Changed',
    });

    # Check out the content.
    $tx->ok('/html/body/div[@id="content"]', 'Look at the content', sub {
        $tx->is('count(./*)', 2, '... Should have two subelements');
        my $msg = quotemeta $mt->maketext(
            q{W00t! Your password has been changed. So what are you waiting for?}
        );
        $tx->like(
            './p[@class="success"]',
            qr/$msg/,
            '... Should have the success message'
        );
        $tx->is(
            './p/a[@href="' . $req->auth_uri . '"]',
            $mt->maketext('Go log in!'),
            'And should have the log in link'
        );
    });
};


