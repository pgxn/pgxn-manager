#!/usr/bin/env perl

use 5.12.0;
use utf8;
use Test::More tests => 33;
#use Test::More 'no_plan';
use JSON::XS;
use Test::File;
use Test::File::Contents;
use Test::MockModule;
use File::Path 'remove_tree';

BEGIN {
    use_ok 'PGXN::Manager' or die;
}

can_ok 'PGXN::Manager', qw(config conn instance initialize uri_templates);
isa_ok my $pgxn = PGXN::Manager->instance, 'PGXN::Manager';
is +PGXN::Manager->instance, $pgxn, 'instance() should return a singleton';
is +PGXN::Manager->instance, $pgxn, 'new() should return a singleton';

open my $fh, '<', 'conf/test.json' or die "Cannot open conf/test.json: $!\n";
my $conf = do {
    local $/;
    decode_json <$fh>;
};
close $fh;
is_deeply $pgxn->config, $conf, 'The configuration should be loaded';

ok my $conn = $pgxn->conn, 'Get connection';
isa_ok $conn, 'DBIx::Connector';
ok my $dbh = $conn->dbh, 'Make sure we can connect';
isa_ok $dbh, 'DBI::db', 'The handle';

# What are we connected to, and how?
is $dbh->{Username}, 'pgxn', 'Should be connected as "postgres"';
is $dbh->{Name}, 'dbname=pgxn_manager_test',
    'Should be connected to "pgxn_manager_test"';
ok !$dbh->{PrintError}, 'PrintError should be disabled';
ok !$dbh->{RaiseError}, 'RaiseError should be disabled';
ok $dbh->{AutoCommit}, 'AutoCommit should be enabled';
ok !$dbh->{pg_server_prepare}, 'pg_server_prepare should be disabled';
isa_ok $dbh->{HandleError}, 'CODE', 'There should be an error handler';

is $dbh->selectrow_arrayref('SELECT 1')->[0], 1,
    'We should be able to execute a query';

# Make sure we can initialize the mirror root.
my $index = File::Spec->catfile($pgxn->config->{mirror_root}, 'index.json');
END { remove_tree $pgxn->config->{mirror_root} }
file_not_exists_ok $index, "$index should not exist";
ok $pgxn->init_root, 'Initialize the mirror root';
file_exists_ok $index, "$index should now exist";

# Make sure that it contains what it ought to.
file_contents_is $index, JSON::XS->new->indent->space_after->canonical->encode(
    $pgxn->config->{uri_templates}
), '...And it should have the mirror templates specified in it';

# Make sure it doesn't get overwritten by subsequent calls to init_root().
my $mock_json = Test::MockModule->new('JSON::XS');
$mock_json->mock(new => sub { fail 'JSON::XS->new should not be called!' });
ok $pgxn->init_root, 'Init the root again';
file_exists_ok $index, "$index should still exist";

# Make sure the URI templates are created.
ok my $tmpl = $pgxn->uri_templates, 'Get URI templates';
isa_ok $tmpl, 'HASH', 'Their storage';
isa_ok $tmpl->{$_}, 'URI::Template', "Template $_" for keys %{ $tmpl };
