#!/usr/bin/env perl

use 5.12.0;
use utf8;
use Test::More tests => 139;
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
use Test::MockModule;
use lib 't/lib';
use TxnTest;

my $CLASS;

BEGIN {
    $CLASS = 'PGXN::Manager::Distribution';
    use_ok $CLASS or die;
}

can_ok $CLASS, qw(
    process extract read_meta normalize update_meta zipit indexit DEMOLISH
);

my $distdir    = File::Spec->catdir(qw(t dist widget));
my $distzip    = File::Spec->catdir(qw(t dist widget-0.2.5.pgz));
my $disttgz    = File::Spec->catdir(qw(t dist widget-0.2.5.tar.gz));
my $nometazip  = File::Spec->catdir(qw(t dist nometa-0.2.5.pgz));
my $badmetazip = File::Spec->catdir(qw(t dist badmeta-0.2.5.pgz));
my $nonsemzip  = File::Spec->catdir(qw(t dist nonsem-0.2.5.pgz));
my $tmpdir     = File::Spec->catdir(File::Spec->tmpdir, 'pgxn');

# First, create a distribution.
my $dzip = Archive::Zip->new;
$dzip->addTree($distdir, 'widget-0.2.5') == AZ_OK or die 'tree error';
$dzip->writeToFileNamed($distzip) == AZ_OK or die 'write error';

END {
    unlink $distzip, $disttgz, $nometazip, $badmetazip, $nonsemzip;
    remove_tree $tmpdir;
}

isa_ok my $dist = new_dist($distzip), $CLASS, 'New object';

##############################################################################
# Test extract().
is $dist->zip, undef, 'Should have no zip attribute';
file_not_exists_ok $dist->workdir, 'Working directory should not exist';
ok $dist->extract, 'Extract the distribution';
file_exists_ok $dist->workdir, 'Working directory should now exist';
ok !$dist->modified, 'The zip should be unmodified';
isa_ok my $zip = $dist->zip, 'Archive::Zip', 'Zip attribute';
is_deeply [sort $zip->memberNames ],
    ['widget-0.2.5/', map { "widget-0.2.5/$_"} qw(META.json Makefile widget.sql.in)],
    'It should have the expected files';
ok $dist->DEMOLISH, 'Demolish';
file_not_exists_ok $dist->workdir, 'Working directory should be gone';

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
my $extdir = File::Spec->catdir($dist->workdir, 'widget');
file_not_exists_ok $extdir, 'Should not have extraction directory';
is $dist->zip, undef, 'Should have no zip attribute';
ok $dist->extract, 'Extract the distribution';
file_exists_ok $extdir, 'Should now have extraction directory';
ok $dist->modified, 'The zip should be modified';
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

##############################################################################
# Test read_meta().
ok $dist = new_dist($distzip), 'Create a distribution with a zip archive again';
ok $dist->extract, 'Extract it';
ok !$dist->error, 'Should be successful';
ok $dist->read_meta, 'Read its meta data';
ok $dist->metamemb, 'It should have the meta member';
is $dist->metamemb->fileName, 'widget-0.2.5/META.json',
    'It should be the right file';
ok !$dist->modified, 'The zip should be unmodified';
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
ok $dist->modified, 'The zip should be modified';
ok $dist->metamemb, 'It should have the meta member';
is $dist->metamemb->fileName, 'widget/META.json',
    'It should be the right file';
ok $dist->distmeta, 'Should have its distmeta';
is_deeply $dist->distmeta, $distmeta, 'It should have the metadata';

# Now try an archive with no META.json in it.
$dzip->removeMember('widget-0.2.5/META.json');
$dzip->writeToFileNamed($nometazip) == AZ_OK or die 'write error';
ok $dist = new_dist($nometazip), 'Create a distribution with meta-less zip';
ok $dist->extract, 'Extract it';
ok !$dist->read_meta, 'Try to read its meta data';
ok !$dist->modified, 'The zip should be unmodified';
is $dist->error, 'Cannot find a META.json in nometa-0.2.5.pgz',
    'The error message should be set';
is $dist->metamemb, undef, 'The meta member should not be set';
is $dist->distmeta, undef, 'Should have no distmeta';

