#!/usr/bin/env perl

use 5.12.0;
use utf8;

use Test::More tests => 291;
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
my $uri  = '/auth/account';
my $head = {
    h1            => 'Edit Your Account',
    validate_form => '#accform',
    page_title    => 'Edit your account information',
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
            $mt->maketext('Keep your account info up-to-date!'),
            '... Intro paragraph should be set'
        );
    });

    # Now examine the form.
    $tx->ok('/html/body/div[@id="content"]/form[@id="accform"]', sub {
        for my $attr (
            [action  => $req->uri_for('/auth/account')],
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
            $tx->is('./@id', 'accessentials', '...... It should have the proper id');
            $tx->is('count(./*)', 9, '...... It should have 9 subelements');
            $tx->is(
                './legend',
                $mt->maketext('The Essentials'),
                '...... Its legend should be correct'
            );
            my $i = 0;
            for my $spec (
                {
                    id    => 'full_name',
                    title => $mt->maketext('What does your mother call you?'),
                    label => $mt->maketext('Name'),
                    type  => 'text',
                    phold => 'Barack Obama',
                    class => '',
                },
                {
                    id    => 'email',
                    title => $mt->maketext('Where can we get hold of you?'),
                    label => $mt->maketext('Email'),
                    type  => 'email',
                    phold => 'you@example.com',
                    class => 'required email',
                },
                {
                    id    => 'uri',
                    title => $mt->maketext('Got a blog or personal site?'),
                    label => $mt->maketext('URI'),
                    type  => 'url',
                    phold => 'http://blog.example.com/',
                    class => '',
                },
                {
                    id    => 'twitter',
                    title => $mt->maketext('Got a Twitter account? Tell us the username and your uploads will be tweeted!'),
                    label => $mt->maketext('Twitter'),
                    type  => 'text',
                    phold => '@barackobama',
                    class => '',
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
                    $_->is('./@placeholder', $spec->{phold}, '......... Check "placeholder" attr' );
                });
            }
        });
        $tx->ok('./input[@type="submit"]', '... Test input', sub {
            for my $attr (
                [id => 'submit'],
                [name => 'submit'],
                [class => 'submit'],
                [value => $mt->maketext('Make it so!')],
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
            full_name => 'Tom Lane',
            email     => 'tgl@pgxn.org',
            uri       => '',
            twitter   => 'tommylane',
            nickname  => 'tgl', # Should be ignored.
        ],
    )), "POST update to $uri";
    ok $res->is_redirect, 'It should be a redirect response';
    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    is $res->headers->header('location'), $req->uri_for($uri),
        "Should redirect to $uri";

    # And now the user should be updated.
    PGXN::Manager->conn->run(sub {
        is_deeply $_->selectrow_arrayref(q{
            SELECT full_name, email, uri, twitter
              FROM users
             WHERE nickname = ?
        }, undef, $user), [
            'Tom Lane', 'tgl@pgxn.org', '', 'tommylane',
        ], 'User should be updated'
    });
};

# Try an update via an XMLHttpRequest.
test_psgi $app => sub {
    my $cb     = shift;
    my $user   = TxnTest->user;
    ok my $res = $cb->(POST(
        $uri,
        Authorization => 'Basic ' . encode_base64("$user:****"),
        'X-Requested-With' => 'XMLHttpRequest',
        Content       => [
            full_name => 'Josh Berkus',
            email     => 'josh@pgxn.org',
            uri       => '',
            twitter   => 'agliodbs',
        ],
    )), "POST update to $uri";
    ok $res->is_success, 'It should return success';
    is $res->content, 'Success', 'And the content should say so';

    # And now the user should be updated.
    PGXN::Manager->conn->run(sub {
        is_deeply $_->selectrow_arrayref(q{
            SELECT full_name, email, uri, twitter
              FROM users
             WHERE nickname = ?
        }, undef, $user), [
            'Josh Berkus', 'josh@pgxn.org', '', 'agliodbs',
        ], 'User should be updated'
    });
};

# Need to mock user_is_admin to get around dead transactions.
my $rmock = Test::MockModule->new('PGXN::Manager::Request');
$rmock->mock(user_is_admin => 0);

