#!/usr/bin/env perl -w

use 5.10.0;
use strict;
use warnings;
use utf8;

use Test::More tests => 37;
# use Test::More 'no_plan';
use JSON::XS;
use Test::Exception;
use Test::MockModule;
use lib 't/lib';
use TxnTest;

##############################################################################
# Mock time.
my (@gmtime, $time);
BEGIN {
    $time = CORE::time();
    @gmtime = CORE::gmtime($time);
    *CORE::GLOBAL::time = sub() { return $time };
    *CORE::GLOBAL::gmtime = sub (;$) { return @gmtime }
}

sub mktime {
    POSIX::strftime '%Y-%m-%dT%H:%M:%SZ', gmtime time + shift;
}

##############################################################################
# Load the class.
BEGIN {
    use_ok 'PGXN::Manager' or die;
    use_ok 'PGXN::Manager::Consumer' or die;
    use_ok 'PGXN::Manager::Consumer::mastodon' or die;
}

can_ok 'PGXN::Manager::Consumer::mastodon', qw(
    new
    server
    ua
    delay
    handle
    toot
    scheduled_at
);

# Silence "used only once" warning by using CORE::GLOBAL::time.
is CORE::GLOBAL::time(), time, 'Time should be mocked';

# Grab the timestamp that will appear in logs.
my $logtime = POSIX::strftime '%Y-%m-%dT%H:%M:%SZ', gmtime $time;
is time, $time, 'Should have mocked time';
is POSIX::strftime('%Y-%m-%dT%H:%M:%SZ', gmtime), $logtime,
    'Should have mocked gmtime';

##############################################################################
# Mock log destination.
my $log_output = '';
my $log_fh = IO::File->new(\$log_output, 'w');
$log_fh->binmode(':utf8');
sub output {
    my $ret = $log_output;
    $log_fh->seek(0, 0);
    $log_output = '';
    return $ret // '';
}

# Set up a logger.
my $logger = PGXN::Manager::Consumer::Log->new(
    verbose => 1,
    log_fh  => $log_fh,
);

open my $fh, '<:raw', 'conf/test.json' or die "Cannot open conf/test.json: $!\n";
my $conf = do {
    local $/;
    decode_json <$fh>;
};
close $fh;

my $cfg = shift @{ $conf->{consumers} };
while (@{ $conf->{consumers} } && $cfg->{type} ne 'mastodon') {
    $cfg = shift @{ $conf->{consumers} };
}
die "No mastodon config found in conf/test.json\n" unless $cfg;
delete $cfg->{events};
my $mastodon = PGXN::Manager::Consumer::mastodon->new(
    config => $cfg,
    logger => $logger,
);

is $mastodon->server, $cfg->{server}, 'The server should be loaded';
is $mastodon->delay, $cfg->{delay}, "The delay should be set";
is $mastodon->name, 'mastodon', 'Should have name method';

# Test UA.
ok my $ua = $mastodon->ua, 'Should have user agent';
is $ua->timeout, 60, 'SHould have timeout 60';
is $ua->agent, $ua->agent(
    'PGXN::Manager::Consumer::mastodon/' . PGXN::Manager::Consumer::mastodon->VERSION
), 'Should have user agent string';
is_deeply [$ua->ssl_opts], ["verify_hostname"], 'Should have SSL options';
is_deeply $ua->default_headers, {
    'user-agent' => 'PGXN::Manager::Consumer::mastodon/' . PGXN::Manager::Consumer::mastodon->VERSION,
    'content-type' => 'application/json',
    'authorization' => "Bearer $cfg->{token}",
}, 'Should have default headers';

# Test scheduled_at.
for my $i (200, 300, 400, 500, 600, 1000) {
    my $m = PGXN::Manager::Consumer::mastodon->new(
        config => $cfg,
        logger => $logger,
        delay  => $i,
    );
    is_deeply [$m->scheduled_at], [scheduled_at => mktime($i)],
        "Should get scheduled_at delay $i";
}

# Should get an exception when no token or server.
CONFIG: {
    for my $key (qw(server token)) {
        my $val = delete $cfg->{$key};
        throws_ok { PGXN::Manager::Consumer::mastodon->new(config => $cfg) }
            qr/Missing Mastodon API $key/, "Should have no UA when no $key";
        $cfg->{$key} = $val;
    }
}

# Test tooting.
is output(), '', 'Should have no output yet';
my $ua_mock = Test::MockModule->new('LWP::UserAgent');
my $toot = 'Hey man';
$ua_mock->mock(post => sub {
    my ($ua, $url, %params) = @_;
    is $url, "$cfg->{server}/api/v1/statuses", 'Should have proper URL';
    $params{Content} = decode_json $params{Content};
    is_deeply \%params, { Content => {
        status => $toot,
        scheduled_at => mktime($cfg->{delay}),
    } },
        'Should have JSON encoded status message';
    return HTTP::Response->new(200);
});

ok $mastodon->toot("release_name", $toot), 'Send a toot!';
is output(), '', 'Should still have no output';

# Test toot with error.
$ua_mock->mock(post => sub {
    return HTTP::Response->new(404, 'not found', undef, 'oops');
});
ok !$mastodon->toot("release_name", $toot), 'Toot send should fail';
is output(),
    "$logtime - ERROR: Error posting release_name to Mastodon (status 404): oops\n",
    'Should have error log message';

# Test handler.
my $meta = {
    user     => 'theory',
    name     => 'pgTAP',
    abstract => "Unit testing for PostgreSQL",
    version  => '1.3.5',
};
my $pgxn = PGXN::Manager->instance;
my $url = URI::Template->new($pgxn->config->{release_permalink})->process({
    dist    => lc $meta->{name},
    version => lc $meta->{version},
});

# Start with unkown event.
is $mastodon->handle(nonesuch => $meta), undef,
    'Should send no message for unknown event';
is output(), '', 'Should have no output';

# Send release event.
SEND: {
    my $mock_masto = Test::MockModule->new('PGXN::Manager::Consumer::mastodon');
    my ($rel, $msg);
    $mock_masto->mock(toot => sub { ($rel, $msg) = ($_[1], $_[2]) });
    ok $mastodon->handle(release => $meta), 'Should send release message';
    is $rel, lc("$meta->{name}-$meta->{version}"), 'Release should have been passed';
    like $msg, qr/\S+ \QReleased: $meta->{name} $meta->{version}\E\n\n\S+ \Q$meta->{abstract}\E\n\n\S+ \QBy $meta->{user}\E\n\n$url/ms,
        'Should have sent the formatted message';
    is output(), "$logtime - INFO: Posting pgtap-1.3.5 to Mastodon\n",
        'Should have info log message';
}

# Have Mastodon throw an exception.
$ua_mock->mock(post => sub { die 'WTF!' });
throws_ok {$mastodon->toot('hi!') } qr/WTF!/, 'Fail to send a toot';