# Now try an archive with a broken META.json.
$dzip->addString('{ "name": "hi", "rank": 1, }', 'widget-0.2.5/META.json');
$dzip->writeToFileNamed($badmetazip) == AZ_OK or die 'write error';
ok $dist = new_dist($badmetazip), 'Create a distribution with bad meta zip';
ok $dist->extract, 'Extract it';
ok !$dist->read_meta, 'Try to read its meta data';
ok !$dist->modified, 'The zip should be unmodified';
is $dist->error, q[Cannot parse JSON from widget-0.2.5/META.json: '"' expected, at character offset 27 (before "}")],
    'The error message should be set';
ok $dist->metamemb, 'It should have the meta member';
is $dist->metamemb->fileName, 'widget-0.2.5/META.json',
    'It should be the right file';
is $dist->distmeta, undef, 'But we should have no distmeta';

##############################################################################
# Test normalize().
my $mock = Test::MockModule->new($CLASS);
my $updated = 0;
my $updater = sub { $updated++ };
$mock->mock(update_meta => $updater);

ok $dist = new_dist($distzip), 'Create a distribution with a zip archive again';
ok $dist->extract, 'Extract it';
ok $dist->read_meta, 'Read its meta data';
ok $dist->normalize, 'Normalize it';
ok !$dist->error, 'Should be successful';
ok !$dist->modified, 'Should not be modified';
ok $dist->metamemb, 'It should have the meta member';
is $dist->metamemb->fileName, 'widget-0.2.5/META.json',
    'It should be the right file';
is_deeply $dist->distmeta, $distmeta, 'The distmeta should be unchanged';
is $updated, 0, 'And update_meta() should not have been called';

# Let's test update_meta() while we're here.
$mock->unmock('update_meta');
ok $dist->update_meta, 'Update the metadata';
$distmeta->{generated_by} = 'PGXN::Manager ' . PGXN::Manager->VERSION;
is_deeply decode_json $dist->metamemb->contents, $distmeta,
    'The distmeta should be complete';

# Mock update_meta again.
$mock->mock(update_meta => $updater);

# Try the tarball which has a bogus prefix.
ok $dist = new_dist($disttgz), 'Create a distribution with a tgz archive again';
ok $dist->extract, 'Extract it';
ok $dist->read_meta, 'Read its meta data';
ok $dist->normalize, 'Normalize it';
ok !$dist->error, 'Should be successful';
ok $dist->modified, 'Should be modified';
ok $dist->metamemb, 'It should have the meta member';
is $dist->metamemb->fileName, 'widget-0.2.5/META.json',
    'It should have its prefix properly updated';
$distmeta->{generated_by} = 'theory';
is_deeply $dist->distmeta, $distmeta, 'The distmeta should be unchanged';
is $updated, 0, 'And update_meta() should not have been called';
is_deeply [sort $dist->zip->memberNames ],
    ['widget-0.2.5/', map { "widget-0.2.5/$_"} qw(META.json Makefile widget.sql.in)],
    'All of the files should have the new prefix';
is $updated, 0, 'update_meta() should not have been called';

# Try with metdata that's got some non-semantic versions.
$distmeta->{version} = '2.5';
$dzip->memberNamed('widget-0.2.5/META.json')->contents(encode_json $distmeta);
$dzip->writeToFileNamed($nonsemzip) == AZ_OK or die 'write error';

ok $dist = new_dist($nonsemzip), 'Create dist with non-smantic version';
ok $dist->extract, 'Extract it';
ok $dist->read_meta, 'Read its meta data';
ok $dist->normalize, 'Normalize it';
ok !$dist->error, 'Should be successful';
ok $dist->modified, 'Should be modified';
ok $dist->metamemb, 'It should have the meta member';
$distmeta->{version} = '2.5.0';
is_deeply $dist->distmeta, $distmeta,
    'The distmeta should have the normalized version';
is $updated, 1, 'And update_meta() should have been called';
is_deeply [sort $dist->zip->memberNames ],
    ['widget-2.5.0/', map { "widget-2.5.0/$_"} qw(META.json Makefile widget.sql.in)],
    'All of the files should have normalized version in their prefix';

