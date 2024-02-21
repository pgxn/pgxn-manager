use strict;
use warnings;
use Module::Build;

my $build_pkg = eval { require Module::Build::DB }
  ? 'Module::Build::DB' : 'Module::Build';

my $class = $build_pkg->subclass(
    class => 'PGXN::Build',
    code => q{
        sub valid_licenses { { postgresql => 'PostgreSQL' } }
        sub new {
            my $self = shift->SUPER::new(@_);
            if (my $meth = $self->can('db_super_user')) {
                $self->tap_harness_args->{sources}{pgTAP}{username}
                    ||= $self->$meth
            }

            # Add html files in lib.
            $self->add_build_element('html');
            return $self;
        }
        sub ACTION_tarball_name { print shift->dist_dir . ".tar.gz\n" }
        sub ACTION_latest_changes {
            my $self = shift;
            (my $dv = $self->dist_version) =~ s/^v//;
            open my $in, '<:raw', 'Changes' or die "Cannot open Changes: $!\n";
            open my $out, '>:raw', 'latest_changes.md' or die "Cannot open latest_changes.md: $!\n";
            while (<$in>) { last if /^\Q$dv\E\b/ }
            print {$out} "Changes for v$dv\n";
            while (<$in>) {
                last if /^\s*$/;
                chomp;
                if (s/^\s+-/-  /) {
                    print {$out} "\n";
                } else {
                    s/^\s+/ /;
                }
                print {$out} $_;
            }
            $self->add_to_cleanup('latest_changes.md');
        }
    },
);

$class->new(
    module_name        => 'PGXN::Manager',
    license            => 'postgresql',
    script_files       => 'bin',
    test_file_exts     => [qw(.t .pg)],
    db_config_key      => 'dbi',
    replace_config     => 'conf/test.json',
    db_client          => 'psql',
    db_super_user      => 'postgres',
    configure_requires => { 'Module::Build::DB' => '0.10', },
    build_requires     => {
        'Archive::Tar'                      => '1.68',
        'File::Copy'                        => '2.14',
        'HTTP::Request::Common'             => '5.824',
        'MIME::Base64'                      => '3.08',
        'Module::Build::DB'                 => '0.10',
        'Software::License'                 => '0.102340',
        'TAP::Parser::SourceHandler::pgTAP' => '3.23',
        'Test::File'                        => '1.29',
        'Test::File::Contents'              => '0.05',
        'Test::Exception'                   => '0.43',
        'Test::Harness'                     => '3.18',
        'Test::MockModule'                  => '0.05',
        'Test::More'                        => '0.70',
        'Test::Output'                      => '1.033',
        'Test::NoWarnings'                  => '1.02',
        'Test::XML'                         => '0.08',
        'Test::XPath'                       => '0.13',
    },
    requires => {
        'aliased'                           => '0.30',
        'Archive::Extract'                  => '0.88',
        'Archive::Tar'                      => '2.32',
        'Compress::Zlib'                    => '2.084',
        'IO::Uncompress::Bunzip2'           => '2.084',
        'IO::Uncompress::UnXz'              => '2.084',
        'IO::Zlib'                          => '1.10',
        'Archive::Zip'                      => '1.30',
        'Class::ISA'                        => '0.36',
        'Cwd'                               => '3.33',
        'Data::Dump'                        => '1.19',
        'Data::Validate::URI'               => '0.05',
        'DBD::Pg'                           => '2.15.1',
        'DBI'                               => '1.608',
        'DBIx::Connector'                   => '0.42',
        'Digest::SHA1'                      => '2.13',
        'Email::Valid'                      => '0.184',
        'Email::MIME::Creator'              => '1.905',
        'Email::Sender::Simple'             => '0.102370',
        'Email::Address'                    => '1.892',
        'Encode'                            => '2.40',
        'Encode::Locale'                    => '1.05',
        'Exception::Class::DBI'             => '1.00',
        'Fcntl'                             => 0,
        'File::Basename'                    => '2.77',
        'File::Copy'                        => '2.14',
        'File::Path'                        => '2.08',
        'File::Spec'                        => '3.33',
        'File::Temp'                        => '0.22',
        'Getopt::Long'                      => '2.34',
        'HTTP::Body'                        => '1.08',
        'HTML::Entities'                    => '3.68',
        'HTTP::Negotiate'                   => '5.835',
        'I18N::LangTags::Detect'            => '1.03',
        'IO::File'                          => 0,
        'JSON::XS'                          => '2.3',
        'Locale::Maketext'                  => '1.13',
        'LWP::Protocol::https'              => 0,
        'LWP::UserAgent'                    => 0,
        'Moose'                             => '1.15',
        'MooseX::Singleton'                 => '0.25',
        'Moose::Util::TypeConstraints'      => '1.15',
        'namespace::autoclean'              => '0.11',
        'Net::Twitter::Lite::WithAPIv1_1'   => '0.12000',
        'parent'                            => '0.223',
        'perl'                              => 5.010,
        'PGXN::Meta::Validator'             => '0.14.0',
        'Plack'                             => '1.0040',
        'Plack::Builder'                    => 0,
        'Plack::App::File'                  => 0,
        'Plack::Request'                    => '1.0040',
        'Plack::Response'                   => '1.0040',
        'Plack::Session::Store::File'       => '0.12',
        'Plack::Middleware::Session'        => '0.12',
        'Plack::Middleware::MethodOverride' => '0.10',
        'Proc::Daemon'                      => 0,
        'Pod::Usage'                        => '1.33',
        'POSIX'                             => 0,
        'namespace::autoclean'              => '0.11',
        'Router::Resource'                  => '0.11',
        'SemVer'                            => '0.10.0',
        'Template::Declare'                 => '0.43',
        'Template::Declare::Tags'           => '0.43',
        'Time::HiRes'                       => 0,
        'Try::Tiny'                         => '0.06',
        'URI::Template'                     => '0.15',
    },
    recommends => {
        'Plack::Middleware::Debug'        => '0.12',
        'Plack::Middleware::ReverseProxy' => '0.07',
        'Test::Pod'                       => '1.41',
        'Test::Pod::Coverage'             => '1.06',
    },
    tap_harness_args => {
        sources => {
            Perl  => undef,
            pgTAP => {
                dbname   => 'pgxn_manager_test',
                suffix   => '.pg',
            },
        },
    },
    meta_merge => {
        resources => {
            homepage   => 'https://manager.pgxn.org/',
            bugtracker => 'https://github.com/pgxn/pgxn-manager/issues/',
            repository => 'https://github.com/pgxn/pgxn-manager/',
        }
    },
)->create_build_script;
