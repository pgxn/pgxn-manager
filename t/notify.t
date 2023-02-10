#!/usr/bin/env perl -w

use 5.10.0;
use strict;
use warnings;
use utf8;
use Encode qw(encode_utf8);
use JSON::XS;

use Test::More tests => 22;
# use Test::More 'no_plan';

use PGXN::Manager::Consumer;

# Do not use TxnTest; we need transactions to commit in order to receive
# notifications. Instead clean the database out when we're done.
my $pgxn = PGXN::Manager->instance;
END {
    my $cfg = $pgxn->config->{dbi};
    my $dbh = DBI->connect($cfg->{dsn}, undef, undef, {
        PrintError => 0,
        RaiseError => 1,
    });
    $dbh->do($_) for (
        'SET client_min_messages TO warning',
        'TRUNCATE users CASCADE'
    );
}

# Create a test user (copied from TxnTest).
ok $pgxn->conn->run(sub {
        $_->do(
            'SELECT insert_user(?, ?, email := ?)',
            undef, 'tmpadmin', 'test-passW0rd', 'tmp@pgxn.org',
        );

        $_->do('SELECT _test_set_admin(?)', undef, 'tmpadmin');

        $_->do(
            'SELECT insert_user(?, ?, email := ?)',
            undef, 'admin', 'test-passW0rd', 'admin@pgxn.org',
        );

        $_->do('SELECT _test_set_admin(?)', undef, 'admin');
        $_->do(
            'SELECT set_user_status(?, ?, ?)',
            undef, 'tmpadmin', 'admin', 'active'
        );
        # Delete the temp admin.
        $_->do(
            'SELECT set_user_status(?, ?, ?)',
            undef, 'admin', 'tmpadmin', 'deleted'
        );
}), 'Create admin user';

# Listen for notices.
ok $pgxn->conn->run(sub {
    $_[0]->do("LISTEN pgxn_$_") for PGXN::Manager::Consumer::CHANNELS ;
    1;
}), 'Listen for all channels';

# Create a user.
$pgxn->conn->dbh->do(
    'SELECT insert_user(?, ?, email := ?, twitter := ?, full_name := ?, uri := ?, why := ?)',
    undef, 'chrissy', 'passW0rd', 'secretary@un.org', 'unsec',
    'Chrisjen Avasarala', 'https://expanse.fandom.com/wiki/Chrisjen_Avasarala_(TV)',
    'I want to save the galaxy 🪐',
);

# Should have no notification.
ok !$pgxn->conn->dbh->pg_notifies, 'Should have no notification';

# Approve the user.
$pgxn->conn->dbh->do(
    'SELECT set_user_status(?, ?, ?)',
    undef, 'admin', 'chrissy', 'active'
);

my $json = JSON::XS->new->utf8(0);
ok my $notice = $pgxn->conn->dbh->pg_notifies, 'Should have notice';
is $notice->[0], 'pgxn_new_user', 'Should be new_user event';
ok my $user = $json->decode($notice->[2]), 'Decode the message';
is_deeply $user, {
      nickname  => 'chrissy',
      full_name => 'Chrisjen Avasarala',
      email     => 'secretary@un.org',
      uri       => 'https://expanse.fandom.com/wiki/Chrisjen_Avasarala_(TV)',
      why       => 'I want to save the galaxy 🪐',
      social    => { twitter => 'unsec' },
}, 'Should have user data in the message payload';

ok !$pgxn->conn->dbh->pg_notifies, 'Should have no other notification';

my $meta = '{
    "name": "Pair",
    "version": "0.0.1",
    "license": "postgresql",
    "maintainer": "chrissy",
    "abstract": "Ordered pair 🤩",
    "description": "An ordered pair for PostgreSQL",
    "tags": ["foo", "bar", "baz"],
    "prereqs": {
        "runtime": {
        "requires": {
            "PostgreSQL": "8.0.0",
            "PostGIS": "1.5.0"
        },
        "recommends": {
            "PostgreSQL": "8.4.0"
        }
        }
    },
    "provides": {
        "pair": { "file": "pair.sql.in", "version": "0.2.2" },
        "Trip": { "file": "trip.sql.in", "version": "0.2.1", "abstract": "A triplet" }
    },
    "meta-spec": {
        "version": "1.0.0",
        "url": "https://pgxn.org/meta/spec.txt"
    },
    "release_status": "testing",
    "resources": {
        "homepage": "https://pgxn.org/dist/pair/"
    }
}';

# Create a distribution.
ok $pgxn->conn->dbh->do(
    'SELECT * FROM add_distribution(?, ?, ?)',
    undef, 'chrissy', 'pshaw', $meta,
), 'Create a distribution';


ok $notice = $pgxn->conn->dbh->pg_notifies, 'Should have another notice';
is $notice->[0], 'pgxn_release', 'Should be release event';
ok my $dist = $json->decode($notice->[2]), 'Decode the message';

# Should have added fields.
ok delete $dist->{date}, 'Should have date';
is delete $dist->{user}, 'chrissy', 'Should have username';
ok delete $dist->{sha1}, 'Should have sha 1';

# Should not have meta-spec.
my $submitted_meta = $json->decode($meta);
delete $submitted_meta->{'meta-spec'};
is_deeply $dist, $submitted_meta, 'Should have the distribution meta';

ok !$pgxn->conn->dbh->pg_notifies, 'Should again have no notification';

# Create a mirror.
my $mirror = {
    uri => 'http://mirror.example.org',
    frequency    => 'hourly',
    location     => 'NYC',
    bandwidth    => 'High',
    organization => 'Kineticode',
    timezone     => 'America/New_York',
    contact      => 'k@example.com',
    src          => 'http://master.pgxn.org',
    rsync        => 'rsync://xxx.example.com',
    notes        => 'Some notes 📝',
};

ok $pgxn->conn->dbh->do(q{SELECT insert_mirror(
    admin        := ?,
    uri          := ?,
    frequency    := ?,
    location     := ?,
    bandwidth    := ?,
    organization := ?,
    timezone     := ?,
    email        := ?,
    src          := ?,
    rsync        := ?,
    notes        := ?
)}, undef, (
    'admin',
    $mirror->{uri},
    $mirror->{frequency},
    $mirror->{location},
    $mirror->{bandwidth},
    $mirror->{organization},
    $mirror->{timezone},
    $mirror->{contact},
    $mirror->{src},
    $mirror->{rsync},
    $mirror->{notes},
)), 'Inser mirror';

ok $notice = $pgxn->conn->dbh->pg_notifies, 'Should have an new notice';
is $notice->[0], 'pgxn_new_mirror', 'Should be new_mirror event';
is_deeply $json->decode($notice->[2]), $mirror, 'Should have message content';

ok !$pgxn->conn->dbh->pg_notifies, 'Should again have no notification';
