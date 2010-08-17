#!/usr/bin/env perl

use 5.12.0;
use utf8;
use Test::More;

eval "use Test::Pod::Coverage 1.06";
plan skip_all => 'Test::Pod::Coverage 1.06 required' if $@;
all_pod_coverage_ok();
