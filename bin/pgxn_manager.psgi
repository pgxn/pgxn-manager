#!/usr/bin/env perl

use 5.12.0;
use utf8;
use lib 'lib';
use aliased 'PGXN::Manager::Router';
Router->app;
