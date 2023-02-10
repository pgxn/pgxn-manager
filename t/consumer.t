#!/usr/bin/env perl -w

use 5.10.0;
use strict;
use warnings;
use utf8;
use Encode qw(encode_utf8);
use JSON::XS;

use Test::More tests => 94;
# use Test::More 'no_plan';
use Test::Output;
use Test::MockModule;
use Test::Exception;

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
    is $consumer->continue, 1, 'Defaault continue is 1';
}

##############################################################################
# Test and then mock _emit
stdout_is { ok PGXN::Manager::Consumer::_emit("Hello there 😀"), '_emit' }
    encode_utf8 "Hello there 😀" . "\n",
    "_emit should encode text";

# Mock emit.
my $mock = Test::MockModule->new($CLASS);
my @said;
$mock->mock(_emit => sub { push @said => @_ });
sub output {
    my @ret = @said;
    @said = ();
    return \@ret;
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
    );
    my $opts = $CLASS->_config;
    is_deeply $opts, {
        daemonize => 1,
        pid       => 'pid.txt',
        interval  => 2.2,
        verbose   => 1,
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
    my $consumer = $CLASS->new();
    my $handlers = $consumer->load_consumers($conf->{consumers});
    is_deeply [keys %{ $handlers }], ["release"], 'Should have one key';
    is @{ $handlers->{release} }, 2, 'Should have two release handlers';
    my ($masto, $twtr) = @{ $handlers->{release} };
    isa_ok $masto, 'PGXN::Manager::Consumer::mastodon', 'First handler';
    isa_ok $twtr, 'PGXN::Manager::Consumer::twitter', 'Second handler';
    is $masto->server, $conf->{consumers}[0]{"server"},
        'Mastdone handler should have server configured';
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
    my $mocker = Test::MockModule->new($CLASS);
    my $ran;
    $mocker->mock(run => sub { $ran = 1; 0 });
    local @ARGV = qw(--env test --daemonize);
    is $CLASS->go, 0, 'Should get zero from go';
    ok $ran, 'Should have run';
    is_deeply output(), [], 'Should have no output';
    ok defined delete $SIG{TERM}, 'Should have set term signal';
    is delete $ENV{PLACK_ENV}, 'test', 'Should have set test env';

    # Now make a pid.
    $mock_proc->mock(Init => 42);
    $ran = 0;
    @ARGV = qw(-D);
    is $CLASS->go, 0, 'Should get zero from go';
    ok !$ran, 'Should not have run';
    is_deeply output(), [42], 'Should emitted the PID';
    is $SIG{TERM}, undef, 'Should not ahve set term signal';
    is delete $ENV{PLACK_ENV}, 'development', 'Should have set development env';
    $mocker->unmock('run');
}

GO: {
    # Test without daemonization.
    my $mocker = Test::MockModule->new($CLASS);
    my $ran;
    $mocker->mock(run => sub { $ran = 1; 0 });
    is $CLASS->go, 0, 'Should get zero from go';
    ok $ran, 'Should have run';
    is_deeply output(), [], 'Should have no output';
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
    my $consumer = $CLASS->new($CLASS->_config);
    is $consumer->interval, 0, 'Should have interval 0';
    is $consumer->continue, 1, 'Should have default continue 1';
    is $consumer->verbose, 0, 'Should have default verbose 0';
    is $consumer->run, 0, 'Run consumer';

    is_deeply output(), [], 'Should have no output';
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
        'Mastdone handler should have server configured';
    ok defined $twtr->client, 'Twitter client should be present';

    # Remove consumer config.
    delete PGXN::Manager->instance->config->{consumers};
    $consumer->continue(1);
    $params = undef;
    is $consumer->run, 0, 'Run consumer';
    is_deeply output(), ['No consumers configured; messages will be dropped'],
        'Should have warning about no consumers';
    is @{ $params }, 1, 'Should have passed one param to consume';
    is_deeply [keys %{ $params->[0] }], [], 'Should have no key in param';

    # Turn on verbosity.
    PGXN::Manager->instance->config->{consumers} = $conf->{consumers};
    $consumer->continue(1);
    $params = undef;
    $consumer = $CLASS->new(interval => 0, verbose => 1);
    is $consumer->verbose, 1, 'Should have verbosity 1';
    is $consumer->run, 0, 'Run consumer';
    is_deeply output(), [
        "Listening on " . join(', ', PGXN::Manager::Consumer::CHANNELS),
    ], 'Should have verbose output';
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
        my $c = $CLASS->new(@_);
        $c->conn->run(sub { $_[0]->do("LISTEN pgxn_$_") for @channels });
        $c;
    };

    # Set up a notification.
    my $json1 = '{"name": "Julie ❤️"}';
    my $payload1 = {name => 'Julie ❤️'};
    my $consumer = $new_consumer->(verbose => 2);
    $consumer->conn->run(sub {
        $_->do("SELECT pg_notify(?, ?)", undef, 'pgxn_release', $json1);
    });

    # Make it so.
    ok $consumer->consume($handlers), 'Consume';
    my $pid = $consumer->conn->dbh->{pg_pid};
    is_deeply output(), [
        'Listening on ' . join(', ', PGXN::Manager::Consumer::CHANNELS),
        'Consuming',
        "Received “pgxn_release” event from PID $pid",
        'Sending to tc handler',
        'Sending to tc handler',
    ], 'Should have verbose output';

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
    is_deeply output(), [
        'Consuming',
        "Received “pgxn_report” event from PID $pid",
        'Sending to tc handler',
        'Sending to tc handler',
    ], 'Should have verbose output again';
    is_deeply $h1->args, [['report', $payload2]],
        'Should have passed report to h1';
    is_deeply $h3->args, [['report', $payload2]],
        'Should have passed report to h3';
    is_deeply $h2->args, [], 'Should have not called h2';

    # Go quiet, send a drop.
    my $json3 = '{"drop": "out"}';
    my $payload3 = {drop => 'out'};
    $consumer = $new_consumer->(verbose => 0);
    $consumer->conn->run(sub {
        $_->do("SELECT pg_notify(?, ?)", undef, 'pgxn_drop', $json3);
    });
    ok $consumer->consume($handlers), 'Consume';
    is_deeply output(), [], 'Should have no output';
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
    is_deeply output(), ["Unknown channel “nope”; skipping"],
        'Should have skipped event';
    is_deeply $h1->args, [], 'Should have not called h1';
    is_deeply $h2->args, [], 'Should have not called h2';
    is_deeply $h3->args, [], 'Should have not called h3';

    # Send invalid JSON.
    $consumer->conn->run(sub {
        $_->do("SELECT pg_notify(?, ?)", undef, 'pgxn_drop', '{"foo: "bar"}');
    });
    ok $consumer->consume($handlers), 'Consume';
    my $out = output();
    is @{ $out }, 1, 'Should have one output';
    like $out->[0], qr/^Cannot decode JSON:/, 'Should have json error';
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
    is_deeply output(), [
        'Listening on ' . join(', ', PGXN::Manager::Consumer::CHANNELS),
        "Received “pgxn_drop” event from PID $pid",
        "No handlers configured for pgxn_drop channel; skipping",
    ], 'Should have skipped event';
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