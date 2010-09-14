#!/usr/bin/env perl

use 5.12.0;
use utf8;
use Test::More tests => 15;
my $CLASS;

BEGIN {
    $CLASS = 'PGXN::Manager::Maketext';
    use_ok $CLASS or die;
}

isa_ok my $l = $CLASS->get_handle('en'), $CLASS, 'English handle';
isa_ok $l, "$CLASS\::en", 'It also';
is $l->maketext('Welcome'), 'Welcome', 'It should translate "Welcome"';

# Try get_handle() with bogus language.
isa_ok my $l = $CLASS->get_handle('nonesuch'), $CLASS, 'Nonesuch get_handle handle';
isa_ok $l, "$CLASS\::en", 'It also';
is $l->maketext('Welcome'), 'Welcome', 'It should translate "Welcome"';

# Try french.
isa_ok my $l = $CLASS->get_handle('fr'), $CLASS, 'French handle';
isa_ok $l, "$CLASS\::fr", 'It also';
is $l->maketext('Welcome'), 'Bienvenue', 'It should translate "Welcome"';

# Try pass-through.
is $l->maketext('whatever'), 'whatever', 'It should pass through unknown phrase';

# Try accept.
isa_ok my $l = $CLASS->accept('en;q=1,fr;q=.5'), $CLASS, 'Accept handle';
isa_ok $l, "$CLASS\::en", 'It also';

isa_ok my $l = $CLASS->accept('en;q=1,fr;q=2'), $CLASS, 'French accept handle';
isa_ok $l, "$CLASS\::fr", 'It also';
