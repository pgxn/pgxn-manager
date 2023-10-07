#!/usr/bin/env perl -w

use 5.10.0;
use strict;
use warnings;
use utf8;
use Encode qw(encode_utf8);
use JSON::XS;
use File::Temp ();

use Test::More tests => 113;
# use Test::More 'no_plan';
use Test::Output;
use Test::MockModule;
use Test::Exception;
use Test::File;
use Test::File::Contents;

##############################################################################
# Mock time.
my (@gmtime, $time);
BEGIN {
    $time = CORE::time();
    @gmtime = CORE::gmtime($time);
    *CORE::GLOBAL::time = sub() { return $time };
    *CORE::GLOBAL::gmtime = sub (;$) { return @gmtime }
}

##############################################################################
# Load the class.
my $CLASS;

BEGIN {
    $CLASS = 'PGXN::Manager::Consumer';
    use_ok $CLASS or die;
}

can_ok $CLASS => qw(
    new
    go
    run
    verbose
    interval
    continue
    load_consumers
    consume
    _config
);

##############################################################################
# Instantiate and test config.
DEFAULTS: {
    local @ARGV;
    is_deeply $CLASS->_config, { verbose => 0, interval => 5 },
        'Default options should be correct';

    local $ENV{PLACK_ENV} = 'test';
    my $consumer = new_ok $CLASS;
    is $consumer->verbose, 0, 'Default verbosity is 0';
    is $consumer->interval, 5, 'Default interval is 5';
    is $consumer->continue, 1, 'Default continue is 1';
    is $consumer->pid_file, undef, 'Default pid file is undef';
    ok $consumer->log_fh, 'Should have log file handle';
}

# Grab the timestamp that will appear in logs.
my $logtime = POSIX::strftime '%Y-%m-%dT%H:%M:%SZ', gmtime $time;
is time, $time, 'Should have mocked time';
is POSIX::strftime('%Y-%m-%dT%H:%M:%SZ', gmtime), $logtime,
    'Should have mocked gmtime';

##############################################################################
# Test and then mock log
STDOUT: {
    my $consumer = $CLASS->new();
    stdout_is { ok $consumer->log("Hello there 😀"), 'log' }
        encode_utf8 "$logtime - Hello there 😀\n",
        "log should encode text";
}

LOGFILE: {
    my $tmp = File::Temp->new;
    my $consumer = $CLASS->new(log_fh => PGXN::Manager::Consumer::_log_fh($tmp->filename));
    ok $consumer->log("Hello there 😀"), 'log to file';
    file_contents_eq $tmp->filename, "$logtime - Hello there 😀\n",
        { encoding => 'UTF-8' },
        'Should have written message to log file';
}

# Mock log file.
my $log_output = '';
my $log_fh = IO::File->new(\$log_output, 'w');
$log_fh->binmode(':utf8');
sub output {
    my $ret = $log_output;
    $log_fh->seek(0, 0);
    $log_output = '';
    return $ret // '';
}
my $chans = join(', ', PGXN::Manager::Consumer::CHANNELS);

##############################################################################
# Test pid file cleanup.
PID: {
    my $tmp = File::Temp->new(UNLINK => 0);
    my $fn = $tmp->filename;
    do {
        my $consumer = $CLASS->new(log_fh => $log_fh, pid_file => $fn);
        file_exists_ok $fn, 'PID file should exist';
    };
    file_not_exists_ok $fn, 'PID file be gone';
    is output(), '', 'Should have no output';
}

##############################################################################
# Load the test environment configuration.
sub load_config {
    open my $fh, '<:raw', 'conf/test.json' or die "Cannot open conf/test.json: $!\n";
    local $/;
    return decode_json <$fh>;
}

