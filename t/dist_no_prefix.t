#!/usr/bin/env perl -w

use 5.10.0;
use strict;
use warnings;
use utf8;

use Test::More tests => 7;
#use Test::More 'no_plan';
use Test::File;
use File::Path qw(remove_tree);
use PGXN::Manager::Distribution;
use Archive::Zip qw(:ERROR_CODES);
use lib 't/lib';
use TxnTest;

my $tmpdir = File::Spec->catdir(File::Spec->tmpdir, 'pgxn');
my $root   = PGXN::Manager->new->config->{mirror_root};

BEGIN { $ENV{HTTP_ACCEPT_LANGUAGE} = 'en' }
END { remove_tree $tmpdir, $root }

my $user = TxnTest->user; # Create user.
my $distzip = File::Spec->catdir(qw(t dist faker-0.4.0.zip));

my $dist = PGXN::Manager::Distribution->new(
    creator  => 'user',
    archive  => $distzip,
    basename => 'faker-0.4.0.zip'
);
ok $dist->process, 'Process the distribution' or note $dist->localized_error;

# Check the files.
my %files = map { join('/', @{ $_ }) => File::Spec->catfile($root, @{ $_ } ) } (
   ['dist',      'postgresql_faker.json'],
   ['extension', 'faker.json'],
   ['dist',      'postgresql_faker', '0.4.0', 'META.json'],
   ['dist',      'postgresql_faker', '0.4.0', 'postgresql_faker-0.4.0.zip'],
);

file_exists_ok $files{$_}, "File $_ should now exist" for keys %files;

# Now unzip it and have a look at its contents.
Archive::Zip::setErrorHandler(sub { diag @_ });
my $dist_zip = File::Spec->catfile(
    $root, qw(dist postgresql_faker 0.4.0 postgresql_faker-0.4.0.zip)
);
my $zip = Archive::Zip->new;
is $zip->read($dist_zip), AZ_OK, 'Unzip the generated zip file';

is_deeply [ sort map { $_->fileName } $zip->members ],
    [map { "postgresql_faker-0.4.0/$_" } qw(META.json Makefile faker--0.4.0.sql faker.control)],
    'It should contain the expected files';
