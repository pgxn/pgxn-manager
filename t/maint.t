#!/usr/bin/env perl -w

use 5.12.0;
use utf8;
use Test::More tests => 20;
#use Test::More 'no_plan';
use Test::File;
use File::Path qw(remove_tree);
use Test::MockModule;

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
    _write_json_to
    DEMOLISH
    _pod2usage
    _config
);

my $tmpdir = File::Spec->catdir(File::Spec->tmpdir, 'pgxn');
my $root   = PGXN::Manager->new->config->{mirror_root};

END {
    remove_tree $tmpdir, $root;
}

##############################################################################
# Instantiate and test config.
my $maint = new_ok $CLASS;
my %defopts = (
    help      => undef,
    man       => undef,
    verbosity => 0,
    version   => undef,
);

DEFAULT: {
    local @ARGV;
    is_deeply { $maint->_config }, \%defopts,
        'Default options should be correct';
}


##############################################################################
# Test run().
RUN: {
    my $mocker = Test::MockModule->new($CLASS);
    my $params;
    $mocker->mock(update_stats => sub { shift; $params = \@_ });
    ok $maint->run('update_stats'), 'Run update_stats';
    is_deeply $params, [], 'Should have called update_stats method';

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
    $mocker->mock(run => sub { shift; $params = \@_ });
    local @ARGV = qw(--verbose update_stats now);
    ok $maint->go, 'Go!';
    is_deeply $params, [qw(update_stats now)],
        'Should have called run with command and args';
};



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