##############################################################################
# Test _config.
CONFIG: {
    local @ARGV = qw(
        --env dev
        --daemonize
        --pid pid.txt
        --interval 2.2
        --verbose
        --log-file log.txt
    );
    my $opts = $CLASS->_config;
    is_deeply $opts, {
        daemonize  => 1,
        'pid-file' => 'pid.txt',
        interval   => 2.2,
        verbose    => 1,
        'log-file' => 'log.txt',
    }, 'Should have long option config';
    is delete $ENV{PLACK_ENV}, 'dev', 'Should have set env to "dev"';

    @ARGV = qw(
        -E foo
        -D
        -i 4
        -V -V -V
    );
    $opts = $CLASS->_config;
    is_deeply $opts, {
        daemonize => 1,
        interval  => 4,
        verbose   => 3,
    }, 'Should have short option config';
    is delete $ENV{PLACK_ENV}, 'foo', 'Should have set env to "foo"';
}

##############################################################################
# Test load_consumers.
LOAD: {
    my $conf = load_config;
    my $consumer = $CLASS->new(log_fh => $log_fh);
    my $handlers = $consumer->load_consumers($conf->{consumers});
    is_deeply [keys %{ $handlers }], ["release"], 'Should have one key';
    is @{ $handlers->{release} }, 2, 'Should have two release handlers';
    my ($masto, $twtr) = @{ $handlers->{release} };
    isa_ok $masto, 'PGXN::Manager::Consumer::mastodon', 'First handler';
    isa_ok $twtr, 'PGXN::Manager::Consumer::twitter', 'Second handler';
    is $masto->server, $conf->{consumers}[0]{"server"},
        'Mastodon handler should have server configured';
    ok defined $twtr->client, 'Twitter client should be present';

    # Test no type.
    throws_ok { $consumer->load_consumers([{}]) }
        qr/No type specified for event consumer/,
        'Should get error for missing type';

    # Test unknown consumer.
    throws_ok { $consumer->load_consumers([{ type => 'unknown' }]) }
        qr/Error loading ${CLASS}::unknown/,
        'Should get error for unknown type';

    # Try other types of events.
    $handlers = $consumer->load_consumers([
        {
            %{ $conf->{consumers}[0] },
            type => 'mastodon',
            events => [qw(release password_reset)],
        },
        {
            %{ $conf->{consumers}[1] },
            type => 'twitter',
            events => [qw(release)],
        },
    ]);
    is_deeply [sort keys %{ $handlers }], [qw(password_reset release)],
        'Should have two keys';
    is @{ $handlers->{release} }, 2, 'Should have two release handlers';
    is @{ $handlers->{password_reset} }, 1,
        'Should have one password_reset handler';
    isa_ok $handlers->{release}[0], 'PGXN::Manager::Consumer::mastodon',
        'First relase handler';
    isa_ok $handlers->{release}[1], 'PGXN::Manager::Consumer::twitter',
        'Second relase handler';
    is $handlers->{password_reset}[0], $handlers->{release}[0],
        'Should have same masto handler for password reset';
}

