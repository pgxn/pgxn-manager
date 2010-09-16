#!/usr/bin/env perl

use 5.12.0;
use utf8;
use Test::More tests => 14;
#use Test::More 'no_plan';
use Archive::Zip qw(:ERROR_CODES);
use HTTP::Headers;
use Plack::Request::Upload;
use Test::File;
use File::Path qw(remove_tree);
use Archive::Tar;

my $CLASS;

BEGIN {
    $CLASS = 'PGXN::Manager::Distribution';
    use_ok $CLASS or die;
}

can_ok $CLASS, qw(process extract read_meta register index);

my $distdir = File::Spec->catdir(qw(t dist widget));
my $distzip = File::Spec->catdir(qw(t dist widget-0.2.5.pgz));
my $disttgz = File::Spec->catdir(qw(t dist widget-0.2.5.tar.gz));
my $tmpdir  = File::Spec->catdir(File::Spec->tmpdir, 'pgxn');

# First, create a distribution.
my $zip = Archive::Zip->new;
$zip->addTree($distdir, 'widget-0.2.5') == AZ_OK or die 'tree error';
$zip->writeToFileNamed($distzip) == AZ_OK or die 'write error';

END {
    unlink $distzip, $disttgz;
    remove_tree $tmpdir;
}

isa_ok my $dist = $CLASS->new(
    owner  => 'user',
    upload => Plack::Request::Upload->new(
        tempname => $distzip,
        filename => 'widget-0.2.5.pgz',
        size     => 0,
        headers  => HTTP::Headers->new(
            'Content-Type'        => 'application/zip',
            'Content-Disposition' => 'attachment; filename=widget-0.2.5.pgz',
        )
    )
), $CLASS, 'New object';

# Test extract().
is $dist->zip, undef, 'Should have no zip attribute';
ok $dist->extract, 'Extract the distribution';
isa_ok my $zip = $dist->zip, 'Archive::Zip', 'Zip attribute';
is_deeply [sort $zip->memberNames ],
    ['widget-0.2.5/', map { "widget-0.2.5/$_"} qw(META.json Makefile widget.sql.in)],
    'It should have the expected files';

# Now try a tarball.
my $tgz = Archive::Tar->new;
opendir my $dir, $distdir or die "Cannot open directory $distdir: $!\n";
while (readdir $dir) {
    next if /^[.]{1,2}$/;
    my $file = Archive::Tar::File->new(file => File::Spec->catfile($distdir, $_));
    $file->prefix('widget');
    $tgz->add_files($file);
}
closedir $dir or die "Cannot close directory $distdir: $!\n";
$tgz->write($disttgz, COMPRESS_GZIP);

isa_ok $dist = $CLASS->new(
    owner  => 'user',
    upload => Plack::Request::Upload->new(
        tempname => $disttgz,
        filename => 'widget-0.2.5.tar.gz',
        size     => 0,
        headers  => HTTP::Headers->new(
            'Content-Type'        => 'application/zip',
            'Content-Disposition' => 'attachment; filename=widget-0.2.5.tar.gz',
        )
    )
), $CLASS, 'Tgz distribution';

my $extdir = File::Spec->catdir($tmpdir, 'widget');
file_not_exists_ok $extdir, 'Should not have extraction directory';
is $dist->zip, undef, 'Should have no zip attribute';
ok $dist->extract, 'Extract the distribution';
file_exists_ok $extdir, 'Should now have extraction directory';
isa_ok my $zip = $dist->zip, 'Archive::Zip', 'Should now have a zip attribute';
is_deeply [sort $zip->memberNames ],
    ['widget/', map { "widget/$_"} qw(META.json Makefile widget.sql.in)],
    'It should have the expected files';
