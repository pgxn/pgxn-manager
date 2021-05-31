#!/usr/bin/env perl -w

use 5.10.0;
use strict;
use warnings;
use utf8;

use Test::More tests => 29;
#use Test::More 'no_plan';
my $CLASS;

BEGIN {
    $CLASS = 'PGXN::Manager::Locale';
    use_ok $CLASS or die;
}

isa_ok my $l = $CLASS->get_handle('en'), $CLASS, 'English handle';
isa_ok $l, "$CLASS\::en", 'It also';
is $l->maketext('Welcome'), 'Welcome', 'It should translate "Welcome"';

# Try get_handle() with bogus language.
isa_ok $l = $CLASS->get_handle('nonesuch'), $CLASS, 'Nonesuch get_handle handle';
isa_ok $l, "$CLASS\::en", 'It also';
is $l->maketext('Welcome'), 'Welcome', 'It should translate "Welcome"';

# Try french.
isa_ok $l = $CLASS->get_handle('fr'), $CLASS, 'French handle';
isa_ok $l, "$CLASS\::fr", 'It also';
is $l->maketext('Welcome'), 'Bienvenue', 'It should translate "Welcome"';

# Try pass-through.
is $l->maketext('whatever'), 'whatever', 'It should pass through unknown phrase';

# Try accept.
isa_ok $l = $CLASS->accept('en;q=1,fr;q=.5'), $CLASS, 'Accept handle';
isa_ok $l, "$CLASS\::en", 'It also';

isa_ok $l = $CLASS->accept('en;q=1,fr;q=2'), $CLASS, 'French accept handle';
isa_ok $l, "$CLASS\::fr", 'It also';

# Try en list().
ok my $lh = $CLASS->get_handle('en'), 'Get English handle';
is $lh->maketext('[list,_1]', ['foo', 'bar']),
    'foo and bar', 'en list() should work';
is $lh->maketext('[list,_1]', ['foo']),
    'foo', 'single-item en list() should work';
is $lh->maketext('[list,_1]', ['foo', 'bar', 'baz']),
    'foo, bar, and baz', 'triple-item en list() should work';

# Try en qlist()
is $lh->maketext('[qlist,_1]', ['foo', 'bar']),
    '“foo” and “bar”', 'en qlist() should work';
is $lh->maketext('[qlist,_1]', ['foo']),
    '“foo”', 'single-item en qlist() should work';
is $lh->maketext('[qlist,_1]', ['foo', 'bar', 'baz']),
    '“foo”, “bar”, and “baz”', 'triple-item en qlist() should work';

# Try fr list().
ok $lh = $CLASS->get_handle('fr'), 'Get Frglish hetle';
is $lh->maketext('[list,_1]', ['foo', 'bar']),
    'foo et bar', 'fr list() should work';
is $lh->maketext('[list,_1]', ['foo']),
    'foo', 'single-item fr list() should work';
is $lh->maketext('[list,_1]', ['foo', 'bar', 'baz']),
    'foo, bar, et baz', 'triple-item fr list() should work';

# Try fr qlist()
is $lh->maketext('[qlist,_1]', ['foo', 'bar']),
    '«foo» et «bar»', 'fr qlist() should work';
is $lh->maketext('[qlist,_1]', ['foo']),
    '«foo»', 'single-item fr qlist() should work';
is $lh->maketext('[qlist,_1]', ['foo', 'bar', 'baz']),
    '«foo», «bar», et «baz»', 'triple-item fr qlist() should work';
