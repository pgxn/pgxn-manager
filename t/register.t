#!/usr/bin/env perl

use 5.12.0;
use utf8;
BEGIN { $ENV{EMAIL_SENDER_TRANSPORT} = 'Test' }

use Test::More tests => 590;
#use Test::More 'no_plan';
use Plack::Test;
use HTTP::Request::Common;
use PGXN::Manager;
use PGXN::Manager::Router;
use HTTP::Message::PSGI;
use Test::XML;
use Test::XPath;
use lib 't/lib';
use TxnTest;
use XPathTest;

my $app      = PGXN::Manager::Router->app;
my $mt       = PGXN::Manager::Locale->accept('en');
my $desc     = $mt->maketext('Request a PGXN Account and start distributing your PostgreSQL extensions!');
my $keywords = 'pgxn,postgresql,distribution,register,account,user,nickname';
my $h1       = $mt->maketext('Request an Account');
my $p        = $mt->maketext(q{Want to distribute your PostgreSQL extensions on PGXN? Register here to request an account. We'll get it approved post haste.});
my $hparams  = {
    desc          => $desc,
    keywords      => $keywords,
    h1            => $h1,
    validate_form => '#reqform',
    page_title    => 'Request an account and start releasing distributions',
};

# Request a registration form.
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET '/pub/account/register'), 'Fetch /register';
    ok $res->is_success, 'Should get a successful response';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{SCRIPT_NAME} = '/pub';
    XPathTest->test_basics($tx, $req, $mt, $hparams);

    # Check the content
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 3, '... It should have three subelements');
        $tx->is('./h1', $h1, '... The title h1 should be set');
        $tx->is('./p', $p, '... Intro paragraph should be set');
    });

    # Now examine the form.
    $tx->ok('/html/body/div[@id="content"]/form[@id="reqform"]', sub {
        for my $attr (
            [action  => $req->uri_for('/account/register')],
            [enctype => 'application/x-www-form-urlencoded; charset=UTF-8'],
            [method  => 'post']
        ) {
            $tx->is(
                "./\@$attr->[0]",
                $attr->[1],
                qq{... Its $attr->[0] attribute should be "$attr->[1]"},
            );
        }
        $tx->is('count(./*)', 3, '... It should have three subelements');
        $tx->ok('./fieldset[1]', '... Test first fieldset', sub {
            $tx->is('./@id', 'reqessentials', '...... It should have the proper id');
            $tx->is('count(./*)', 11, '...... It should have 11 subelements');
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
                    id    => 'nickname',
                    title => $mt->maketext('By what name would you like to be known? Letters, numbers, and dashes only, please.'),
                    label => $mt->maketext('Nickname'),
                    type  => 'text',
                    phold => 'bobama',
                    class => 'required',
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
        $tx->ok('./fieldset[2]', '... Test second fieldset', sub {
            $tx->is('./@id', 'reqwhy', '...... It should have the proper id');
            $tx->is('count(./*)', 3, '...... It should have three subelements');
            $tx->is('./legend', $mt->maketext('Your Plans'), '...... It should have a legend');
            my $t = $mt->maketext('So what are your plans for PGXN? What do you wanna release?');
            $tx->ok('./label', '...... Test the label', sub {
                $_->is('./@for', 'why', '......... It should be for the right field');
                $_->is('./@title', $t, '......... It should have the title');
                $_->is('./text()', $mt->maketext('Why'), '......... It should have label');
            });
            $tx->ok('./textarea', '...... Test the textarea', sub {
                $_->is('./@id', 'why', '......... It should have its id');
                $_->is('./@name', 'why', '......... It should have its name');
                $_->is('./@title', $t, '......... It should have the title');
                $_->is('./@placeholder', $mt->maketext('I would like to release the following killer extensions on PGXN:

* foo
* bar
* baz'), '......... It should have its placeholder');
                $_->is('./text()', '', '......... And it should be empty')
            });
        });
        $tx->ok('./input[@type="submit"]', '... Test input', sub {
            for my $attr (
                [id => 'submit'],
                [name => 'submit'],
                [class => 'submit'],
                [value => $mt->maketext('Pretty Please!')],
            ) {
                $_->is(
                    "./\@$attr->[0]",
                    $attr->[1],
                    qq{...... Its $attr->[0] attribute should be "$attr->[1]"},
                );
            }
        });
    }, 'Test request form');
};

# Okay, let's submit the form.
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(POST '/pub/account/register', [
        full_name => 'Tom Lane',
        email     => 'tgl@pgxn.org',
        uri       => '',
        nickname  => 'tgl',
        why       => 'In short, +1 from me. Regards, Tom Lane',
    ]), 'POST tgl to /register';
    ok $res->is_redirect, 'It should be a redirect response';
    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{SCRIPT_NAME} = '/pub';
    is $res->headers->header('location'), $req->uri_for('/pub/account/thanks'),
        'Should redirect to /account/thanks';

    # And now Tom Lane should be registered.
    PGXN::Manager->conn->run(sub {
        is_deeply $_->selectrow_arrayref(q{
            SELECT full_name, email, uri, twitter, why, status
              FROM users
             WHERE nickname = ?
        }, undef, 'tgl'), [
            'Tom Lane', 'tgl@pgxn.org', '', '',
            'In short, +1 from me. Regards, Tom Lane', 'new'
        ], 'TGL should exist';
    });

    # And an email should have been sent.
    ok my $deliveries = Email::Sender::Simple->default_transport->deliveries,
        'Should have email deliveries.';
    is @{ $deliveries }, 1, 'Should have one message';
    is @{ $deliveries->[0]{successes} }, 1, 'Should have been successfully delivered';

    my $email = $deliveries->[0]{email};
    is $email->get_header('Subject'), 'New User Request for tgl',
        'The subject should be set';
    is $email->get_header('From'), PGXN::Manager->config->{admin_email},
        'From header should be set';
    is $email->get_header('To'), PGXN::Manager->config->{alert_email},
        'To header should be set';
    is $email->get_body, 'A new PGXN account has been requted from localhost:

     Name: Tom Lane
 Nickname: tgl
    Email: tgl@pgxn.org
   Reason:

> In short, +1 from me. Regards, Tom Lane
', 'The body should be correct';
    Email::Sender::Simple->default_transport->clear_deliveries;
};

# Awesome. Let's get a nickname conflict and see how it handles it.
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(POST '/pub/account/register', [
        full_name => 'Tom Lane',
        email     => 'tgl@pgxn.org',
        uri       => 'http://tgl.example.org/',
        nickname  => 'tgl',
        why       => 'In short, +1 from me. Regards, Tom Lane',
    ]), 'POST tgl to /register again';
    ok !$res->is_redirect, 'It should not be a redirect response';
    is $res->code, 409, 'Should have 409 status code';

    is @{ Email::Sender::Simple->default_transport->deliveries },
        0, 'No email should have been sent';

    # So check the content.
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{SCRIPT_NAME} = '/pub';
    XPathTest->test_basics($tx, $req, $mt, $hparams);

    # Now verify that we have the error message and that the form fields are
    # filled-in.
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 4, '... It should have four subelements');
        $tx->is('./h1', $h1, '... The title h1 should be set');
        $tx->is('./p[1]', $p, '... Intro paragraph should be set');
        my $err = $mt->maketext('The Nickname “[_1]” is already taken. Sorry about that.', 'tgl');
        $tx->is('./p[@class="error"]', $err, '... Error paragraph should be set');

        # Check the form fields.
        $tx->ok('./form[@id="reqform"]/fieldset[1]', '... Check first fieldset', sub {
            $tx->is('./input[@id="full_name"]/@value', 'Tom Lane', '...... Name should be set');
            $tx->is('./input[@id="email"]/@value', 'tgl@pgxn.org', '...... Email should be set');
            $tx->is('./input[@id="uri"]/@value', 'http://tgl.example.org/', '...... URI should be set');
            $tx->is('./input[@id="nickname"]/@value', '', '...... Nickname should not be set');
            $tx->is('./input[@id="nickname"]/@class', 'required highlight', '...... And it should be highlighted');
        });

        $tx->ok('./form[@id="reqform"]/fieldset[2]', '... Check second fieldset', sub {
            $tx->is(
                './textarea[@id="why"]',
                'In short, +1 from me. Regards, Tom Lane',
                '...... Why textarea should be set'
            );
        });
    });
};

