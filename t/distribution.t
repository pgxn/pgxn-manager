#!/usr/bin/env perl

use 5.12.0;
use utf8;
use Test::More tests => 49;
#use Test::More 'no_plan';
use Archive::Zip qw(:ERROR_CODES);
use HTTP::Headers;
use Plack::Request::Upload;
use Test::File;
use File::Path qw(remove_tree);
use Archive::Tar;
use File::Basename;
use File::Copy;
use JSON::XS;

my $CLASS;

BEGIN {
    $CLASS = 'PGXN::Manager::Distribution';
    use_ok $CLASS or die;
}

can_ok $CLASS, qw(process extract read_meta register index);

my $distdir    = File::Spec->catdir(qw(t dist widget));
my $distzip    = File::Spec->catdir(qw(t dist widget-0.2.5.pgz));
my $nometazip  = File::Spec->catdir(qw(t dist widget-0.2.5.pgz));
my $badmetazip = File::Spec->catdir(qw(t dist widget-0.2.5.pgz));
my $disttgz    = File::Spec->catdir(qw(t dist widget-0.2.5.tar.gz));
my $tmpdir     = File::Spec->catdir(File::Spec->tmpdir, 'pgxn');

# First, create a distribution.
my $dzip = Archive::Zip->new;
$dzip->addTree($distdir, 'widget-0.2.5') == AZ_OK or die 'tree error';
$dzip->writeToFileNamed($distzip) == AZ_OK or die 'write error';

END {
    unlink $distzip, $disttgz, $nometazip, $badmetazip;
    remove_tree $tmpdir;
}

isa_ok my $dist = new_dist($distzip), $CLASS, 'New object';

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

isa_ok $dist = new_dist($disttgz), $CLASS, 'Tgz distribution';
my $extdir = File::Spec->catdir($tmpdir, 'widget');
file_not_exists_ok $extdir, 'Should not have extraction directory';
is $dist->zip, undef, 'Should have no zip attribute';
ok $dist->extract, 'Extract the distribution';
file_exists_ok $extdir, 'Should now have extraction directory';
isa_ok my $zip = $dist->zip, 'Archive::Zip', 'Should now have a zip attribute';
is_deeply [sort $zip->memberNames ],
    ['widget/', map { "widget/$_"} qw(META.json Makefile widget.sql.in)],
    'It should have the expected files';

# Let's handle some exceptional situations. Start with an unkonwn archive.
isa_ok $dist = new_dist(__FILE__), $CLASS, 'Non-archive distribution';
ok $dist->extract, 'Try to extract it';
like $dist->error, qr/distribution[.]t doesn’t look like a distribution archive/,
    'Should invalid archive error';

# Try an invalid zip file.
my $badzip = __FILE__ . '.zip';
copy __FILE__, $badzip;
END { unlink $badzip }

isa_ok $dist = new_dist($badzip), $CLASS, 'Bad zip distribution';
ok $dist->extract, 'Try to extract it';
like $dist->error, qr/distribution[.]t[.]zip doesn’t look like a distribution archive/,
    'Should invalid archive error';

# Try an invalid tgz file.
my $badtgz = __FILE__ . '.tgz';
copy __FILE__, $badtgz;
END { unlink $badtgz }

isa_ok $dist = new_dist($badtgz), $CLASS, 'Bad tgz distribution';
ok $dist->extract, 'Try to extract it';
like $dist->error, qr/distribution[.]t[.]tgz doesn’t look like a distribution archive/,
    'Should invalid archive error';

# Okay, go back to the zip file and process its META.json.
ok $dist = new_dist($distzip), 'Create a distribution with a zip archive again';
ok $dist->extract, 'Extract it';
ok !$dist->error, 'Should be successful';
ok $dist->read_meta, 'Read its meta data';
is $dist->prefix, 'widget-0.2.5', 'It should have the prefix';
ok $dist->distmeta, 'Should have its distmeta';
my $distmeta = decode_json do {
    my $mf = File::Spec->catfile($distdir, 'META.json');
    open my $fh, '<', $mf or die "Cannot open $mf: $!\n";
    local $/;
    <$fh>;
};
is_deeply $dist->distmeta, $distmeta, 'It should have the metadata';

# Now do the tarball.
ok $dist = new_dist($disttgz), 'Create a distribution with a tgz archive again';
ok $dist->extract, 'Extract it';
ok !$dist->error, 'Should be successful';
ok $dist->read_meta, 'Read its meta data';
is $dist->prefix, 'widget', 'It should have the prefix';
ok $dist->distmeta, 'Should have its distmeta';
is_deeply $dist->distmeta, $distmeta, 'It should have the metadata';

# Now try an archive with no META.json in it.
$dzip->removeMember('widget-0.2.5/META.json');
$dzip->writeToFileNamed($nometazip) == AZ_OK or die 'write error';
ok $dist = new_dist($nometazip), 'Create a distribution with meta-less zip';
ok $dist->extract, 'Extract it';
ok !$dist->read_meta, 'Try to read its meta data';
is $dist->error, 'Cannot find a META.json in widget-0.2.5.pgz',
    'The error message should be set';
is $dist->prefix, undef, 'The prefix should not be set';
is $dist->distmeta, undef, 'Should have no distmeta';

# Now try an archive with a broken META.json.
$dzip->addString('{ "name": "hi", "rank": 1, }', 'widget-0.2.5/META.json');
$dzip->writeToFileNamed($badmetazip) == AZ_OK or die 'write error';
ok $dist = new_dist($badmetazip), 'Create a distribution with bad meta zip';
ok $dist->extract, 'Extract it';
ok !$dist->read_meta, 'Try to read its meta data';
is $dist->error, q[Cannot parse JSON from widget-0.2.5/META.json: '"' expected, at character offset 27 (before "}")],
    'The error message should be set';
is $dist->prefix, 'widget-0.2.5', 'The prefix should be set';
is $dist->distmeta, undef, 'But we should have no distmeta';



sub new_dist {
    my $fn = shift;
    my $bn = basename $fn;
    $CLASS->new(
        owner  => 'user',
        upload => Plack::Request::Upload->new(
            tempname => $fn,
            filename => $bn,
            size     => 0,
            headers  => HTTP::Headers->new(
                'Content-Type'        => 'application/zip',
                'Content-Disposition' => "attachment; filename=$bn",
            )
        )
    );
}
