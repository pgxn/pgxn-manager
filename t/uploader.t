#!/usr/bin/env perl

use 5.12.0;
use utf8;
#use Test::More tests => 1;
use Test::More 'no_plan';

my $CLASS;

BEGIN {
    $CLASS = 'PGXN::Manager::Uploader';
    use_ok $CLASS or die;
}