# Start a new test transaction and create Tom again.
TxnTest->restart;
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(POST '/pub/account/register', [
        full_name => 'Tom Lane',
        email     => 'tgl@pgxn.org',
        uri       => 'http://tgl.example.org/',
        nickname  => 'tgl',
        twitter   => 'tomlane',
        why       => 'In short, +1 from me. Regards, Tom Lane',
    ]), 'POST valid tgl to /register again';
    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{SCRIPT_NAME} = '/pub';
    ok $res->is_redirect, 'It should be a redirect response';
    is $res->headers->header('location'), $req->uri_for('/pub/account/thanks'),
        'Should redirect to /account/thanks';

    # And now Tom Lane should be registered.
    PGXN::Manager->conn->run(sub {
        is_deeply $_->selectrow_arrayref(q{
            SELECT full_name, email, uri, twitter, status
              FROM users
             WHERE nickname = ?
        }, undef, 'tgl'),
            ['Tom Lane', 'tgl@pgxn.org', 'http://tgl.example.org/', 'tomlane', 'new'],
            'TGL should exist';
    });

    is @{ Email::Sender::Simple->default_transport->deliveries },
        1, 'And an admin email should have been sent';
    Email::Sender::Simple->default_transport->clear_deliveries;
};

# Now try a conflicting email address.
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(POST(
        '/pub/account/register',
        Accept => 'text/html',
        Content => [
            full_name => 'Tom Lane',
            email     => 'tgl@pgxn.org',
            uri       => 'http://tgl.example.org/',
            nickname  => 'yodude',
            why       => 'In short, +1 from me. Regards, Tom Lane',
        ],
    )), 'POST yodude to /register';
    ok !$res->is_redirect, 'It should not be a redirect response';
    is $res->code, 409, 'Should have 409 status code';

    is @{ Email::Sender::Simple->default_transport->deliveries },
        0, 'No email should have been sent';

    # So check the content.
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{SCRIPT_NAME} = '/pub';
    XPathTest->test_basics($tx, $req, $mt, $hparams);

    # Now verify that we have the error message and that the form fields are
    # filled-in.
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 4, '... It should have four subelements');
        $tx->is('./h1', $h1, '... The title h1 should be set');
        $tx->is('./p[1]', $p, '... Intro paragraph should be set');
        my $err = $mt->maketext('Looks like you might already have an account. Need to reset your password?') . "\n   ";
        $tx->is('./p[@class="error"]', $err, '... Error paragraph should be set');
        $tx->is(
            './p[@class="error"]/a/@href',
            $req->uri_for('/reset', email => 'tgl@pgxn.org'),
            '... And it should have a link'
        );

        # Check the form fields.
        $tx->ok('./form[@id="reqform"]/fieldset[1]', '... Check first fieldset', sub {
            $tx->is('./input[@id="full_name"]/@value', 'Tom Lane', '...... Name should be set');
            $tx->is('./input[@id="email"]/@value', '', '...... Email should be blank');
            $tx->is('./input[@id="email"]/@class', 'required email', '...... And it should not be highlighted');
            $tx->is('./input[@id="uri"]/@value', 'http://tgl.example.org/', '...... URI should be set');
            $tx->is('./input[@id="nickname"]/@value', 'yodude', '...... Nickname should be set');
        });

        $tx->ok('./form[@id="reqform"]/fieldset[2]', '... Check second fieldset', sub {
            $tx->is(
                './textarea[@id="why"]',
                'In short, +1 from me. Regards, Tom Lane',
                '...... Why textarea should be set'
            );
        });
    });
};

