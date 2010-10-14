#!/usr/bin/env perl

use 5.12.0;
use utf8;
use Test::More tests => 150;
#use Test::More 'no_plan';
use Test::XML;
use Test::XPath;
use PGXN::Manager::Request;
use HTTP::Request::Common;
use HTTP::Message::PSGI;
use lib 't/lib';
use XPathTest;
use TxnTest;

BEGIN {
    use_ok 'PGXN::Manager::Templates';
}

Template::Declare->init( dispatch_to => ['PGXN::Manager::Templates'] );

ok my $req = PGXN::Manager::Request->new(req_to_psgi(GET '/')),
    'Create a Plack request object';
$req->env->{'psgix.session'} = {};
my $mt = PGXN::Manager::Locale->accept($req->env->{HTTP_ACCEPT_LANGUAGE});

ok my $html = Template::Declare->show('home', $req, {
    description => 'Whatever desc',
    keywords    => 'yes,no',
}), 'Show home';

is_well_formed_xml $html, 'The HTML should be well-formed';
my $tx = Test::XPath->new( xml => $html, is_html => 1 );
XPathTest->test_basics($tx, $req, $mt, {
    desc       => 'Whatever desc',
    keywords   => 'yes,no',
    h1         => $mt->maketext('Welcome'),
    page_title => 'Distribute PostgreSQL extensions on our world-wide network',
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
$req->env->{HTTP_ACCEPT_LANGUAGE} = 'en';

# Try with an authenticated user.
my $user = TxnTest->user;
ok $req = PGXN::Manager::Request->new(req_to_psgi(GET '/')),
    'Create another Plack request object';
$req->env->{'psgix.session'} = {};
$mt = PGXN::Manager::Locale->accept($req->env->{HTTP_ACCEPT_LANGUAGE});
$req->env->{REMOTE_USER} = $user;
is $req->user, $user, 'User should be authenicated';

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
    page_title => 'Distribute PostgreSQL extensions on our world-wide network',
});

# Try with an amin user.
my $admin = TxnTest->admin;
ok $req = PGXN::Manager::Request->new(req_to_psgi(GET '/')),
    'Create another Plack request object';
$req->env->{'psgix.session'} = {};
$mt = PGXN::Manager::Locale->accept($req->env->{HTTP_ACCEPT_LANGUAGE});
$req->env->{REMOTE_USER} = $admin;
is $req->user, $admin, 'User should be authenicated';
ok $req->user_is_admin, 'User should be admin';

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
    page_title => 'Distribute PostgreSQL extensions on our world-wide network',
});
