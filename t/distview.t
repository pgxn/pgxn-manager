#!/usr/bin/env perl -w

use 5.12.0;
use utf8;
use Test::More tests => 240;
#use Test::More 'no_plan';
use Test::MockModule;
use Plack::Test;
use HTTP::Request::Common;
use PGXN::Manager;
use PGXN::Manager::Router;
use HTTP::Message::PSGI;
use Test::XML;
use Test::XPath;
use JSON::XS;
use Archive::Zip qw(:ERROR_CODES);
use File::Path qw(remove_tree);
use MIME::Base64;
use lib 't/lib';
use TxnTest;
use XPathTest;

my $app      = PGXN::Manager::Router->app;
my $mt       = PGXN::Manager::Locale->accept('en');
my $uri      = '/auth/distributions/widget/0.2.5';
my $user     = TxnTest->user;
my $admin    = TxnTest->admin;

# Connect without authenticating.
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET $uri), "GET $uri";
    is $res->code, 401, 'Should get 401 response';
    like $res->content, qr/Authorization required/,
        'The body should indicate need for authentication';
};

# Connect as authenticated user.
test_psgi $app => sub {
    my $cb  = shift;
    my $req = GET $uri, Authorization => 'Basic ' . encode_base64("$user:****");

    ok my $res = $cb->($req), "Get $uri with auth token";
    ok !$res->is_success, 'Response should not be success';
    is $res->code, 404, 'Response code should be 404';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
};

##############################################################################
# Okay, let's upload a couple of distributions, eh?
my $tmpdir     = File::Spec->catdir(File::Spec->tmpdir, 'pgxn');
my $root       = PGXN::Manager->new->config->{mirror_root};
my $distdir    = File::Spec->catdir(qw(t dist widget));
my $distzip    = File::Spec->catdir(qw(t dist widget-0.2.5.pgz));

# First, create a distribution.
my $dzip = Archive::Zip->new;
$dzip->addTree($distdir, 'widget-0.2.5') == AZ_OK or die 'tree error';
$dzip->writeToFileNamed($distzip) == AZ_OK or die 'write error';

END {
    unlink $distzip;
    remove_tree $tmpdir, $root;
}

ok my $dist = PGXN::Manager::Distribution->new(
    owner    => TxnTest->user,
    archive  => $distzip,
    basename => 'widget-0.2.5.pgz',
), 'Create a widget-0.2.5 distribution';
ok $dist->process, 'Process the widget-0.2.5 distribution';
my $sha1 = $dist->sha1;

# Create another one, widget-0.2.6, with no README'
my $meta = $dist->distmeta;
$meta->{version} = '0.2.6';
$meta->{release_status} = 'testing';
$dzip->memberNamed('widget-0.2.5/META.json')->contents(encode_json $meta);
$dzip->removeMember('widget-0.2.5/README');
$dzip->writeToFileNamed($distzip) == AZ_OK or die 'write error';

ok $dist = PGXN::Manager::Distribution->new(
    owner    => TxnTest->user,
    archive  => $distzip,
    basename => 'widget-0.2.6.pgz',
), 'Create a widget-0.2.6 distribution';
ok $dist->process, 'Process the widget-0.2.6 distribution';

# And finally, create one for the admin user.
$meta->{name} = 'pgTAP';
$meta->{version} = '0.35.0';
$meta->{provides} = { 'pgtap' => { version => '0.35.0' } };
$dzip->memberNamed('widget-0.2.5/META.json')->contents(encode_json $meta);
$dzip->writeToFileNamed($distzip) == AZ_OK or die 'write error';

ok $dist = PGXN::Manager::Distribution->new(
    owner    => TxnTest->admin,
    archive  => $distzip,
    basename => 'pgTAP-0.35.0.pgz',
), 'Create a pgTAP-0.35.0 distribution for admin';
ok $dist->process, 'Process the pgTAP-0.35.0 distribution';