# Start a new test transaction and create Tom via an API request.
TxnTest->restart;
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(POST(
        '/pub/account/register',
        'X-Requested-With' => 'XMLHttpRequest',
        Content => [
        full_name => 'Tom Lane',
        email     => 'tgl@pgxn.org',
        uri       => '',
        nickname  => 'tgl',
        why       => 'In short, +1 from me. Regards, Tom Lane',
    ])), 'POST valid XMLHttpRequest for tgl to /register again';
    ok $res->is_success, 'It should be a successful response';
    is $res->content, $mt->maketext('Success'), 'And the content should say so';

    # And now Tom Lane should be registered.
    PGXN::Manager->conn->run(sub {
        is_deeply $_->selectrow_arrayref(q{
            SELECT full_name, email, uri, status
              FROM users
             WHERE nickname = ?
        }, undef, 'tgl'), ['Tom Lane', 'tgl@pgxn.org', '', 'new'], 'TGL should exist';
    });

    is @{ Email::Sender::Simple->default_transport->deliveries },
       1, 'And an admin email should have been sent';
    Email::Sender::Simple->default_transport->clear_deliveries;
};

# Now use a conflicting email address, also submitted via XMLHttpRequest.
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(POST(
        '/pub/account/register',
        'X-Requested-With' => 'XMLHttpRequest',
        Content => [
            full_name => 'Tom Lane',
            email     => 'tgl@pgxn.org',
            uri       => 'http://tgl.example.org/',
            nickname  => 'yodude',
            why       => 'In short, +1 from me. Regards, Tom Lane',
        ]
    )), 'POST yodude via Ajax to /register';
    is $res->code, 409, 'Should have 409 status code';
    is @{ Email::Sender::Simple->default_transport->deliveries },
        0, 'No email should have been sent';

    is $res->content,
        $mt->maketext('Looks like you might already have an account. Need to reset your password?'),
        'And the content should reflect that error';
};

