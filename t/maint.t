#!/usr/bin/env perl -w

use 5.10.0;
use strict;
use warnings;
use utf8;

use Test::More tests => 144;
# use Test::More 'no_plan';
use Test::File;
use File::Path qw(remove_tree);
use File::Basename qw(basename);
use Test::MockModule;
use Test::File::Contents;
use Test::Output;
use Encode qw(encode_utf8);
use JSON::XS;
use Archive::Zip qw(:ERROR_CODES);
use lib 't/lib';
use TxnTest;

my $CLASS;

BEGIN {
    $CLASS = 'PGXN::Manager::Maint';
    use_ok $CLASS or die;
}

can_ok $CLASS => qw(
    new
    go
    run
    verbosity
    workdir
    update_stats
    update_users
    reindex
    reindex_all
    reset_password
    _write_json_to
    DEMOLISH
    _pod2usage
    _config
);

my $tmpdir  = File::Spec->catdir(File::Spec->tmpdir, 'pgxn');
my $root    = PGXN::Manager->new->config->{mirror_root};
my $distdir = File::Spec->catdir(qw(t dist widget));
my $distzip = File::Spec->catdir(qw(t dist widget-0.2.5.zip));

# Create a distribution.
my $dzip = Archive::Zip->new;
$dzip->addTree($distdir, 'widget-0.2.5') == AZ_OK or die 'tree error';
$dzip->writeToFileNamed($distzip) == AZ_OK or die 'write error';

END {
    unlink $distzip;
    remove_tree $tmpdir, $root;
}

##############################################################################
# Instantiate and test config.
my $maint = new_ok $CLASS;

DEFAULT: {
    local @ARGV;
    is_deeply { $maint->_config }, { verbosity => 0 },
        'Default options should be correct';
}

##############################################################################
# Test _write_json_to().
my $file = File::Spec->catfile($root, 'tmp.json');
file_not_exists_ok $file, 'Test JSON file should not exist';
ok $maint->_write_json_to('{"name": "Bjørn"}', $file), 'Write JSON to a file';
file_exists_ok $file, 'Test JSON file should now exist';
my $data = decode_json do {
    open my $fh, '<:raw', $file or die "Cannot open $file: $!\n";
    local $/;
    <$fh>;
};
is_deeply $data, {name => 'Bjørn'}, 'The JSON should have been properly written';

##############################################################################
# Test run().
RUN: {
    my $mocker = Test::MockModule->new($CLASS);
    my $params;
    $mocker->mock(update_stats => sub { shift; $params = \@_ });
    ok $maint->run('update_stats'), 'Run update_stats';
    is_deeply $params, [], 'Should have called update_stats method';

    # Try a dashed command.
    ok $maint->run('update-stats', 'now'), 'Run update-stats';
    is_deeply $params, ['now'], 'Should have called update_stats';

    # Make sure we croak for an unknown command.
    local $@;
    eval { $maint->run('nonexistent') };
    like $@, qr{PGXN Maint: "nonexistent" is not a command},
        'Should get an error for an unknown command';
};

##############################################################################
# Tetst go().
GO: {
    my $mocker = Test::MockModule->new($CLASS);
    my $params;
    $mocker->mock(run => sub { my $s = shift; $params = \@_; $s });
    local @ARGV = qw(--verbose update_stats now);
    is $maint->go, 0, 'Go!';
    is_deeply $params, [qw(update_stats now)],
        'Should have called run with command and args';

    # Try with a dashed task.
    @ARGV = qw(--verbose update-stats now);
    is $maint->go, 0, 'Go!';
    is_deeply $params, [qw(update-stats now)],
        'Should have called run with command and args';

    # Try with an error code.
    $mocker->mock(run => sub { $_[0]->exitval(42); $_[0] });
    is $maint->go, 42, 'Go should return exitval!';
};

