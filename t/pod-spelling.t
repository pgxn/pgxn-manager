#!/usr/bin/env perl -w

use 5.10.0;
use utf8;
use Test::More;

plan skip_all => 'No point in checking spelling when $LANG is not US English'
    unless $ENV{LANG} eq 'en_US.UTF-8';
eval "use Test::Spelling";
plan skip_all => "Test::Spelling required for testing POD spelling" if $@;

add_stopwords(<DATA>);
all_pod_files_spelling_ok();

__DATA__
admin
API
APIs
app
app's
auth
gendoc
hereunder
http
IP
jQuery
JSON
merchantability
metadata
middlewares
OAuth
PGXN
Plack
PostgreSQL
programmatically
reindex
reindexes
Reindexes
repack
SQL
subrequests
tuples
UI
uploader
UTF
yikes
