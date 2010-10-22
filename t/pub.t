#!/usr/bin/env perl -w

use 5.12.0;
use utf8;
BEGIN { $ENV{EMAIL_SENDER_TRANSPORT} = 'Test' }

use Test::More tests => 409;
#use Test::More 'no_plan';
use Plack::Test;
use HTTP::Request::Common;
use PGXN::Manager::Router;
use HTTP::Message::PSGI;
use Test::XML;
use Test::XPath;
use MIME::Base64;
use lib 't/lib';
use XPathTest;
use TxnTest;

my $app  = PGXN::Manager::Router->app;
my $mt   = PGXN::Manager::Locale->accept('en');
my $user = TxnTest->user;

# Test /pub/contact basics.
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET '/pub/contact'), "GET /pub/contact";
    ok $res->is_success, 'Should be a successful request';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{SCRIPT_NAME} = '/pub';
    XPathTest->test_basics($tx, $req, $mt, {
        h1         => 'Contact Us',
        page_title => 'contact_page_title',
    });
};

# Test /auth/contact basics.
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET(
        '/auth/contact',
        Authorization => 'Basic ' . encode_base64("$user:****"),
    )), "GET /auth/contact";
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{REMOTE_USER} = $user;
    $req->env->{SCRIPT_NAME} = '/auth';
    XPathTest->test_basics($tx, $req, $mt, {
        h1         => 'Contact Us',
        page_title => 'contact_page_title',
    });
};

# Test /pub/about basics.
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET '/pub/about'), "GET /pub/about";
    ok $res->is_success, 'Should be a successful request';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{SCRIPT_NAME} = '/pub';
    XPathTest->test_basics($tx, $req, $mt, {
        h1         => 'About PGXN Manager',
        page_title => 'about_page_title',
    });
};

# Test /auth/about basics.
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET(
        '/auth/about',
        Authorization => 'Basic ' . encode_base64("$user:****"),
    )), "GET /auth/about";
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{REMOTE_USER} = $user;
    $req->env->{SCRIPT_NAME} = '/auth';
    XPathTest->test_basics($tx, $req, $mt, {
        h1         => 'About PGXN Manager',
        page_title => 'about_page_title',
    });
};

# Test /pub/howto basics.
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET '/pub/howto'), "GET /pub/howto";
    ok $res->is_success, 'Should be a successful request';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{SCRIPT_NAME} = '/pub';
    XPathTest->test_basics($tx, $req, $mt, {
        h1         => 'PGXN How To',
        page_title => 'howto_page_title',
    });

    my $content = quotemeta ${ $mt->section_data('howto') };
    like $res->decoded_content, qr/$content/, 'Content should match locale section data';
};

# Test /auth/howto basics.
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET(
        '/auth/howto',
        Authorization => 'Basic ' . encode_base64("$user:****"),
    )), "GET /auth/howto";
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{REMOTE_USER} = $user;
    $req->env->{SCRIPT_NAME} = '/auth';
    XPathTest->test_basics($tx, $req, $mt, {
        h1         => 'PGXN How To',
        page_title => 'howto_page_title',
    });

    my $content = quotemeta ${ $mt->section_data('howto') };
    like $res->decoded_content, qr/$content/, 'Content should match locale section data';
};

# Test /pub/error basics.
my $err_app = sub {
    my $env = shift;
    $env->{'psgix.errordocument.PATH_INFO'} = '/';
    $env->{'psgix.errordocument.SCRIPT_NAME'} = '/pub';
    $env->{'psgix.errordocument.SCRIPT_NAME'} = '/pub';
    $env->{'psgix.errordocument.HTTP_HOST'} = 'localhost';
    $env->{'psgix.trace'} = 'This is the trace';
    $app->($env);
};

test_psgi $err_app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET '/pub/error'), "GET /pub/error";
    ok $res->is_success, 'Should be a successful request';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{SCRIPT_NAME} = '/pub';
    XPathTest->test_basics($tx, $req, $mt, {
        h1         => 'Ow ow ow ow ow ow…',
        page_title => 'Internal Server Error',
    });

    test_error_response($tx);
};

# Test /auth/error basics.
test_psgi $err_app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET(
        '/auth/error',
        Authorization => 'Basic ' . encode_base64("$user:****"),
    )), "GET /auth/error";
    ok $res->is_success, 'Should be a successful request';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{REMOTE_USER} = $user;
    $req->env->{SCRIPT_NAME} = '/auth';
    XPathTest->test_basics($tx, $req, $mt, {
        h1         => 'Ow ow ow ow ow ow…',
        page_title => 'Internal Server Error',
    });

    test_error_response($tx);
};

sub test_error_response {
    my $tx = shift;
    # Check the content.
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 2, '... It should have two subelements');
        $tx->like(
            './p[@class="error"]',
            qr/We apologise for the fault in the server/,
            '... Error paragraph should be there'
        );
    });

    # Check the alert email.
    ok my $deliveries = Email::Sender::Simple->default_transport->deliveries,
        'Should have email deliveries.';
    is @{ $deliveries }, 1, 'Should have one message';
    is @{ $deliveries->[0]{successes} }, 1, 'Should have been successfully delivered';

    my $email = $deliveries->[0]{email};
    is $email->get_header('Subject'), 'PGXN Manager Internal Server Error',
        'The subject should be set';
    is $email->get_header('From'), PGXN::Manager->config->{admin_email},
        'From header should be set';
    is $email->get_header('To'), PGXN::Manager->config->{alert_email},
        'To header should be set';
    is $email->get_body, 'An error occurred during a request to http://localhost/pub/.

Environment:

{ HTTP_HOST => "localhost", PATH_INFO => "/", SCRIPT_NAME => "/pub" }

Trace:

This is the trace
',
    'The body should be correct';
    Email::Sender::Simple->default_transport->clear_deliveries;
}