# Start a new test transaction and post with missing data.
TxnTest->restart;
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(POST '/pub/account/register', [
        full_name => '',
        email     => '',
        uri       => '',
        nickname  => '',
        why       => '',
    ]), 'POST empty form to /register yet again';
    ok !$res->is_redirect, 'It should not be a redirect response';
    is $res->code, 409, 'Should have 409 status code';

    is @{ Email::Sender::Simple->default_transport->deliveries },
        0, 'No email should have been sent';

    # So check the content.
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{SCRIPT_NAME} = '/pub';
    XPathTest->test_basics($tx, $req, $mt, $hparams);

    # Now verify that we have the error message.
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 4, '... It should have four subelements');
        $tx->is('./h1', $h1, '... The title h1 should be set');
        $tx->is('./p[1]', $p, '... Intro paragraph should be set');
        my $err = $mt->maketext('Sorry, the nickname “[_1]” is invalid. Your nickname must start with a letter, end with a letter or digit, and otherwise contain only letters, digits, or hyphen. Sorry to be so strict.', '');
        $tx->is('./p[@class="error"]', $err, '... Error paragraph should be set');
        $tx->is(
            './form/fieldset[1]/input[@id="nickname"]/@class',
            'required highlight',
            '... And the nickname field should be highlighted'
        );
    });
};

# Try a bogus nickname.
TxnTest->restart;
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(POST '/pub/account/register', [
        full_name => '',
        email     => '',
        uri       => '',
        nickname  => '-@@-',
        why       => '',
    ]), 'POST form with bogus nickname to /register';
    ok !$res->is_redirect, 'It should not be a redirect response';
    is $res->code, 409, 'Should have 409 status code';

    is @{ Email::Sender::Simple->default_transport->deliveries },
        0, 'No email should have been sent';

    # So check the content.
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{SCRIPT_NAME} = '/pub';
    XPathTest->test_basics($tx, $req, $mt, $hparams);

    # Now verify that we have the error message.
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 4, '... It should have four subelements');
        $tx->is('./h1', $h1, '... The title h1 should be set');
        $tx->is('./p[1]', $p, '... Intro paragraph should be set');
        my $err = $mt->maketext('Sorry, the nickname “[_1]” is invalid. Your nickname must start with a letter, end with a letter or digit, and otherwise contain only letters, digits, or hyphen. Sorry to be so strict.', '-@@-');
        $tx->is('./p[@class="error"]', $err, '... Error paragraph should be set');
        $tx->ok('./form/fieldset[1]/input[@id="nickname"]', '... Test nickname input', sub {
            $tx->is('./@value', '', '...... Its value should be empty');
            $tx->is('./@class', 'required highlight', '...... And it should be highlighted');
        })
    });
};

