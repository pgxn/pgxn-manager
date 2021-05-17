#!/usr/bin/env perl -w

use 5.10.0;
use utf8;
BEGIN { $ENV{EMAIL_SENDER_TRANSPORT} = 'Test' }

use Test::More tests => 210;
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

# Test /contact basics.
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET '/contact'), "GET /contact";
    ok $res->is_success, 'Should be a successful request';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    XPathTest->test_basics($tx, $req, $mt, {
        h1         => 'Contact Us',
        page_title => 'contact_page_title',
    });
};

# Test /about basics.
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET '/about'), "GET /about";
    ok $res->is_success, 'Should be a successful request';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    XPathTest->test_basics($tx, $req, $mt, {
        h1         => 'About PGXN Manager',
        page_title => 'about_page_title',
    });
};

# Test /howto basics.
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET '/howto'), "GET /howto";
    ok $res->is_success, 'Should be a successful request';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    XPathTest->test_basics($tx, $req, $mt, {
        h1         => 'PGXN How To',
        page_title => 'howto_page_title',
    });

    my $content = quotemeta $mt->maketext('howto_body');
    like $res->decoded_content, qr/$content/, 'Content should match locale section data';
};

# Test /error basics.
my $err_app = sub {
    my $env = shift;
    $env->{'psgix.errordocument.PATH_INFO'} = '/';
    $env->{'psgix.errordocument.SCRIPT_NAME'} = '/foo';
    $env->{'psgix.errordocument.HTTP_HOST'} = 'localhost';
    $env->{'psgix.errordocument.HTTP_AUTHORIZATION'} = 'Basic ' . encode_base64("user:****");
    $env->{'plack.stacktrace.text'} = 'This is the trace';
    $app->($env);
};

test_psgi $err_app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET '/error'), "GET /error";
    ok $res->is_success, 'Should be a successful request';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
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
    ok my @deliveries = Email::Sender::Simple->default_transport->deliveries,
        'Should have email deliveries.';
    is @deliveries, 1, 'Should have one message';
    is @{ $deliveries[0]{successes} }, 1, 'Should have been successfully delivered';

    my $email = $deliveries[0]{email};
    is $email->get_header('Subject'), 'PGXN Manager Internal Server Error',
        'The subject should be set';
    is $email->get_header('From'), PGXN::Manager->config->{admin_email},
        'From header should be set';
    is $email->get_header('To'), PGXN::Manager->config->{alert_email},
        'To header should be set';
    is $email->get_body, 'An error occurred during a request to http://localhost/foo/.

Trace:

This is the trace

Environment:

{
  HTTP_AUTHORIZATION => "[REDACTED]",
  HTTP_HOST          => "localhost",
  PATH_INFO          => "/",
  SCRIPT_NAME        => "/foo",
}
',
    'The body should be correct';
    Email::Sender::Simple->default_transport->clear_deliveries;
}
