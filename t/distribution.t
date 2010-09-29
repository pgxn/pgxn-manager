#!/usr/bin/env perl

use 5.12.0;
use utf8;
use Test::More tests => 197;
#use Test::More 'no_plan';
use Archive::Zip qw(:ERROR_CODES);
use HTTP::Headers;
use Test::File;
use Test::File::Contents;
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
    $ENV{HTTP_ACCEPT_LANGUAGE} = 'en';
}

can_ok $CLASS, qw(
    process extract read_meta normalize _update_meta zipit indexit DEMOLISH
);

my $distdir    = File::Spec->catdir(qw(t dist widget));
my $distzip    = File::Spec->catdir(qw(t dist widget-0.2.5.pgz));
my $disttgz    = File::Spec->catdir(qw(t dist widget-0.2.5.tar.gz));
my $nometazip  = File::Spec->catdir(qw(t dist nometa-0.2.5.pgz));
my $badmetazip = File::Spec->catdir(qw(t dist badmeta-0.2.5.pgz));
my $nonsemzip  = File::Spec->catdir(qw(t dist nonsem-0.2.5.pgz));
my $noreadzip  = File::Spec->catdir(qw(t dist badmeta-0.2.5.pgz));
my $tmpdir     = File::Spec->catdir(File::Spec->tmpdir, 'pgxn');
my $root = PGXN::Manager->new->config->{mirror_root};

# First, create a distribution.
my $dzip = Archive::Zip->new;
$dzip->addTree($distdir, 'widget-0.2.5') == AZ_OK or die 'tree error';
$dzip->writeToFileNamed($distzip) == AZ_OK or die 'write error';
my $distzip_sha1 = _sha1_for($distzip);

