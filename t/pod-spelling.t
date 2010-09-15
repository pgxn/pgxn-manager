#!/usr/bin/env perl

use 5.12.0;
use utf8;
use Test::More;

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