##################################################################################
# Okay, now have the user fetch her distribution.
test_psgi $app => sub {
    my $cb  = shift;
    my $req = GET $uri, Authorization => 'Basic ' . encode_base64("$user:****");

    ok my $res = $cb->($req), "Get existing $uri with auth token";
    ok $res->is_success, 'Response should be success';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($req));
    $req->env->{REMOTE_USER} = $user;
    $req->env->{SCRIPT_NAME} = '/auth';
    XPathTest->test_basics($tx, $req, $mt, {
        h1 => 'widget-0.2.5',
        page_title => 'widget-0.2.5',
    });

    # Validate the content.
    $tx->ok('/html/body/div[@id="content"]', 'Look at the content', sub {
        $tx->is('count(./*)', 4, '... Should have four subelements');
        $tx->is(
            './p[@class="abstract"]',
            'Widget for PostgreSQL',
            '... Should have abstract'
        );
        $tx->ok('./ul[@id="distlinks"]', '... Test distlinks list', sub {
            $tx->is('count(./*)', 3, '...... Should have three subelements');
            $tx->is('count(./li)', 3, '...... All list items');
            $tx->ok('./li[1]', '......... Test first item', sub {
                $tx->is('count(./*)', 1, '......... Should have one subelement');
                $tx->ok('./a', '......... Test link', sub {
                    $tx->is(
                        './@href',
                        'http://localhost/mirror/dist/widget/widget-0.2.5.pgz',
                        '............ Should link to archive'
                    );
                    $tx->is(
                        './@title',
                        $mt->maketext('Download [_1].', 'widget-0.2.5'),
                        '............ Should have link title'
                    );
                    $tx->is('count(./*)', 2, '............ Should have two subelements');
                    $tx->is(
                        './img/@src',
                        $req->uri_for('/ui/img/download.png'),
                        'Should have download image'
                    );
                    $tx->is(
                        './span',
                        $mt->maketext('Archive'),
                        'Should have "Archive" text'
                    );
                });
            });
            $tx->ok('./li[2]', '......... Test second item', sub {
                $tx->is('count(./*)', 1, '......... Should have one subelement');
                $tx->ok('./a', '......... Test link', sub {
                    $tx->is(
                        './@href',
                        'http://localhost/mirror/dist/widget/widget-0.2.5.readme',
                        '............ Should link to readme'
                    );
                    $tx->is(
                        './@title',
                        $mt->maketext('Download the [_1] README.', 'widget-0.2.5'),
                        '............ Should have link title'
                    );
                    $tx->is('count(./*)', 2, '............ Should have two subelements');
                    $tx->is(
                        './img/@src',
                        $req->uri_for('/ui/img/warning.png'),
                        'Should have warning image'
                    );
                    $tx->is(
                        './span',
                        $mt->maketext('README'),
                        'Should have "README" text'
                    );
                });
            });
            $tx->ok('./li[3]', '......... Test third item', sub {
                $tx->is('count(./*)', 1, '......... Should have one subelement');
                $tx->ok('./a', '......... Test link', sub {
                    $tx->is(
                        './@href',
                        'http://localhost/mirror/dist/widget/widget-0.2.5.json',
                        '............ Should link to JSON metadata file'
                    );
                    $tx->is(
                        './@title',
                        $mt->maketext('Download the [_1] Metadata.', 'widget-0.2.5'),
                        '............ Should have link title'
                    );
                    $tx->is('count(./*)', 2, '............ Should have two subelements');
                    $tx->is(
                        './img/@src',
                        $req->uri_for('/ui/img/info.png'),
                        'Should have info image'
                    );
                    $tx->is(
                        './span',
                        $mt->maketext('Metadata'),
                        'Should have "Metadata" text'
                    );
                });
            });
        });
        $tx->ok('./dl', '... Test definition list', sub {
            $tx->is('count(./*)', 12, '...... Should have 12 subelements');
            # Check simple key/value pairs.
            my $i;
            for my $spec (
                [ Description => 'A widget is just thing thing, you know' ],
                [ Owner       => $user ],
                [ Status      => 'stable' ],
                [ SHA1        => $sha1 ],
                [ Extensions  => undef ], # see below
                [ Tags        => undef ], # see below
            ) {
                $i++;
                $tx->is(
                    "./dt[$i]",
                    $mt->maketext($spec->[0]),
                    qq{...... Should have "$spec->[0]" dt}
                );
                $tx->is(
                    "./dd[$i]/p",
                    $spec->[1],
                    qq{...... Should have "$spec->[0]" dd}
                ) if $spec->[1];
            }

            # Have a look at the extensions list.
            $tx->ok('./dd[5]/ul', '...... Test extensions list', sub {
                $tx->is('count(./*)', 1, '...... Should have 1 subelement');
                $tx->is('./li/p', 'widget 0.2.5', 'It should list the extension');
            });

            # Have a look at the tags list.
            $tx->ok('./dd[6]/ul', '...... Test tags list', sub {
                $tx->is('count(./*)', 3, '...... Should have 3 subelements');
                my $i = 0;
                for my $tag ('full text search', 'gadget', 'widget') {
                    $i++;
                    $tx->is("./li[$i]", $tag, qq{Item $i should be "$tag"});
                }
            });
        });
    });
};