##############################################################################
# Okay, we need some distributions in the database.
my $user = TxnTest->user; # Create user.
PGXN::Manager->instance->conn->run(sub {
    my $dbh = shift;
    $dbh->do(
        'SELECT * FROM add_distribution(?, ?, ?)',
        undef, $user, 'the-sha1-hash',
        '{
        "name": "pair",
        "version": "0.0.1",
        "license": "postgresql",
        "maintainer": "theory",
        "abstract": "Ordered pair",
        "description": "An ordered pair for PostgreSQL",
        "tags": ["foo", "bar", "baz"],
        "provides": {
            "pair": { "file": "pair.sql.in", "version": "0.2.2" },
            "trip": { "file": "trip.sql.in", "version": "0.2.1" }
        },
        "tags": ["foo", "bar", "baz"],
        "release_status": "testing",
        "meta-spec": {
           "version": "1.0.0",
           "url": "https://pgxn.org/meta/spec.txt"
        },
        "resources": {
          "homepage": "https://pgxn.org/dist/pair/"
        }
    }'
    );
    $dbh->do(
        'SELECT * FROM add_distribution(?, ?, ?)',
        undef, $user, 'the-sha1-hash2',
        '{
        "name": "pair",
        "version": "0.0.2",
        "license": "postgresql",
        "maintainer": "theory",
        "abstract": "Ordered pair",
        "description": "An ordered pair for PostgreSQL",
        "tags": ["foo", "bar", "baz"],
        "tags": ["foo", "bar", "baz", "yo"],
        "provides": {
            "pair": { "file": "pair.sql.in", "version": "0.2.2" },
            "trip": { "file": "trip.sql.in", "version": "0.2.2" }
        },
        "release_status": "testing",
        "meta-spec": {
           "version": "1.0.0",
           "url": "https://pgxn.org/meta/spec.txt"
        },
        "resources": {
          "homepage": "https://pgxn.org/dist/pair/"
        }
    }'
    );

    $dbh->do(
        'SELECT * FROM add_distribution(?, ?, ?)',
        undef, $user, 'the-sha1-hash3',
        '{
        "name":        "foo",
        "version":     "0.0.2",
        "license":     "postgresql",
        "maintainer":  "strongrrl",
        "abstract":    "whatever",
        "tags": ["Foo", "PAIR", "pair"],
        "meta-spec": {
           "version": "1.0.0",
           "url": "https://pgxn.org/meta/spec.txt"
        },
        "provides": { "foo": { "version": "0.0.2", "abstract": "whatever", "file": "foo.sql" } }
    }'
    );

    $dbh->do(
        'SELECT * FROM add_distribution(?, ?, ?)',
        undef, $user, 'the-sha1-hash4',
        '{
        "name":        "bar",
        "version":     "0.3.2",
        "license":     "postgresql",
        "maintainer":  "someone else",
        "abstract":    "whatever",
        "meta-spec": {
           "version": "1.0.0",
           "url": "https://pgxn.org/meta/spec.txt"
        },
        "provides": { "bar": { "version": "0.3.2", "abstract": "whatever", "file": "bar.sql" } }
    }'
    );

    $dbh->do(
        'SELECT * FROM add_distribution(?, ?, ?)',
        undef, $user, 'widget',
        '{
        "name":        "widget",
        "version":     "0.2.5",
        "license":     "postgresql",
        "maintainer":  "freddy",
        "abstract":    "widgets and sprockets",
        "meta-spec": {
           "version": "1.0.0",
           "url": "https://pgxn.org/meta/spec.txt"
        },
        "provides": { "widget": { "version": "0.2.5", "abstract": "widgety", "file": "widget.sql" } }
    }'
    );
});

##############################################################################
# Test update_stats().
my %files = map { join('/', @{ $_ }) => File::Spec->catfile($root, @{ $_ } ) } (
   ['stats', 'tag.json'      ],
   ['stats', 'user.json'     ],
   ['stats', 'extension.json'],
   ['stats', 'dist.json'     ],
   ['stats', 'summary.json'  ],
);
file_not_exists_ok $files{$_}, "File $_ should not yet exist" for keys %files;

