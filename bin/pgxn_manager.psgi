#!/usr/bin/env perl

use 5.12.0;
use utf8;
use lib 'lib';
use PGXN::Manager::Router;
PGXN::Manager->instance->init_root;
PGXN::Manager::Router->app;
