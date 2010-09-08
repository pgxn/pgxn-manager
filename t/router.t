#!/usr/bin/env perl

use 5.12.0;
use utf8;
use Test::More tests => 4;
#use Test::More 'no_plan';
use Plack::Test;
use HTTP::Request::Common;

BEGIN {
    use_ok 'PGXN::Manager::Router' or die;
}

test_psgi +PGXN::Manager::Router->app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET '/'), 'Fetch /';
    is $res->code, 200, 'Should get 200 response';
    is $res->content, 'Hello World', 'The body should be correct';
};
