#!/usr/bin/env perl -w

use 5.10.0;
use strict;
use warnings;
use utf8;

use Test::More tests => 50;
#use Test::More 'no_plan';
use JSON::XS;
use Test::File;
use Test::File::Contents;
use Test::MockModule;
use File::Path 'remove_tree';
use File::Copy 'copy';

BEGIN {
    use_ok 'PGXN::Manager' or die;
}

can_ok 'PGXN::Manager', qw(
    config
    conn
    instance
    initialize
    uri_templates
    email_transport
    init_root
    move_file
    send_email
);

isa_ok my $pgxn = PGXN::Manager->instance, 'PGXN::Manager';
is +PGXN::Manager->instance, $pgxn, 'instance() should return a singleton';
is +PGXN::Manager->instance, $pgxn, 'new() should return a singleton';

open my $fh, '<:raw', 'conf/test.json' or die "Cannot open conf/test.json: $!\n";
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

##############################################################################
# Make sure we can initialize the mirror root.
my $index = File::Spec->catfile($pgxn->config->{mirror_root}, 'index.json');
my $spec = File::Spec->catfile($pgxn->config->{mirror_root}, qw(meta spec.txt));
END { remove_tree $pgxn->config->{mirror_root} }
file_not_exists_ok $index, "$index should not exist";
file_not_exists_ok $spec, "$spec should not exist";
ok $pgxn->init_root, 'Initialize the mirror root';
file_exists_ok $index, "$index should now exist";
file_exists_ok $spec, "$spec should now exist";

# Make sure that index.json contains what it ought to.
file_contents_is $index, JSON::XS->new->indent->space_after->canonical->encode(
    $pgxn->config->{uri_templates}
), "... And $index should have the mirror templates specified in it";

# Make sure that spec.txt contains what it ought to.
file_contents_like $spec,
    qr{PGXN Meta Spec - The PGXN distribution metadata specification},
    "...And $spec should look like the meta spec";

# Make sure they don't get overwritten by subsequent calls to init_root().
my $mock_json = Test::MockModule->new('JSON::XS');
$mock_json->mock(new => sub { fail 'JSON::XS->new should not be called!' });
copy 'README.md', $spec;
ok $pgxn->init_root, 'Init the root again';
file_exists_ok $index, "$index should still exist";
file_contents_unlike $spec,
    qr{PGXN Meta Spec - The PGXN distribution metadata specification},
    "...And $spec should not have been replaced";

# Make sure a newer spec.txt updates the mirror.
my $time = (stat File::Spec->catfile(qw(doc spec.txt)))[9];
utime $time, $time - 5, $spec;
ok $pgxn->init_root, 'Init the root once more';
file_contents_like $spec,
    qr{PGXN Meta Spec - The PGXN distribution metadata specification},
    "Now $spec should be updated";

##############################################################################
# Make sure the URI templates are created.
ok my $tmpl = $pgxn->uri_templates, 'Get URI templates';
isa_ok $tmpl, 'HASH', 'Their storage';
isa_ok $tmpl->{$_}, 'URI::Template', "Template $_" for keys %{ $tmpl };

# Test email_transport.
ok my $trans = $pgxn->email_transport, 'Should have email transport';
ok $trans->DOES('Email::Sender::Transport'),
    'And it should do Email::Sender::Transport';

##############################################################################
# Test send_email().
my $email_mock = Test::MockModule->new('Email::Sender::Simple');
my ($email, $params);
$email_mock->mock(send => sub {
    shift;
    ($email, $params) = @_;
});

ok $pgxn->send_email({
    to      => 'fred@example.com',
    from    => 'joe@example.net',
    subject => 'Hi',
    body    => 'How you doin?',
}), 'Send an email';

is_deeply $params, { transport => $pgxn->email_transport },
    'The email params should be correct';
isa_ok $email, 'Email::MIME', 'The email';
my $headers = { $email->header_pairs };
like delete $headers->{'Content-Type'}, qr{text/plain; charset="?UTF-8"?},
    'The Content Type should be correct';
is_deeply $headers, {
    'To'           => 'fred@example.com',
    'From'         => 'joe@example.net',
    'Subject'      => 'Hi',
    'MIME-Version' => '1.0',
    'Date'         => $email->header('Date'),
}, 'The other headers should be correct';

is $email->body, 'How you doin?', 'The body should be correct';
