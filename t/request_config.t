#!/usr/bin/env perl -w

use 5.10.0;
use utf8;
use Test::More tests => 6;
#use Test::More 'no_plan';
use HTTP::Request::Common;
use HTTP::Message::PSGI;

use PGXN::Manager;

BEGIN {
    # Change the script name key before loading the request object.
    PGXN::Manager->config->{uri_script_name_key} = 'HTTP_X_SCRIPT_NAME';

    # Set the login URI.
    PGXN::Manager->config->{auth_uri} = 'https://manager.pgxn.org/';
}

use PGXN::Manager::Request;

isa_ok my $req = PGXN::Manager::Request->new(req_to_psgi(GET(
    '/', 'X-Script-Name' => '/hello'
))), 'PGXN::Manager::Request', 'Request';

my $base = $req->base;

is $req->uri_for('foo'), $base . 'foo', 'uri_for(foo)';
is $req->uri_for('/foo'), $base . 'hello/foo', 'uri_for(/foo)';

ok $req = PGXN::Manager::Request->new(req_to_psgi(GET(
    '/app', 'X-Script-Name' => '/hi'
))), 'Create a request to /app';

is $req->uri_for('foo'), $base . 'app/foo', 'app uri_for(foo)';
is $req->uri_for('/foo'), $base . 'hi/foo', 'app uri_for(/foo)';