# Generate 'em.
ok $maint->update_stats, 'Update the stats';
file_exists_ok $files{$_}, "File $_ should now exist" for keys %files;

##############################################################################
# Test reindex(). First, we need some distributions.
REINDEX: {
    my $mocker = Test::MockModule->new('PGXN::Manager::Distribution');
    my $zip = File::Spec->catfile($root, qw(dist pair 0.0.1 pair-0.0.1.zip));
    $mocker->mock(reindex => sub {
        my $dist = shift;
        pass 'Distribution->reindex should be called';
        is $dist->archive, $zip, 'Dist should have archive';
        is $dist->basename, 'pair-0.0.1.zip', 'Dist should have basename';
        is $dist->creator, $user, 'Dist should have user as creator';
    });

    ok $maint->reindex('pair', '0.0.1'), 'Reindex pair 0.0.1';
    is $maint->exitval, 0, 'Exit val should be 0';

    # Try indexing with file.
    $mocker->mock(reindex => sub {
        my $dist = shift;
        pass 'Distribution->reindex should be called again';
        is $dist->archive, $distzip, 'Dist should have specified archive';
        is $dist->basename, 'widget-0.2.5.zip', 'Dist basename should be "widget-0.2.5"';
        is $dist->creator, $user, 'Dist should have user as creator';
    });
    ok $maint->reindex($distzip), 'Reindex widget 0.2.5';
    is $maint->exitval, 0, 'Exit val should be 0';

    # Reindex two different distributions.
    my $zip2 = File::Spec->catfile($root, qw(dist foo 0.0.2 foo-0.0.2.zip));
    my @exp = ($zip, $zip2);

    $mocker->mock(reindex => sub {
        my $dist = shift;
        pass 'Distribution->reindex should be called';
        my $exp = shift @exp;
        my $base = basename($exp);
        is $dist->archive, $exp, "Dist $base should have archive";
        is $dist->basename, $base, "Dist $base should have basename";
        is $dist->creator, $user, "Dist $base should have user as creator";

    });

    ok $maint->reindex( pair => '0.0.1', foo => '0.0.2' ),
        'Reindex pair 0.0.1 and foo 0.0.2';
    is $maint->exitval, 0, 'Exit val should again be 0';

    # Make sure we warn for an unknown release.
    local $SIG{__WARN__} = sub {
        no utf8;
        is shift, "“nonexistent 0.0.1” is not a known release\n",
            'Should get warning for non-existant distribution';
    };
    ok $maint->reindex(nonexistent => '0.0.1'), 'Reindex nonexistent release';
    is $maint->exitval, 1, 'Exit val should be 1';
    $maint->exitval(0);

    # Make sure we emit a message and set exitval for a failed reindex.
    $mocker->mock(reindex => sub {
        shift->error(['This is an error: [_1]', 'ha']);
        return 0;
    });
    local $SIG{__WARN__} = sub {
        like shift, qr/This is an error: ha/,
            'Should get warning for reindex failure';
    };
    ok $maint->reindex( pair => '0.0.1', foo => '0.0.2' ),
        'Fail to Reindex pair 0.0.1 and foo 0.0.2';
    is $maint->exitval, 2, 'Exitval should reflect number of failures';
    $maint->exitval(0);
}

##############################################################################
# Test reindex_all.

