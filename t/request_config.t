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
}

use PGXN::Manager::Request;

my $base = 'http://localhost/hello/';
my $env = req_to_psgi GET $base;
$env->{HTTP_X_SCRIPT_NAME} = '/hello';

isa_ok my $req = PGXN::Manager::Request->new($env), 'PGXN::Manager::Request', 'Request';
is $req->uri_for('foo'), $base . 'foo', 'uri_for(foo)';
is $req->uri_for('/foo'), $base . 'foo', 'uri_for(/foo)';

$base = 'http://localhost/hi/';
my $env = req_to_psgi GET $base . 'app';
$env->{HTTP_X_SCRIPT_NAME} = '/hi';

ok $req = PGXN::Manager::Request->new($env), 'Create a request to /hi/app';
is $req->uri_for('foo'), $base . 'foo', 'app uri_for(foo)';
is $req->uri_for('/foo'), $base . 'foo', 'app uri_for(/foo)';
