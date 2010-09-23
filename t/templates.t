#!/usr/bin/env perl

use 5.12.0;
use utf8;
use Test::More tests => 43;
#use Test::More 'no_plan';
use Test::XML;
use Test::XPath;
use PGXN::Manager::Request;
use HTTP::Request::Common;
use HTTP::Message::PSGI;
use lib 't/lib';
use XPathTest;

BEGIN {
    use_ok 'PGXN::Manager::Templates';
}

Template::Declare->init( dispatch_to => ['PGXN::Manager::Templates'] );

ok my $req = PGXN::Manager::Request->new(req_to_psgi(GET '/')),
    'Create a Plack request object';
my $mt = PGXN::Manager::Locale->accept($req->env->{HTTP_ACCEPT_LANGUAGE});

ok my $html = Template::Declare->show('home', $req, {
    description => 'Whatever desc',
    keywords    => 'yes,no',
}), 'Show home';

is_well_formed_xml $html, 'The HTML should be well-formed';
my $tx = Test::XPath->new( xml => $html, is_html => 1 );
XPathTest->test_basics($tx, $req, $mt, {
    desc        => 'Whatever desc',
    keywords    => 'yes,no',
    h1          => $mt->maketext('Welcome'),
});

# Try in french.
$req->env->{HTTP_ACCEPT_LANGUAGE} = 'fr';
ok $html = Template::Declare->show('home', $req ), 'Show French home';
is_well_formed_xml $html, 'French HTML should be well-formed';
my $tx = Test::XPath->new( xml => $html, is_html => 1 );
$tx->is(
    '/html/body/div[@id="content"]/h1',
    'Bienvenue',
    'French HTML should have localized h1'
);
