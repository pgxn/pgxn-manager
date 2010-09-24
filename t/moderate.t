#!/usr/bin/env perl

use 5.12.0;
use utf8;
use Test::More tests => 103;
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
use MIME::Base64;

my $app      = PGXN::Manager::Router->app;
my $mt       = PGXN::Manager::Locale->accept('en');
my $uri      = '/auth/admin/moderate';

# Connect without authenticating.
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET $uri), "GET $uri";
    is $res->code, 401, 'Should get 401 response';
    like $res->content, qr/Authorization required/,
        'The body should indicate need for authentication';
};

# Authenticate a non-admin user.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb   = shift;
    my $user = TxnTest->user;
    my $req  = GET $uri, Authorization => 'Basic ' . encode_base64("$user:****");

    ok my $res = $cb->($req), "Get $uri with auth token";
    is $res->code, 403, 'Should get 403 response';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($req));
    $req->env->{REMOTE_USER} = $user;
    XPathTest->test_basics($tx, $req, $mt, { h1 => 'Permission Denied' });

    $tx->ok('/html/body/div[@id="content"]', 'Look at the content', sub {
        $tx->is('count(./*)', 2, '... Should have two subelements');
        $tx->is(
            './p[@class="error"]',
            $mt->maketext(q{Sorry, you do not have permission to access this page.}),
            '... Should have the error message'
        );
    });
};

# Authenticate an admin user.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb    = shift;
    my $admin = TxnTest->admin;
    my $req   = GET $uri, Authorization => 'Basic ' . encode_base64("$admin:****");

    ok my $res = $cb->($req), "Get $uri with auth token";
    ok $res->is_success, 'Response should be success';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($req));
    $req->env->{REMOTE_USER} = $admin;
    XPathTest->test_basics($tx, $req, $mt, { h1 => 'Moderate Account Requests' });

    $tx->ok('/html/body/div[@id="content"]', 'Look at the content', sub {
        $tx->is('count(./*)', 4, '... Should have four subelements');
    });
};