REINDEX: {
    my $zip1 = File::Spec->catfile($root, qw(dist bar 0.3.2 bar-0.3.2.zip));
    my $zip2 = File::Spec->catfile($root, qw(dist foo 0.0.2 foo-0.0.2.zip));
    my $zip3 = File::Spec->catfile($root, qw(dist pair 0.0.2 pair-0.0.2.zip));
    my $zip4 = File::Spec->catfile($root, qw(dist pair 0.0.1 pair-0.0.1.zip));
    my $zip5 = File::Spec->catfile($root, qw(dist widget 0.2.5 widget-0.2.5.zip));

    # Reindex *everything*.
    my $mocker = Test::MockModule->new('PGXN::Manager::Distribution');
    my @exp = ($zip1, $zip2, $zip3, $zip4, $zip5);
    $mocker->mock(reindex => sub {
        my $dist = shift;
        pass 'Distribution->reindex should be called';
        my $exp = shift @exp;
        my $base = basename($exp);
        is $dist->archive, $exp, "Dist $base should have archive";
        is $dist->basename, $base, "Dist $base should have basename";
        is $dist->creator, $user, "Dist $base should have user as creator";
    });

    ok $maint->reindex_all, 'Reindex everything';
    is $maint->exitval, 0, 'Exit val should be 0';

    # Just reindex all pair distributions.
    @exp = ($zip3, $zip4);
    ok $maint->reindex_all('pair'), 'Reindex all pairs';
    is $maint->exitval, 0, 'Exit val should again be 0';

    # Reindex named distros.
    @exp = ($zip2, $zip3, $zip4);
    ok $maint->reindex_all('pair', 'foo'), 'Reindex all pairs and foos';
    is $maint->exitval, 0, 'Exit val should still be 0';

    # Make sure we emit a message and set exitval for a failed reindex.
    $mocker->mock(reindex => sub {
        shift->error(['This is an error: [_1]', 'ha']);
        return 0;
    });
    local $SIG{__WARN__} = sub {
        like shift, qr/This is an error: ha/,
            'Should get warning for reindex failure';
    };
    ok $maint->reindex_all( 'pair', 'foo' ),
        'Fail to Reindex pair 0.0.1 and foo 0.0.2';
    is $maint->exitval, 3, 'Exitval should reflect number of failures';
    $maint->exitval(0);
}

##############################################################################
# Test update_users().
USERS: {
    my $json = File::Spec->catfile($root, 'user', "$user.json");
    file_not_exists_ok $json, 'user.json should not exist';
    ok $maint->update_users, 'Update users';
    file_exists_ok $json, 'user.json should now exist';
    file_contents_like $json, qr{"nickname": "user",},
        'And it should look like user JSON';
}

##############################################################################
# Test _reset_message_template().
TEMPLATE: {
    # Start with default expires and no reason.
    my $msg = <<EOF;
Hello %s,

Your password has been disabled by an administrator Click the link below to
reset your PGXN password. But do it soon! This link will expire in 2 days:

  %s

Best,

PGXN Management
EOF
    is $maint->_reset_message_template, $msg, 'Should get default message';

    # Try with a custome expires and reason.
    ok $maint = $CLASS->new(
        expires => '1 week',
    ), "Create Maint with custom expires";
    $msg =~ s/2 days/1 week/;
    is $maint->_reset_message_template, $msg,
        'Should get message with custom expres';

    # Try with a custome expires and reason.
    ok $maint = $CLASS->new(
        expires => '1 week',
        reason  => 'You requested a reset',
    ), "Create Maint with custom expires and reason";
    is $maint->_reset_message_template, <<EOF, 'Should get message with custom expireas and reason';
Hello %s,

Your PGXN password has been disabled by an administrator because:

  You requested a reset

Click the link below to reset your PGXN password. But do it soon! This
link will expire in 1 week:

  %s

Best,

PGXN Management
EOF
}

