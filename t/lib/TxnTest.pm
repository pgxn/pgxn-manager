package TxnTest;

use PGXN::Manager;
use Test::MockModule;

my ($dbi_mock, $begin, $commit, $rollback);
BEGIN {
    my $dbh = PGXN::Manager->conn->dbh;
    $dbh->begin_work;
    $dbi_mock = Test::MockModule->new(ref $dbh, no_auto => 1 );

    $dbi_mock->mock(begin_work => sub { $begin++ });
    $dbi_mock->mock(commit     => sub { $commit++ });
    $dbi_mock->mock(rollback   => sub { $rollback++ });
}

END {
    $dbi_mock->unmock('rollback');
    PGXN::Manager->conn->dbh->rollback;
}

sub begins {
    my $ret = $begin;
    $begin = 0;
    return $ret;
}

sub commits {
    my $ret = $commit;
    $commit = 0;
    return $ret;
}

sub rollbacks {
    my $ret = $rollback;
    $rollback = 0;
    return $ret;
}

my $admin;
sub admin {
    PGXN::Manager->conn->run(sub {
        $_->do(
            'SELECT insert_user(?, ?, email := ?)',
            undef, 'tmpadmin', '****', 'tmp@pgxn.org',
        );

        $_->do('SELECT _test_set_admin(?)', undef, 'tmpadmin');

        $_->do(
            'SELECT insert_user(?, ?, email := ?)',
            undef, 'admin', '****', 'admin@pgxn.org',
        );

        $_->do('SELECT _test_set_admin(?)', undef, 'admin');
        $_->do(
            'SELECT set_user_status(?, ?, ?)',
            undef, 'tmpadmin', 'admin', 'active'
        );
    }) unless $admin;
    return $admin = 'admin';
}

my $user;
sub user {
    PGXN::Manager->conn->run(sub {
        admin();
        $_->do(
            'SELECT insert_user(?, ?, email := ?)',
            undef, 'user', '****', 'user@pgxn.org',
        );

        $_->do(
            'SELECT set_user_status(?, ?, ?)',
            undef, 'admin', 'user', 'active'
        );
    }) unless $user;
    return $user = 'user';
}


1;