##############################################################################
# Test go.
DAEMONIZE: {
   # Mock Proc::Daemon
    my $mock_proc = Test::MockModule->new('Proc::Daemon');
    $mock_proc->mock(Init => 0);
    my %pd_params;
    $mock_proc->mock(new => sub {
        my $pkg = shift;
        %pd_params = @_;
        my $pd_new = $mock_proc->original('new');
        $pkg->$pd_new(@_);
    });

    my $mocker = Test::MockModule->new($CLASS);
    my $ran;
    $mocker->mock(run => sub { $ran = 1; 0 });
    local @ARGV = (qw(--env test --daemonize --pid-file foo));
    stdout_is { is $CLASS->go, 0, 'Should get zero from go' }
        "", 'Should have logged nothing';
    is_deeply \%pd_params, {
            work_dir      => Cwd::getcwd,
            dont_close_fh => [qw(STDERR STDOUT)],
            pid_file      => 'foo',
    }, 'Should have passed params to Proc::Daemon->new';

    ok $ran, 'Should have run';
    is output(), '', 'Should have no output';
    ok defined delete $SIG{TERM}, 'Should have set term signal';
    is delete $ENV{PLACK_ENV}, 'test', 'Should have set test env';

    # Now make a pid.
    my $tmp = File::Temp->new(UNLINK => 0);
    my $pid_file = $tmp->filename;
    file_exists_ok $pid_file, 'PID file should exist';
    $mock_proc->mock(Init => 42);
    $ran = 0;
    @ARGV = (qw(-D --pid-file), $pid_file);
    stdout_is { is $CLASS->go, 0, 'Should get zero from go' }
        "$logtime - INFO: Forked PID 42 written to $pid_file\n",
        'Should have emitted PID';
    ok !$ran, 'Should not have run';
    is $SIG{TERM}, undef, 'Should not have set term signal';
    is delete $ENV{PLACK_ENV}, 'development', 'Should have set development env';
     is_deeply \%pd_params, {
            work_dir      => Cwd::getcwd,
            dont_close_fh => [qw(STDERR STDOUT)],
            pid_file      => $pid_file,
    }, 'Should have passed params to Proc::Daemon->new';

    # Try with no PID file (shoud log it was written to STDOUT).
    $ran = 0;
    @ARGV = qw(-D);
    stdout_is { is $CLASS->go, 0, 'Should get zero from go' }
        "$logtime - INFO: Forked PID 42 written to STDOUT\n",
        'Should have emitted PID';
    ok !$ran, 'Should not have run';
    is $SIG{TERM}, undef, 'Should not have set term signal';
    is delete $ENV{PLACK_ENV}, 'development', 'Should have set development env';
     is_deeply \%pd_params, {
            work_dir      => Cwd::getcwd,
            dont_close_fh => [qw(STDERR STDOUT)],
            pid_file      => undef,
    }, 'Should have passed params to Proc::Daemon->new';

   $mocker->unmock('run');
}

GO: {
    # Test without daemonization.
    my $mocker = Test::MockModule->new($CLASS);
    my $ran;
    $mocker->mock(run => sub { $ran = 1; 0 });
    stdout_is { is $CLASS->go, 0, 'Should get zero from go' } '',
        'Should have logged nothing';
    ok $ran, 'Should have run';
    is_deeply output(), '', 'Should have no output';
    ok defined delete $SIG{TERM}, 'Should have set term signal';
    is delete $ENV{PLACK_ENV}, 'development', 'Should have set development env';
    $mocker->unmock('run');
}

