#!/usr/bin/env perl -w

use 5.10.0;
use strict;
use warnings;
use utf8;

use Test::More tests => 31;
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

##############################################################################
# Load the class.
BEGIN {
    use_ok 'PGXN::Manager' or die;
    use_ok 'PGXN::Manager::Consumer' or die;
    use_ok 'PGXN::Manager::Consumer::twitter' or die;
}

can_ok 'PGXN::Manager::Consumer::twitter', qw(
    new
    client
    handle
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
while (@{ $conf->{consumers} } && $cfg->{type} ne 'twitter') {
    $cfg = shift @{ $conf->{consumers} };
}
die "No twitter config found in conf/test.json\n" unless $cfg;
delete $cfg->{events};
my $twitter = PGXN::Manager::Consumer::twitter->new(
    config => $cfg,
    logger => $logger,
);
is $twitter->name, 'twitter', 'Should have name method';

# Should get an exception for missing API config.
CONFIG: {
    for my $key (qw(consumer_key consumer_secret access_token access_token_secret)) {
        my $val = delete $cfg->{$key};
        throws_ok { PGXN::Manager::Consumer::twitter->new(
            config => $cfg,
            logger => $logger,
        ) } qr/Missing Twitter API $key/, "Should have no clent when no $key";
        $cfg->{$key} = $val;
    }
}

# Test tweeting.
my $twitter_mock = Test::MockModule->new('Net::Twitter::Lite::WithAPIv1_1');
# Force the class to load.
Net::Twitter::Lite::WithAPIv1_1->new( ssl => 1 );
my $tweet = 'Hey man';
$twitter_mock->mock(update => sub {
    my ($nt, $msg) = @_;
    is $msg, $tweet, 'Should have proper twitter message';
    for my $key (qw(consumer_key consumer_secret access_token access_token_secret)) {
        is $nt->{$key}, $cfg->{$key}, "$key should be set properly";

    }
    return $nt;
});

ok $twitter->client->update($tweet), 'Send a tweet!';

# Test handler.
my $meta = {
    user    => 'theory',
    name    => 'pgTAP',
    version => '1.3.5',
    release_status => 'stable',
};
my $pgxn = PGXN::Manager->instance;
my $url = URI::Template->new($pgxn->config->{release_permalink})->process({
    dist    => lc $meta->{name},
    version => lc $meta->{version},
});
$tweet = "$meta->{name} $meta->{version} released by $meta->{user}: $url";
$twitter_mock->mock(update => sub {
    my ($nt, $msg) = @_;
    is $msg, $tweet, 'Should have release twitter message';
    return $nt;
});

# Start with unknown event.
is output(), '', 'Should have no output so far';
is $twitter->handle(nonesuch => $meta), undef,
    'Should send no message for unknown event';
is output(), '', 'Should have no log for unknown event';

# Try it with debug verbosity.
$logger->{verbose} = 2;
is $twitter->handle(nonesuch => $meta), undef,
    'Should send no message for unknown event';
is output(),
    "$logtime - DEBUG: Twitter skiping nonesuch notification\n",
    'Should have unknown event log message';

# Send release event.
ok $twitter->handle(release => $meta), 'Should send release message';
is output(),
    "$logtime - DEBUG: Fetching Twitter username for $meta->{user}\n" .
    "$logtime - INFO: Posting \L$meta->{name}-$meta->{version}\E to Twitter\n",
    'Should have DEBUG username lookup and INFO message for posting';

# Look up the Twitter username in the database.
$logger->{verbose} = 1;
$meta->{release_status} = 'testing';
$meta->{user} = TxnTest->user;
$tweet = "$meta->{name} $meta->{version} (testing) released by \@notHere: $url";
ok $twitter->handle(release => $meta), 'Should send message with Twitter nick';
is output(),
    "$logtime - INFO: Posting \L$meta->{name}-$meta->{version}\E to Twitter\n",
    'Should have INFO message for posting';

# Have Twitter throw an exception.
$twitter_mock->mock(update => sub { die "WTF!\n" });
ok !$twitter->handle(release => $meta), 'Should not send message';
is output(),
    "$logtime - INFO: Posting \L$meta->{name}-$meta->{version}\E to Twitter\n" .
    "$logtime - ERROR: Error posting \L$meta->{name}-$meta->{version}\E to Twitter: WTF!\n\n",
    'Should have INFO message and ERROR message';