# Awesome. Try to get a conflicting email address.
test_psgi $app => sub {
    my $cb     = shift;
    my $user   = TxnTest->user;

    # Need to mock the fetching of original email address.
    my $dmock = Test::MockModule->new(ref PGXN::Manager->conn->dbh);
    $dmock->mock(selectcol_arrayref => sub {
        shift;
        is_deeply \@_, [
            'SELECT email FROM users WHERE nickname = ?',
            undef, $user
        ], 'Should get query for nickname';
        return ['theuser@pgxn.org'];
    });

    # Okay, now make the request.
    ok my $res = $cb->(POST(
        $uri,
        Authorization => 'Basic ' . encode_base64("$user:****"),
        Content       => [
            full_name => 'Tom Lane',
            email     => 'admin@pgxn.org',
            uri       => '',
        ],
    )), "POST email conflict to $uri";
    ok !$res->is_redirect, 'It should not be a redirect response';
    is $res->code, 409, 'Should have 409 status code';

    # So check the content.
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{REMOTE_USER} = $user;
    XPathTest->test_basics($tx, $req, $mt, $head);

    # Now verify that we have the error message and that the form fields are
    # filled-in.
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 4, '... It should have four subelements');
        my $err = $mt->maketext('Do you have two accounts? Because the email address “[_1]” is associated with another account.', 'admin@pgxn.org');
        $tx->is('./p[@class="error"]', $err, '... Error paragraph should be set');

        # Check the form fields.
        $tx->ok('./form[@id="accform"]/fieldset', '... Check form fieldset', sub {
            $tx->is('./input[@id="full_name"]/@value', 'Tom Lane', '...... Name should be set');
            $tx->is('./input[@id="email"]/@value', 'theuser@pgxn.org', '...... Email should be original');
            $tx->is('./input[@id="email"]/@class', 'required email', '...... And it should not be highlighted');
            $tx->is('./input[@id="uri"]/@value', '', '...... URI should be set');
        });
    });
};

# Try a bogus email.
TxnTest->restart;
test_psgi $app => sub {
    my $cb     = shift;
    my $user   = TxnTest->user;
    ok my $res = $cb->(POST(
        $uri,
        Authorization => 'Basic ' . encode_base64("$user:****"),
        Content       => [
            full_name => '',
            email     => 'getme at whatever dot com',
            uri       => '',
        ]
    )), 'POST form with bogus email';
    ok !$res->is_redirect, 'It should not be a redirect response';
    is $res->code, 409, 'Should have 409 status code';

    # So check the content.
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{REMOTE_USER} = $user;
    XPathTest->test_basics($tx, $req, $mt, $head);

    # Now verify that we have the error message.
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 4, '... It should have four subelements');
        my $err = $mt->maketext(q{Hrm, “[_1]” doesn't look like an email address. Care to try again?}, 'getme at whatever dot com');
        $tx->is('./p[@class="error"]', $err, '... Error paragraph should be set');
        $tx->ok('./form/fieldset/input[@id="email"]', '... Test email input', sub {
            $tx->is('./@value', '', '...... Its value should be empty');
            $tx->is('./@class', 'required email highlight', '...... And it should be highlighted');
        })
    });
};

# Try a bogus uri.
TxnTest->restart;
test_psgi $app => sub {
    my $cb     = shift;
    my $user   = TxnTest->user;
    ok my $res = $cb->(POST(
        $uri,
        Authorization => 'Basic ' . encode_base64("$user:****"),
        Content       => [
            full_name => '',
            uri       => 'http:\\foo.com/',
            email     => 'foo@bar.com',
        ]
    )), 'POST form with bogus URI to /register';
    ok !$res->is_redirect, 'It should not be a redirect response';
    is $res->code, 409, 'Should have 409 status code';

    # So check the content.
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{REMOTE_USER} = $user;
    XPathTest->test_basics($tx, $req, $mt, $head);

    # Now verify that we have the error message.
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 4, '... It should have four subelements');
        my $err = $mt->maketext(q{Hrm, “[_1]” doesn't look like a URI. Care to try again?}, 'http:\\foo.com/');
        $tx->is('./p[@class="error"]', $err, '... Error paragraph should be set');
        $tx->ok('./form/fieldset[1]/input[@id="uri"]', '... Test uri input', sub {
            $tx->is('./@value', '', '...... Its value should be empty');
            $tx->is('./@class', 'highlight', '...... And it should be highlighted');
        })
    });
};

# Try a bogus uri via XMLHttpRequest.
TxnTest->restart;
test_psgi $app => sub {
    my $cb     = shift;
    my $user   = TxnTest->user;
    ok my $res = $cb->(POST(
        $uri,
        Authorization => 'Basic ' . encode_base64("$user:****"),
        'X-Requested-With' => 'XMLHttpRequest',
        Content       => [
            full_name => '',
            uri       => 'http:\\foo.com/',
            email     => 'foo@bar.com',
        ]
    )), 'POST form with bogus URI to /register';
    is $res->code, 409, 'Should have 409 status code';
    is $res->decoded_content,
        $mt->maketext(q{Hrm, “[_1]” doesn't look like a URI. Care to try again?}, 'http:\\foo.com/'),
        'And the content should reflect such';
};