# Try getting the one without a README.
$uri = '/auth/distributions/widget/0.2.6';

test_psgi $app => sub {
    my $cb  = shift;
    my $req = GET $uri, Authorization => 'Basic ' . encode_base64("$user:****");

    ok my $res = $cb->($req), "Get $uri";
    ok $res->is_success, 'Response should be success';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($req));
    $req->env->{REMOTE_USER} = $user;
    $req->env->{SCRIPT_NAME} = '/auth';
    XPathTest->test_basics($tx, $req, $mt, {
        h1 => 'widget-0.2.6 (testing)',
        page_title => 'widget-0.2.6 (testing)',
    });

    # Validate the content.
    $tx->ok('/html/body/div[@id="content"]', 'Look at the content', sub {
        $tx->ok('./ul[@id="distlinks"]', '... Test distlinks list', sub {
            $tx->is('count(./*)', 2, '...... Should have two subelements');
            $tx->is('count(./li)', 2, '...... All list items');
            $tx->is(
                './li[1]/a/@href',
                'http://localhost/mirror/dist/widget/widget-0.2.6.pgz',
                '......... First should be the archive link'
            );
            $tx->is(
                './li[2]/a/@href',
                'http://localhost/mirror/dist/widget/widget-0.2.6.json',
                '......... Second should be the meta link'
            );
        });
    });
};

# Connect as user without permission.
test_psgi $app => sub {
    my $cb  = shift;
    my $req = GET $uri, Authorization => 'Basic ' . encode_base64("$admin:****");

    ok my $res = $cb->($req), "Get $uri as another user";
    ok !$res->is_success, 'Response should not be success';
    is $res->code, 403, 'Response code should be 403';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
};

# Should be able to fetch own distribution though.
$uri = '/auth/distributions/pgTAP/0.35.0';
test_psgi $app => sub {
    my $cb  = shift;
    my $req = GET $uri, Authorization => 'Basic ' . encode_base64("$admin:****");

    ok my $res = $cb->($req), "Get $uri";
    ok $res->is_success, 'Response should be success';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
};

# Mock success.
my $mreq = Test::MockModule->new('PGXN::Manager::Request');
$mreq->mock( session => { success => 1 });

test_psgi $app => sub {
    my $cb  = shift;
    my $req = GET $uri, Authorization => 'Basic ' . encode_base64("$admin:****");

    ok my $res = $cb->($req), "Get $uri with success";
    ok $res->is_success, 'Response should be success';

    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($req));
    $req->env->{REMOTE_USER} = $admin;
    $req->env->{SCRIPT_NAME} = '/auth';
    XPathTest->test_basics($tx, $req, $mt, {
        h1 => 'pgTAP-0.35.0 (testing)',
        page_title => 'pgTAP-0.35.0 (testing)',
    });

    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    $tx->ok('/html/body/div[@id="content"]', 'Look at the content', sub {
        $tx->is('count(./*)', 5, '... Should have 5 subelements');
        $tx->ok('./p[@class="success dist"]', '... Test success message', sub {
            $tx->is(
                './text()',
                $mt->maketext('Congratulations! This distribution has been released on PGXN.'),
                'Should have the proper message'
            );
        });
    });
};
