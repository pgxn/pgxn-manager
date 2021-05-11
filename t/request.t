#!/usr/bin/env perl -w

use 5.10.0;
use utf8;
use Test::More tests => 54;
#use Test::More 'no_plan';
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
    'uri_for(foo, bar => baz)';

is $req->uri_for('foo', bar => 'baz', 'foo' => 1),
    $base . 'app/foo?bar=baz;foo=1',
    'uri_for(foo, bar => baz, foo => 1)';

##############################################################################
# Test auth_uri() and auth_uri_for().
$req->env->{SCRIPT_NAME} = '/foo';
is $req->auth_uri, 'http://localhost', 'Should have default login URI';
$base = 'http://localhost/';

is $req->auth_uri_for('foo'), $base . 'foo',
    'auth_uri() should work with a simple string';
is $req->auth_uri_for('/foo'), $base . 'foo',
    'auth_uri() should work with an absolute URI';
is $req->auth_uri_for('foo', bar => 'baz'), $base . 'foo?bar=baz',
    'auth_uri_for(foo, bar => baz)';

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
$req->headers->header(Accept => 'application/atom+xml;q=0.91,application/json;q=0.90');
is $req->respond_with, 'atom', 'Should prefer atom again';

# Now have them tie. Smallest content-size should win.
$req->headers->header(Accept => 'application/atom+xml;q=0.91,application/json;q=0.91');
is $req->respond_with, 'json', 'Should prefer json for a tie';

isa_ok $req = PGXN::Manager::Request->new(req_to_psgi(GET(
    '/',
    'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Encoding' => 'gzip, deflate',
    'Accept-Language' => 'en-us,en;q=0.5',
))), 'PGXN::Manager::Request', 'Request with different headers';
is $req->respond_with, 'html', 'Should respond with HTML';

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

##############################################################################
# Test is_xhr()
ok !$req->is_xhr, 'Request should not be Ajax';
isa_ok $req = +PGXN::Manager::Request->new(req_to_psgi(GET(
    '/',
    'X-Requested-With' => 'XMLHttpRequest',
))), 'PGXN::Manager::Request', 'Request with X-Requested-With header';
ok $req->is_xhr, 'New request should be Ajax';

##############################################################################
# Test decoded params.
ok $req = PGXN::Manager::Request->new({
    QUERY_STRING => "q=%E3%83%A1%E3%82%A4%E3%83%B3%E3%83%9A%E3%83%BC%E3%82%B8",
}), 'Create request with unicode query string';
is_deeply $req->query_parameters, { q => "メインページ" },
    'Query params should be decoded';
is_deeply $req->parameters, { q => "メインページ" },
    'All params should be decoded';
is $req->param('q'), "メインページ", 'q param should be decoded';

# Try setting content type of submission.
ok $req = PGXN::Manager::Request->new({
    CONTENT_TYPE => 'application/x-www-form-urlencoded; charset=euc-jp',
    QUERY_STRING => "q=%A5%C6%A5%B9%A5%C8",
}), 'Create request with content type with charset';
is_deeply $req->parameters, { q => "テスト" },
    'The euc-jp params should be decoded';
is $req->param('q'), "テスト", 'And a single param should be decoded';

# Try post.
my $body ="q=%A5%C6%A5%B9%A5%C8";
ok  $req = PGXN::Manager::Request->new({
    CONTENT_TYPE   => 'application/x-www-form-urlencoded; charset=euc-jp',
    CONTENT_LENGTH => length $body,
    'psgi.input'   => do { open my $io, "<", \$body; $io },
}), 'Create request with encoded body';
is_deeply $req->body_parameters, { q => "テスト" }, 'All body params should be decoded';
is_deeply $req->parameters, { q => "テスト" }, 'All params should be decoded';
is $req->param('q'), "テスト", 'Single param should be decoded';

# Make sure multiple params with same name work.
{
    no utf8;
    isa_ok $req = +PGXN::Manager::Request->new(req_to_psgi(POST('/', [
        q => 'テスト',
        q => 'メインページ',
    ]))), 'PGXN::Manager::Request', 'Create request with multiple fields with same name';
}

is_deeply $req->body_parameters, { q => "メインページ" },
    'All params should be decoded';
is_deeply $req->parameters, { q => "メインページ" },
    'Query params should be decoded';
is $req->param('q'), "メインページ", 'q param should be decoded';
is_deeply [$req->parameters->get_all('q')], ['テスト', 'メインページ'],
    'All q values should be decoded';

##############################################################################
# Test remote_host() and address().
is $req->remote_host, 'localhost', 'remote_host should be "localhost"';
is $req->address, '127.0.0.1', 'remote_host should be "127.0.0.1"';
$req->env->{HTTP_X_FORWARDED_HOST} = 'foo';
is $req->remote_host, 'foo', 'remote_host should prefer X-Forwarded-host';
$req->env->{HTTP_X_FORWARDED_FOR} = '192.168.0.1';
is $req->address, '192.168.0.1', 'remote_host should prefer X-Forwarded-For';