##############################################################################
# Test reset_password().
RESET: {
    # Mock sending an email.
    my $mgr_mock = Test::MockModule->new('PGXN::Manager');
    my @email_params;
    $mgr_mock->mock(send_email => sub { push @email_params => $_[1] });

    # Mock the message template.
    my $maint_mock = Test::MockModule->new($CLASS);
    $maint_mock->mock(_reset_message_template => sub {
        my $self = shift;
        my $exp = $self->expires;
        my $msg = "user: %s\nurl: %s\nexpires: $exp";
        my $reason = $self->reason or return $msg;
        return $msg . "\nreason: $reason";
    });

    # Reset the password for a user.
    my $pgxn    = PGXN::Manager->instance;
    my $admin = TxnTest->admin;
    ok $maint = $CLASS->new(admin => $admin), "Create Maint for $admin";
    my $l = PGXN::Manager::Locale->get_handle;
    stdout_is { ok $maint->reset_password($user), "Reset $user password" }
        encode_utf8 "$user... " . $l->maketext('✅ Sent!') . "\n",
        "Output should show $user password reset";
    is $maint->exitval, 0, 'Exit value should be 0';
    is @email_params, 1, "Should have email params for $user";
    my $body = delete $email_params[0]->{body};
    is_deeply $email_params[0], {
        from    => $pgxn->config->{admin_email},
        to      => 'user@pgxn.org',
        subject => 'Reset Your PGXN Password',
    }, "Email should have been sent to $user";

    my $base_url = $maint->base_url;
    like $body, qr{\Auser: $user\nurl: $base_url/account/reset/\w+\nexpires: 2 days\z},
        "Should have sent email to the user";

    # Try an unknown user.
    @email_params = ();
    stdout_is { ok $maint->reset_password('nonesuch'), "Reset unknown user password" }
        encode_utf8 "nonesuch... " . $l->maketext("🚫 Error: Unknown nickname\n"),
        "Output should show unknown nickname";
    is $maint->exitval, 1, 'Exit value should be 1';
    is @email_params, 0, 'Should have no email params';

    # Try multiple users with a custom expires, reason, and base URL.
    $base_url = 'https://pgxn.example.com';
    my $expires = '10 days';
    my $reason = 'Because I said so';
    ok $maint = $CLASS->new(
        admin    => $admin,
        expires  => $expires,
        reason   => $reason,
        base_url => $base_url,
    ), "Create Maint for admin, expires, reason";

    stdout_is { ok $maint->reset_password($user, $admin), "Reset $user and $admin passwords" }
        encode_utf8 join("\n",
            "$user... "  . $l->maketext('✅ Sent!'),
            "$admin... " . $l->maketext('✅ Sent!'),
        ) . "\n",
        "Output should show $user and $admin password resets";
    is $maint->exitval, 0, 'Exit value should be 0';

    is @email_params, 2, "Should have sent two emails";
    $body = delete $email_params[0]->{body};
    is_deeply $email_params[0], {
        from    => $pgxn->config->{admin_email},
        to      => 'user@pgxn.org',
        subject => 'Reset Your PGXN Password',
    }, "Email should have been sent to $user";
    like $body, qr{\Auser: $user\nurl: $base_url/account/reset/\w+\nexpires: $expires\nreason: $reason\z},
        "Should have sent another email to $user";

    $body = delete $email_params[1]->{body};
    is_deeply $email_params[1], {
        from    => $pgxn->config->{admin_email},
        to      => 'admin@pgxn.org',
        subject => 'Reset Your PGXN Password',
    }, "Email should have been sent to $admin";
    like $body, qr{\Auser: $admin\nurl: $base_url/account/reset/\w+\nexpires: $expires\nreason: $reason\z},
        "Should have sent an email to $admin";

    # Try an email address.
    @email_params = ();
    stdout_is { ok $maint->reset_password('user@pgxn.org'), 'Reset user@pgxn.org password' }
        encode_utf8 'user@pgxn.org... ' . $l->maketext('✅ Sent!') . "\n",
        'Output should show user@pgxn.org password reset';
    is $maint->exitval, 0, 'Exit value should be 0';
    ok $email_params[0], 'Should have email params for user@pgxn.org';
    my $body = delete $email_params[0]->{body};
    is_deeply $email_params[0], {
        from    => $pgxn->config->{admin_email},
        to      => 'user@pgxn.org',
        subject => 'Reset Your PGXN Password',
    }, 'Email should have been sent to user@pgxn.org';
    like $body, qr{\Auser: user\@pgxn.org\nurl: $base_url/account/reset/\w+\nexpires: $expires\nreason: $reason\z},
        'Should have sent an email to user@pgxn.org';
}
