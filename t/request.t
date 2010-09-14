#!/usr/bin/env perl

use 5.12.0;
use utf8;
use Test::More tests => 10;
#use Test::More 'no_plan';
use HTTP::Request::Common;
use HTTP::Message::PSGI;

BEGIN {
    use_ok 'PGXN::Manager::Request';
}

isa_ok my $req = PGXN::Manager::Request->new(req_to_psgi(GET '/')),
    'PGXN::Manager::Request', 'Request';
isa_ok $req, 'Plack::Request', 'It also';

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
