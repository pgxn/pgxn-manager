#!/usr/bin/env perl

use 5.12.0;
use utf8;
use Test::More;

plan skip_all => 'No point in checking spelling when $LANG is not US English'
    unless $ENV{LANG} eq 'en_US.UTF-8';
eval "use Test::Spelling";
plan skip_all => "Test::Spelling required for testing POD spelling" if $@;

add_stopwords(<DATA>);
all_pod_files_spelling_ok();

__DATA__
gendoc
Plack
PGXN
UI
uploader
tuples
jQuery
UTF
SQL
PostgreSQL
API
metadata
