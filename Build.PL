use strict;
use warnings;
use Module::Build::DB;

Module::Build::DB->new(
    module_name        => 'PGXN::Manager',
    license            => 'perl',
#   script_files       => 'bin',
    test_file_exts     => [qw(.t .pg)],
    db_config_key      => 'dbi',
    replace_config     => 'conf/dev.yml',
    db_client          => 'psql',
    configure_requires => {
        'Module::Build::DB' => '0.10',
    },
    build_requires     => {
        'Module::Build::DB' => '0.10',
        'Test::More'        => '0.70',
        'Test::Harness'     => '3.18',
    },
    requires           => {
        'Data::Validate::URI' => '0.05',
        'DBD::Pg'             => '2.15.1',
        'DBI'                 => '1.608',
        'DBIx::Connector'     => '0.20',
        'Email::Valid'        => '0.184',
        'perl'                => 5.012,
    },
    recommends         => {
        'Test::Pod'              => '1.20',
        'Test::Pod::Coverage'    => '1.06',
    },
    tap_harness_args => {
        sources => {
            Perl  => undef,
            pgTAP => {
                dbname   => 'pgxn_manager_test',
                username => 'postgres',
                suffix   => '.pg',
            },
        },
    },
    meta_merge         => {
        resources => {
            homepage    => 'http://manage.pgxn.org/',
            bugtracker  => 'http://github.com/theory/pgxn-manager/issues/',
            repository  => 'http://github.com/theory/pgxn-manager/tree/',
        }
    },
)->create_build_script;