# Try a bogus email.
TxnTest->restart;
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(POST '/pub/account/register', [
        full_name => '',
        email     => 'getme at whatever dot com',
        uri       => '',
        nickname  => 'foo',
        why       => 'I rock',
    ]), 'POST form with bogus email to /register';
    ok !$res->is_redirect, 'It should not be a redirect response';
    is $res->code, 409, 'Should have 409 status code';

    is @{ Email::Sender::Simple->default_transport->deliveries },
        0, 'No email should have been sent';

    # So check the content.
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{SCRIPT_NAME} = '/pub';
    XPathTest->test_basics($tx, $req, $mt, $hparams);

    # Now verify that we have the error message.
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 4, '... It should have four subelements');
        $tx->is('./h1', $h1, '... The title h1 should be set');
        $tx->is('./p[1]', $p, '... Intro paragraph should be set');
        my $err = $mt->maketext(q{Hrm, “[_1]” doesn't look like an email address. Care to try again?}, 'getme at whatever dot com');
        $tx->is('./p[@class="error"]', $err, '... Error paragraph should be set');
        $tx->ok('./form/fieldset[1]/input[@id="email"]', '... Test email input', sub {
            $tx->is('./@value', '', '...... Its value should be empty');
            $tx->is('./@class', 'required email highlight', '...... And it should be highlighted');
        })
    });
};

# Try a bogus uri.
TxnTest->restart;
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(POST '/pub/account/register', [
        full_name => '',
        uri       => 'http:\\foo.com/',
        email     => 'foo@bar.com',
        nickname  => 'foo',
        why       => 'I rock',
    ]), 'POST form with bogus URI to /register';
    ok !$res->is_redirect, 'It should not be a redirect response';
    is $res->code, 409, 'Should have 409 status code';

    is @{ Email::Sender::Simple->default_transport->deliveries },
        0, 'No email should have been sent';

    # So check the content.
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{SCRIPT_NAME} = '/pub';
    XPathTest->test_basics($tx, $req, $mt, $hparams);

    # Now verify that we have the error message.
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 4, '... It should have four subelements');
        $tx->is('./h1', $h1, '... The title h1 should be set');
        $tx->is('./p[1]', $p, '... Intro paragraph should be set');
        my $err = $mt->maketext(q{Hrm, “[_1]” doesn't look like a URI. Care to try again?}, 'http:\\foo.com/');
        $tx->is('./p[@class="error"]', $err, '... Error paragraph should be set');
        $tx->ok('./form/fieldset[1]/input[@id="uri"]', '... Test uri input', sub {
            $tx->is('./@value', '', '...... Its value should be empty');
            $tx->is('./@class', 'highlight', '...... And it should be highlighted');
        })
    });
};

# Try an empty why.
TxnTest->restart;
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(POST '/pub/account/register', [
        full_name => '',
        uri       => 'http://foo.com/',
        email     => 'foo@bar.com',
        nickname  => 'foo',
        why       => '    ',
    ]), 'POST form with empty why to /register';
    ok !$res->is_redirect, 'It should not be a redirect response';
    is $res->code, 409, 'Should have 409 status code';

    is @{ Email::Sender::Simple->default_transport->deliveries },
        0, 'No email should have been sent';

    # So check the content.
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{SCRIPT_NAME} = '/pub';
    XPathTest->test_basics($tx, $req, $mt, $hparams);

    # Now verify that we have the error message.
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 4, '... It should have four subelements');
        $tx->is('./h1', $h1, '... The title h1 should be set');
        $tx->is('./p[1]', $p, '... Intro paragraph should be set');
        my $err = $mt->maketext(q{You forgot to tell us why you want an account. Is it because you're such a rockin PostgreSQL developer that we just can't do without you? Don't be shy, toot your own horn!});
        $tx->is('./p[@class="error"]', $err, '... Error paragraph should be set');
        $tx->is('./form/fieldset[2]/textarea', '', '... The why Textarea should be empty');
        $tx->is(
            './form/fieldset[2]/textarea/@class',
            'required highlight',
            '... And it should be highlighted'
        );
    });
};