# Make sure that the "prereq" versions are normalized.
$updated = 0;
$distmeta->{prereqs}{runtime}{requires}{PostgreSQL} = '8.0';
$dzip->memberNamed('widget-0.2.5/META.json')->contents(encode_json $distmeta);
$dzip->writeToFileNamed($nonsemzip) == AZ_OK or die 'write error';

ok $dist = new_dist($nonsemzip), 'Create dist with non-smantic "prereq" version';
ok $dist->extract, 'Extract it';
ok $dist->read_meta, 'Read its meta data';
ok $dist->normalize, 'Normalize it';
ok !$dist->error, 'Should be successful';
ok $dist->modified, 'Should be modified';
ok $dist->metamemb, 'It should have the meta member';
$distmeta->{prereqs}{runtime}{requires}{PostgreSQL} = '8.0.0';
is_deeply $dist->distmeta, $distmeta,
    'The distmeta should have the normalized prereq version';
is $updated, 1, 'And update_meta() should have been called';

# Make sure that the "provides" versions are normalized.
$updated = 0;
$distmeta->{provides}{widget}{version} = '1.095';
$dzip->memberNamed('widget-0.2.5/META.json')->contents(encode_json $distmeta);
$dzip->writeToFileNamed($nonsemzip) == AZ_OK or die 'write error';

ok $dist = new_dist($nonsemzip), 'Create dist with non-smantic "provides" version';
ok $dist->extract, 'Extract it';
ok $dist->read_meta, 'Read its meta data';
ok $dist->normalize, 'Normalize it';
ok !$dist->error, 'Should be successful';
ok $dist->modified, 'Should be modified';
ok $dist->metamemb, 'It should have the meta member';
$distmeta->{provides}{widget}{version} = '1.95.0';
is_deeply $dist->distmeta, $distmeta,
    'The distmeta should have the normalized prvides version';
is $updated, 1, 'And update_meta() should have been called again';

##############################################################################
# Test zipit().
ok $dist = new_dist($distzip), 'Create a distribution with a zip archive again';
ok $dist->extract, 'Extract it';
ok $dist->read_meta, 'Read its meta data';
ok $dist->normalize, 'Normalize it';
ok $dist->zipit, 'Zip it';
ok !$dist->error, 'Should be successful';
ok !$dist->modified, 'Should not be modified';
is $dist->zipfile, $distzip, 'Should reference the original zip file';
is $dist->sha1, '39642746a8d91345f93fc3027765043c8e52bbde', 'The SHA1 should be set';

# Try the tgz file, which must be rewritten as a zip file.
ok $dist = new_dist($disttgz), 'Create a distribution with a tgz archive again';
ok $dist->extract, 'Extract it';
ok $dist->read_meta, 'Read its meta data';
ok $dist->normalize, 'Normalize it';
ok $dist->zipit, 'Zip it';
ok !$dist->error, 'Should be successful';
ok $dist->modified, 'Should be modified';
is $dist->zipfile, File::Spec->catfile($dist->workdir, 'dest', 'widget-0.2.5.zip'),
    'Zip file name should be new';
is $dist->sha1, do {
    open my $fh, '<', $dist->zipfile or die "Cannot open zipfile: $!\n";
    my $sha1 = Digest::SHA1->new;
    $sha1->addfile($fh);
    $sha1->hexdigest;
}, 'The SHA1 should be set';

END { $dist->zipfile }

# Make sure the zip file looks right.
my $nzip = Archive::Zip->new;
$nzip->read($dist->zipfile);
is_deeply [sort $nzip->memberNames ],
    ['widget-0.2.5/', map { "widget-0.2.5/$_"} qw(META.json Makefile widget.sql.in)],
    'It should have the expected files';

##############################################################################
# Test indexit().
my $user = TxnTest->user; # Create user.
ok $dist = new_dist($distzip), 'Create a distribution with a zip archive again';
ok $dist->extract, 'Extract it';
ok $dist->read_meta, 'Read its meta data';
ok $dist->normalize, 'Normalize it';
ok $dist->zipit, 'Zip it';
ok $dist->indexit, 'Index it';


##############################################################################
# Utility for constructing a distribution.
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