END {
    unlink $distzip, $disttgz, $nometazip, $badmetazip, $nonsemzip, $noreadzip;
    remove_tree $tmpdir, $root;
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
is_deeply [sort $zip->memberNames ], [
    'widget-0.2.5/',
    map { "widget-0.2.5/$_"} qw(META.json Makefile README widget.sql.in)
], 'It should have the expected files';
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
my $extdir = File::Spec->catdir($dist->workdir, 'source', 'widget');
file_not_exists_ok $extdir, 'Should not have extraction directory';
is $dist->zip, undef, 'Should have no zip attribute';
ok $dist->extract, 'Extract the distribution';
file_exists_ok $extdir, 'Should now have extraction directory';
ok $dist->modified, 'The zip should be modified';
isa_ok my $zip = $dist->zip, 'Archive::Zip', 'Should now have a zip attribute';
is_deeply [sort $zip->memberNames ], [
    'widget/',
    map { "widget/$_"} qw(META.json Makefile README widget.sql.in)
], 'It should have the expected files';

# Let's handle some exceptional situations. Start with an unkonwn archive.
isa_ok $dist = new_dist(__FILE__), $CLASS, 'Non-archive distribution';
ok $dist->extract, 'Try to extract it';
is_deeply scalar $dist->error, [
    "\x{201c}[_1]\x{201d} doesn\x{2019}t look like a distribution archive",
    "distribution.t"
], 'Should invalid archive error';
is $dist->localized_error,
    "\x{201c}distribution.t\x{201d} doesn\x{2019}t look like a distribution archive",
    'And it should localize properly';

# Try an invalid zip file.
my $badzip = __FILE__ . '.zip';
copy __FILE__, $badzip;
END { unlink $badzip }

isa_ok $dist = new_dist($badzip), $CLASS, 'Bad zip distribution';
ok $dist->extract, 'Try to extract it';
is_deeply scalar $dist->error, [
    "\x{201c}[_1]\x{201d} doesn\x{2019}t look like a distribution archive",
    "distribution.t.zip"
], 'Should invalid archive error';

# Try an invalid tgz file.
my $badtgz = __FILE__ . '.tgz';
copy __FILE__, $badtgz;
END { unlink $badtgz }

isa_ok $dist = new_dist($badtgz), $CLASS, 'Bad tgz distribution';
ok $dist->extract, 'Try to extract it';
is_deeply scalar $dist->error, [
    "\x{201c}[_1]\x{201d} doesn\x{2019}t look like a distribution archive",
    "distribution.t.tgz",
], 'Should invalid archive error';

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
is $dist->metamemb, undef, 'The meta member should not be set';
is $dist->distmeta, undef, 'Should have no distmeta';
is_deeply scalar $dist->error, [
    'Cannot find a “[_1]” in “[_2]”',
    'META.json', 'nometa-0.2.5.pgz',
], 'The error message should be set';
is $dist->localized_error,
    'Cannot find a “META.json” in “nometa-0.2.5.pgz”',
    'And it should localize properly';

# Now try an archive with a broken META.json.
$dzip->addString('{ "name": "hi", "rank": 1, }', 'widget-0.2.5/META.json');
$dzip->writeToFileNamed($badmetazip) == AZ_OK or die 'write error';
ok $dist = new_dist($badmetazip), 'Create a distribution with bad meta zip';
ok $dist->extract, 'Extract it';
ok !$dist->read_meta, 'Try to read its meta data';
ok !$dist->modified, 'The zip should be unmodified';
is_deeply scalar $dist->error, [
    'Cannot parse JSON from “[_1]”: [_2]',
    'widget-0.2.5/META.json',
    q['"' expected, at character offset 27 (before "}")],
], 'The error message should be set';
is $dist->localized_error,
    q[Cannot parse JSON from “widget-0.2.5/META.json”: '"' expected, at character offset 27 (before "}")],
    'And it should localize properly';
ok $dist->metamemb, 'It should have the meta member';
is $dist->metamemb->fileName, 'widget-0.2.5/META.json',
    'It should be the right file';
is $dist->distmeta, undef, 'But we should have no distmeta';

##############################################################################
# Test normalize().
my $mock = Test::MockModule->new($CLASS);
my $updated = 0;
my $updater = sub { $updated++ };
$mock->mock(_update_meta => $updater);

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
is $updated, 0, 'And _update_meta() should not have been called';

# Let's test _update_meta() while we're here.
$mock->unmock('_update_meta');
ok $dist->_update_meta, 'Update the metadata';
$distmeta->{generated_by} = 'PGXN::Manager ' . PGXN::Manager->VERSION;
is_deeply decode_json $dist->metamemb->contents, $distmeta,
    'The distmeta should be complete';

# Mock _update_meta again.
$mock->mock(_update_meta => $updater);

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
is $updated, 0, 'And _update_meta() should not have been called';
is_deeply [sort $dist->zip->memberNames ], [
    'widget-0.2.5/',
    map { "widget-0.2.5/$_"} qw(META.json Makefile README widget.sql.in)
], 'All of the files should have the new prefix';
is $updated, 0, '_update_meta() should not have been called';

# Try an archive with keys missing from the META.json.
$dzip->memberNamed('widget-0.2.5/META.json')->contents(encode_json {
    name => 'whatever',
    version => '1.2.2',
});
$dzip->writeToFileNamed($badmetazip) == AZ_OK or die 'write error';
ok $dist = new_dist($badmetazip), 'Create dist with missing meta keys';
ok $dist->extract, 'Extract it';
ok $dist->read_meta, 'Read its meta data';
ok !$dist->normalize, 'Should get false from normalize()';
is_deeply scalar $dist->error, [
    '“[_1]” is missing the required [numerate,_2,key] [qlist,_3]',
    'widget-0.2.5/META.json', 3, [qw(license maintainer abstract)],
], 'Sould get missing keys error';
is $dist->localized_error,
    '“widget-0.2.5/META.json” is missing the required keys “license”, “maintainer”, and “abstract”',

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
is $updated, 1, 'And _update_meta() should have been called';
is_deeply [sort $dist->zip->memberNames ], [
    'widget-2.5.0/',
    map { "widget-2.5.0/$_"} qw(META.json Makefile README widget.sql.in)
], 'All of the files should have normalized version in their prefix';

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
is $updated, 1, 'And _update_meta() should have been called';

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
is $updated, 1, 'And _update_meta() should have been called again';

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
is $dist->sha1, $distzip_sha1, 'The SHA1 should be set';

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
is $dist->sha1, _sha1_for($dist->zipfile), 'The SHA1 should be set';

END { $dist->zipfile }

# Make sure the zip file looks right.
my $nzip = Archive::Zip->new;
$nzip->read($dist->zipfile);
is_deeply [sort $nzip->memberNames ], [
    'widget-0.2.5/',
    map { "widget-0.2.5/$_"} qw(META.json Makefile README widget.sql.in)
], 'It should have the expected files';

##############################################################################
# Test indexit().
my $user = TxnTest->user; # Create user.
my %files = map { join('/', @{ $_ }) => File::Spec->catfile($root, @{ $_ } ) } (
   ['by',   'owner',     'user.json'],
   ['by',   'dist',      'widget.json'],
   ['by',   'tag',       'gadget.json'],
   ['by',   'tag',       'widget.json'],
   ['by',   'extension', 'widget.json'],
   ['dist', 'widget',    'widget-0.2.5.json'],
   ['dist', 'widget',    'widget-0.2.5.readme'],
   ['dist', 'widget',    'widget-0.2.5.pgz'],
   ['by',   'tag',       'full text search.json'],
);

file_exists_ok $distzip, 'We should have the distzip file';
file_not_exists_ok $files{$_}, "File $_ should not yet exist" for keys %files;
ok $dist = new_dist($distzip), 'Create a distribution with a zip archive again';
ok $dist->extract, 'Extract it';
ok $dist->read_meta, 'Read its meta data';
ok $dist->normalize, 'Normalize it';
ok $dist->zipit, 'Zip it';
ok $dist->indexit, 'Index it';
file_not_exists_ok $distzip, 'The distzip file should be gone';
file_exists_ok $files{$_}, "File $_ should now exist" for keys %files;

# Check the content of those files.
PGXN::Manager->conn->run(sub {
    my $dbh = shift;

    # Check distribution JSON.
    my ($json) = $dbh->selectrow_array(
        'SELECT meta FROM distributions WHERE name = ? AND version = ?',
        undef, 'widget', '0.2.5',
    );
    file_contents_is $files{'dist/widget/widget-0.2.5.json'}, $json,
        "Distribution JSON file should be correct";

    # Check by-extension JSON.
    my ($json) = $dbh->selectrow_array(
        'SELECT json FROM by_extension_json(?, ?)',
        undef, 'widget', '0.2.5',
    );
    file_contents_is $files{'by/extension/widget.json'}, $json,
        "By extension JSON file should be correct";

    # Check owner JSON.
    ($json) = $dbh->selectrow_array(
        'SELECT by_owner_json(?)', undef, $user,
    );
    file_contents_is $files{'by/owner/user.json'}, $json,
        "By owner JSON file should be correct";

    # Check dist JSON.
    ($json) = $dbh->selectrow_array(
        'SELECT by_dist_json(?)', undef, 'widget',
    );
    file_contents_is $files{'by/dist/widget.json'}, $json,
        "By dist JSON file should be correct";

    # Check tag JSON.
    my $tags = $dbh->selectall_arrayref(
        'SELECT tag, json FROM by_tag_json(?, ?)',
        undef, 'widget', '0.2.5'
    );
    for my $row (@$tags) {
        file_contents_is $files{"by/tag/$row->[0].json"}, $row->[1],
            qq{By tag "$row->[0]" JSON should be correct}
    }
});

# Check the distribution itself.
is _sha1_for($files{'dist/widget/widget-0.2.5.pgz'}), $distzip_sha1,
    'The distribution archive should be as expected';

file_contents_is $files{'dist/widget/widget-0.2.5.readme'},
    "This is the widget 0.2.5 README.\n",
    'The README contents should be correct';

# Let's try a distribution without a README.
%files = map { join('/', @{ $_ }) => File::Spec->catfile($root, @{ $_ } ) } (
   ['by',   'owner',     'user.json'],
   ['by',   'dist',      'widget.json'],
   ['by',   'tag',       'gadget.json'],
   ['by',   'tag',       'widget.json'],
   ['by',   'extension', 'widget.json'],
   ['dist', 'widget',    'widget-2.5.0.json'],
   ['dist', 'widget',    'widget-2.5.0.pgz'],
   ['by',   'tag',       'full text search.json'],
);
$dzip->removeMember('widget-0.2.5/README');
$dzip->writeToFileNamed($noreadzip) == AZ_OK or die 'write error';

ok $dist = new_dist($noreadzip), 'Create a distribution with README-less zip';
ok $dist->process, 'Process the distribution';
file_exists_ok $files{$_}, "File $_ should now exist" for keys %files;
file_not_exists_ok +File::Spec->catfile('dist', 'widget', 'widget-2.5.0.readme'),
    'There should be no README on the mirror';

##############################################################################
# Now test with an exception thrown by the database.
ok $dist = new_dist($noreadzip, 'nobody'), 'Create a distribution object with invalid owner';
ok !$dist->process, 'process() should return false';
is_deeply scalar $dist->error, [
    'User “[_1]” does not own all provided extensions',
    'nobody'
], 'The error message should be correct';
is $dist->localized_error,
    'User “nobody” does not own all provided extensions',
    'And it should localize properly';

##############################################################################
# Test distribution constraint exception.
TxnTest->restart;
$user = TxnTest->user;
move +File::Spec->catfile($root, qw(dist widget widget-0.2.5.pgz)), $distzip;
ok $dist = new_dist($distzip), 'Create dist with a zip archive yet again';
ok $dist->process, 'First creation of distribution should succeed';

move +File::Spec->catfile($root, qw(dist widget widget-0.2.5.pgz)), $distzip;
ok $dist = new_dist($distzip), 'Create dist with a zip archive yet again';
ok !$dist->process, 'Second creation of distribution should fail';
is_deeply [$dist->error], ['Distribution “[_1]” already exists', 'widget 0.2.5'],
    'Should get the expected localizeable exception';

##############################################################################
# Utility for constructing a distribution.
sub new_dist {
    my $fn = shift;
    my $bn = basename $fn;
    $CLASS->new(
        owner    => shift || 'user',
        archive  => $fn,
        basename => $bn,
    );
}

sub _sha1_for {
    my $fn = shift;
    open my $fh, '<', $fn or die "Cannot open $fn: $!\n";
    my $sha1 = Digest::SHA1->new;
    $sha1->addfile($fh);
    return $sha1->hexdigest;
}
