#!/usr/bin/env perl

use 5.12.0;
use utf8;
use Test::More tests => 25;
#use Test::More 'no_plan';
use lib '/Users/david/dev/github/Plack/lib';
use HTTP::Request::Common;
use HTTP::Message::PSGI;
use MIME::Base64;
use lib 't/lib';
use TxnTest;

BEGIN {
    use_ok 'PGXN::Manager::Request';
}

isa_ok my $req = PGXN::Manager::Request->new(req_to_psgi(GET '/')),
    'PGXN::Manager::Request', 'Request';
isa_ok $req, 'Plack::Request', 'It also';

##############################################################################
# Test uri_for()
my $base = $req->base;

is $req->uri_for('foo'), $base . 'foo', 'uri_for(foo)';
is $req->uri_for('/foo'), $base . 'foo', 'uri_for(/foo)';

ok $req = PGXN::Manager::Request->new(req_to_psgi(GET '/app')),
    'Create a request to /app';

is $req->uri_for('foo'), $base . 'app/foo', 'app uri_for(foo)';
is $req->uri_for('/foo'), $base . 'foo', 'app uri_for(/foo)';

is $req->uri_for('foo', bar => 'baz'), $base . 'app/foo?bar=baz',
    'app uri_for(foo, bar => baz)';

is $req->uri_for('foo', bar => 'baz', 'foo' => 1),
    $base . 'app/foo?bar=baz;foo=1',
    'app uri_for(foo, bar => baz, foo => 1)';

##############################################################################
# Test respond_with()
isa_ok $req = +PGXN::Manager::Request->new(req_to_psgi(GET(
    '/',
    'Accept' => 'application/xml,application/xhtml+xml,text/html;q=0.9,text/plain;q=0.8,image/png,*/*;q=0.5',
    'Accept-Encoding' => 'gzip, deflate',
    'Accept-Language' => 'en-us',
))), 'PGXN::Manager::Request', 'Request with headers';
can_ok $req, 'respond_with';
is_deeply [$req->respond_with], [
    [ 'html', '0.9', 4000 ],
    [ 'text', '0.8', 1000 ],
    [ 'json', '0.5', 2000 ],
    [ 'atom', '0.5', 3000 ],
], 'respond_with should prefer html';

is_deeply scalar $req->respond_with, 'html',
    'And should return only HTML in scalar context';

# Try preferring atom.
$req->headers->push_header(Accept => 'application/atom+xml;q=0.91');
is $req->respond_with, 'atom', 'Should now prefer atom';

# Try preferring JSON.
$req->headers->push_header(Accept => 'application/json;q=0.93');
is $req->respond_with, 'json', 'Should now prefer json';

# Try making JSON lower than atom.
$req->headers->header(Accept => 'application/atom+xml;q=0.91,application/json;q=0.90)');
is $req->respond_with, 'atom', 'Should prefer atom again';

# Now have them tie. Smallest content-size should win.
$req->headers->header(Accept => 'application/atom+xml;q=0.91,application/json;q=0.91)');
is $req->respond_with, 'json', 'Should prefer json for a tie';

##############################################################################
# Test user_is_admin()
ok !$req->user_is_admin, 'user_is_admin should be false';

# Create and authenticate non-admin user.
my $user = TxnTest->user;
isa_ok $req = +PGXN::Manager::Request->new(req_to_psgi(
    GET '/auth'
)), 'PGXN::Manager::Request', 'Auth request';

$req->env->{REMOTE_USER} = $user;
is $req->user, $user, 'User should be authenicated';
ok !$req->user_is_admin, '... But not an admin';

# Create and authenticate admin user.
my $admin = TxnTest->admin;
isa_ok $req = +PGXN::Manager::Request->new(req_to_psgi(
    GET '/auth'
)), 'PGXN::Manager::Request', 'Admin Auth request';

$req->env->{REMOTE_USER} = $admin;
is $req->user, $admin, 'Admin should be authenicated';
ok $req->user_is_admin, '... And should be an admin';
