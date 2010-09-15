#!/usr/bin/env perl

use 5.12.0;
use utf8;
#use Test::More tests => 1;
use Test::More 'no_plan';
use Archive::Zip qw(:ERROR_CODES);
use File::Basename;

my $CLASS;

BEGIN {
    $CLASS = 'PGXN::Manager::Distribution';
    use_ok $CLASS or die;
}

can_ok $CLASS, qw(process extract DEMOLISH read_meta register index);

my $distdir = File::Spec->catdir(qw(t dist widget));
my $distzip = File::Spec->catdir(qw(t dist widget-0.2.5.pgz'));

# First, create a distribution.
my $zip = Archive::Zip->new;
$zip->addTree($distdir, 'widget-0.2.5') == AZ_OK or die 'tree error';
$zip->writeToFileNamed($distzip) == AZ_OK or die 'write error';

END { unlink $distzip; }