##############################################################################
# Test run().
RUN: {
    my $conf = load_config;

    # Mock the consume method.
    my $mocker = Test::MockModule->new($CLASS);
    my $params;
    $mocker->mock(consume => sub {
        $_[0]->conn->dbh;   # Connect to the database.
        shift->continue(0); # Break out of run loop.
        $params = \@_;      # Trap params.
    });

    # Mock the DBI do method.
    my $db_mocker = Test::MockModule->new('DBI::db', no_auto => 1);
    my @done;
    $db_mocker->mock(do => sub { shift; push @done => \@_ });
    my $exp_done = [map { ["LISTEN pgxn_$_"] } PGXN::Manager::Consumer::CHANNELS ];

    # Run it.
    local @ARGV = qw(--env test --interval 0);
    my $cfg = $CLASS->_config;
    $cfg->{log_fh} = $log_fh;
    my $consumer = $CLASS->new($cfg);
    is $consumer->interval, 0, 'Should have interval 0';
    is $consumer->continue, 1, 'Should have default continue 1';
    is $consumer->verbose, 0, 'Should have default verbose 0';
    is $consumer->run, 0, 'Run consumer';

    is_deeply output(), join("\n",
        "$logtime - INFO: Starting $CLASS " . $CLASS->VERSION,
        "$logtime - INFO: Shutting down",
        '',
    ), 'Should have startup and shutdown log entries';
    is_deeply \@done, $exp_done, 'Should have listened to all channels';
    ok $consumer->conn->dbh->{Callbacks}{connected},
        'Should have configured listening in connected callback';

    is @{ $params }, 1, 'Should have passed one param to consume';
    is_deeply [keys %{ $params->[0] }], ["release"], 'Should have one key in param';
    is @{ $params->[0]{release} }, 2, 'Should have two release handlers';
    my ($masto, $twtr) = @{ $params->[0]{release} };
    isa_ok $masto, 'PGXN::Manager::Consumer::mastodon', 'First handler';
    isa_ok $twtr, 'PGXN::Manager::Consumer::twitter', 'Second handler';
    is $masto->server, $conf->{consumers}[0]{"server"},
        'Mastodon handler should have server configured';
    ok defined $twtr->client, 'Twitter client should be present';

    # Remove consumer config.
    delete PGXN::Manager->instance->config->{consumers};
    $consumer->continue(1);
    $params = undef;
    is $consumer->run, 0, 'Run consumer';
    is_deeply output(), join("", map { "$logtime - $_\n" }
        "INFO: Starting $CLASS " . $CLASS->VERSION,
        "WARN: No consumers configured; messages will be dropped",
        "INFO: Shutting down",
    ), 'Should have warning about no consumers';
    is @{ $params }, 1, 'Should have passed one param to consume';
    is_deeply [keys %{ $params->[0] }], [], 'Should have no key in param';

    # Turn on verbosity.
    PGXN::Manager->instance->config->{consumers} = $conf->{consumers};
    $consumer->continue(1);
    $params = undef;
    $db_mocker->mock(selectcol_arrayref => sub {
        [PGXN::Manager::Consumer::CHANNELS]
    });
    $consumer = $CLASS->new(interval => 0, verbose => 1, log_fh => $log_fh);
    is $consumer->verbose, 1, 'Should have verbosity 1';
    is $consumer->run, 0, 'Run consumer';
    is_deeply output(), join("", map { "$logtime - $_\n" }
        "INFO: Starting $CLASS " . $CLASS->VERSION,
        "INFO: Listening on $chans",
        "INFO: Shutting down",
    ), 'Should have verbose output';
    $mocker->unmock('consume');
};

