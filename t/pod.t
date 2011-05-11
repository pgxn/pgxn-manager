#!/usr/bin/env perl -w

use 5.10.0;
use utf8;
use Test::More;

eval 'use Test::Pod 1.41';
plan skip_all => 'Test::Pod 1.41 required for testing POD' if $@;
all_pod_files_ok();
