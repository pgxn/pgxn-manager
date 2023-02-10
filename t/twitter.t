#!/usr/bin/env perl -w

use 5.10.0;
use strict;
use warnings;
use utf8;

use Test::More tests => 20;
# use Test::More 'no_plan';
use JSON::XS;
use Test::Exception;
use Test::MockModule;
use lib 't/lib';
use TxnTest;

BEGIN {
    use_ok 'PGXN::Manager' or die;
    use_ok 'PGXN::Manager::Consumer::twitter' or die;
}

can_ok 'PGXN::Manager::Consumer::twitter', qw(
    new
    client
    handle
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
my $twitter = PGXN::Manager::Consumer::twitter->new( config => $cfg );
is $twitter->name, 'twitter', 'Should have name method';

# Should get an exception for missing API config.
CONFIG: {
    for my $key (qw(consumer_key consumer_secret access_token access_token_secret)) {
        my $val = delete $cfg->{$key};
        throws_ok { PGXN::Manager::Consumer::twitter->new(config => $cfg) }
            qr/Missing Twitter API $key/, "Should have no clent when no $key";
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

# Start with unkown event.
is $twitter->handle(nonesuch => $meta), undef,
    'Should send no message for unknown event';

# Send release event.
ok $twitter->handle(release => $meta), 'Should send release message';

# Look up the Twitter username in the database.
$meta->{user} = TxnTest->user;
$tweet = "$meta->{name} $meta->{version} released by \@notHere: $url";
ok $twitter->handle(release => $meta), 'Should send message with Twitter nick';

# Have Twitter throw an exception.
$twitter_mock->mock(update => sub { die 'WTF!' });
throws_ok {$twitter->client->update('hi!') } qr/WTF!/, 'Fail to send a tweet';
