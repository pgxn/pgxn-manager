#!/usr/bin/env perl -w

use 5.10.0;
use strict;
use warnings;
use utf8;
use Test::More;

eval "use Test::Pod::Coverage 1.06";
plan skip_all => 'Test::Pod::Coverage 1.06 required' if $@;
all_pod_coverage_ok({ also_private => [ qr/^[A-Z_]+$/ ] });
