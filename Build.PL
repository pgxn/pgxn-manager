use strict;
use warnings;
use Module::Build::DB;

Module::Build::DB->new(
    module_name        => 'PGXN::Manager',
    license            => 'perl',
    script_files       => 'bin',
    test_file_exts     => [qw(.t .pg)],
    db_config_key      => 'dbi',
    replace_config     => 'conf/test.json',
    db_client          => 'psql',
    configure_requires => { 'Module::Build::DB' => '0.10', },
    build_requires     => {
        'HTTP::Request::Common'             => '5.824',
        'Module::Build::DB'                 => '0.10',
        'TAP::Parser::SourceHandler::pgTAP' => '3.23',
        'Test::File'                        => '1.29',
        'Test::File::Contents'              => '0.05',
        'Test::Harness'                     => '3.18',
        'Test::MockModule'                  => '0.05',
        'Test::More'                        => '0.70',
        'Test::XPath'                       => '0.13',
    },
    requires => {
        'aliased'                    => '0.30',
        'Data::Validate::URI'        => '0.05',
        'DBD::Pg'                    => '2.15.1',
        'DBI'                        => '1.608',
        'DBIx::Connector'            => '0.20',
        'Email::Valid'               => '0.184',
        'Exception::Class::DBI'      => '1.00',
        'JSON::XS'                   => '2.3',
        'Moose'                      => '1.12',
        'MooseX::Singleton'          => '0.25',
        'perl'                       => 5.012,
        'Plack'                      => '0.9946',
        'namespace::autoclean'       => '0.11',
        'Router::Simple::Sinatraish' => '0.02',
        'Template::Declare'          => '0.43',
    },
    recommends => {
        'Test::Pod'           => '1.20',
        'Test::Pod::Coverage' => '1.06',
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
    meta_merge => {
        resources => {
            homepage   => 'http://manage.pgxn.org/',
            bugtracker => 'http://github.com/theory/pgxn-manager/issues/',
            repository => 'http://github.com/theory/pgxn-manager/tree/',
        }
    },
)->create_build_script;
