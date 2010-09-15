#!/usr/bin/env perl

use 5.12.0;
use utf8;
#use Test::More tests => 1;
use Test::More 'no_plan';

my $CLASS;

BEGIN {
    $CLASS = 'PGXN::Manager::Distribution';
    use_ok $CLASS or die;
}

can_ok $CLASS, qw(process extract DEMOLISH read_meta register index);