##############################################################################
# Test consume.
CONSUME: {
    # Mock up some handlers.
    my $h1 = _testConsumer->new;
    my $h2 = _testConsumer->new;
    my $h3 = _testConsumer->new;
    my $handlers = {
        release => [$h1, $h2],
        report  => [$h1, $h3],
        drop    => [$h2],
    };

    # Wrap the constuctor to listen for our test handlers.
    my @channels = keys %{ $handlers };
    my $new_consumer = sub {
        my $c = $CLASS->new(@_, log_fh => $log_fh);
        $c->conn->run(sub { $_[0]->do("LISTEN pgxn_$_") for @channels });
        $c;
    };

    # Set up a notification.
    my $json1 = '{"name": "Julie ❤️"}';
    my $payload1 = {name => 'Julie ❤️'};
    my $consumer = $new_consumer->(verbose => 2, log_fh => $log_fh);
    $consumer->conn->run(sub {
        $_->do("SELECT pg_notify(?, ?)", undef, 'pgxn_release', $json1);
    });

    # Make it so.
    ok $consumer->consume($handlers), 'Consume';
    my $pid = $consumer->conn->dbh->{pg_pid};
    is_deeply output(), encode_utf8 join("\n", map { "$logtime - $_" }
        'INFO: Listening on ' . join(', ', PGXN::Manager::Consumer::CHANNELS),
        "INFO: Received “pgxn_release” event from PID $pid",
        'INFO: Sending to tc handler',
        'INFO: Sending to tc handler' . "\n",
    ), 'Should have verbose output';

    # Make sure the release handlers processed it.
    is_deeply $h1->args, [['release', $payload1]],
        'Should have passed release to h1';
    is_deeply $h2->args, [['release', $payload1]],
        'Should have passed release to h2';
    is_deeply $h3->args, [], 'Should have not called h3';

    # Send a report.
    my $json2 = '{"go": "hi"}';
    my $payload2 = {go => 'hi'};
    $consumer->conn->run(sub {
        $_->do("SELECT pg_notify(?, ?)", undef, 'pgxn_report', $json2);
    });
    ok $consumer->consume($handlers), 'Consume';
    is_deeply output(), encode_utf8 join("\n",  map { "$logtime - $_" }
        "INFO: Received “pgxn_report” event from PID $pid",
        'INFO: Sending to tc handler',
        'INFO: Sending to tc handler' . "\n",
    ), 'Should have verbose output again';
    is_deeply $h1->args, [['report', $payload2]],
        'Should have passed report to h1';
    is_deeply $h3->args, [['report', $payload2]],
        'Should have passed report to h3';
    is_deeply $h2->args, [], 'Should have not called h2';

    # Go quiet, send a drop.
    my $json3 = '{"drop": "out"}';
    my $payload3 = {drop => 'out'};
    $consumer = $new_consumer->(verbose => 0, log_fh => $log_fh);
    $consumer->conn->run(sub {
        $_->do("SELECT pg_notify(?, ?)", undef, 'pgxn_drop', $json3);
    });
    ok $consumer->consume($handlers), 'Consume';
    is_deeply output(), "", 'Should have no log output';
    is_deeply $h1->args, [], 'Should have not called h1';
    is_deeply $h2->args, [['drop', $payload3]],
        'Should have passed drop to h2';
    is_deeply $h3->args, [], 'Should have not called h3';

    # Send an unknown event.
    $consumer->conn->run(sub {
        $_->do("LISTEN nope");
        $_->do("SELECT pg_notify(?, ?)", undef, 'nope', $json2);
    });
    ok $consumer->consume($handlers), 'Consume';
    is_deeply output(), encode_utf8 join("\n", map { "$logtime - $_" }
        'WARN: Unknown channel “nope”; skipping' . "\n",
    ), 'Should have skipped event';
    is_deeply $h1->args, [], 'Should have not called h1';
    is_deeply $h2->args, [], 'Should have not called h2';
    is_deeply $h3->args, [], 'Should have not called h3';

    # Send invalid JSON.
    $consumer->conn->run(sub {
        $_->do("SELECT pg_notify(?, ?)", undef, 'pgxn_drop', '{"foo: "bar"}');
    });
    ok $consumer->consume($handlers), 'Consume';
    like output(), qr/^$logtime - ERORR: Cannot decode JSON:/, 'Should have JSON error';
    is_deeply $h1->args, [], 'Should have not called h1';
    is_deeply $h2->args, [], 'Should have not called h2';
    is_deeply $h3->args, [], 'Should have not called h3';

    # Remove a handlers.
    delete $handlers->{drop};
    $consumer = $new_consumer->(verbose => 1);
    $consumer->conn->run(sub {
        $_->do("SELECT pg_notify(?, ?)", undef, 'pgxn_drop', $json3);
    });
    ok $consumer->consume($handlers), 'Consume';
    $pid = $consumer->conn->dbh->{pg_pid};
    is_deeply output(), encode_utf8 join("\n", map { "$logtime - $_" }
        "INFO: Listening on $chans",
        "INFO: Received “pgxn_drop” event from PID $pid",
        "INFO: No handlers configured for pgxn_drop channel; skipping\n",
    ), 'Should have skipped event';
    is_deeply $h1->args, [], 'Should have not called h1';
    is_deeply $h2->args, [], 'Should have not called h2';
    is_deeply $h3->args, [], 'Should have not called h3';
}

package _testConsumer;

sub name { 'tc' }

sub new {
    return bless { args => [] } => __PACKAGE__;
}

sub args {
    my $self = shift;
    my $ret = $self->{args};
    $self->{args} = [];
    return $ret;
}

sub handle {
    my $self = shift;
    push @{ $self->{args} } => \@_;
}
