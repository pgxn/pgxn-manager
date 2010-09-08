#!/usr/bin/env perl

use 5.12.0;
use utf8;
use Test::More tests => 17;
#use Test::More 'no_plan';
use JSON::XS;

BEGIN {
    use_ok 'PGXN::Manager' or die;
}

can_ok 'PGXN::Manager', qw(config conn instance initialize);
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
isa_ok $dbh->{HandleError}, 'CODE', 'There should be an error handler';

is $dbh->selectrow_arrayref('SELECT 1')->[0], 1,
    'We should be able to execute a query';
