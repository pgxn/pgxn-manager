#!/usr/bin/env perl -w

use 5.10.0;
use utf8;
use Test::More tests => 295;
#use Test::More 'no_plan';
use Plack::Test;
use HTTP::Request::Common;
use PGXN::Manager;
use PGXN::Manager::Router;
use PGXN::Manager::Distribution;
use HTTP::Message::PSGI;
use File::Path qw(remove_tree);
use Test::XML;
use Test::XPath;
use JSON::XS;
use Archive::Zip qw(:ERROR_CODES);
use MIME::Base64;
use lib 't/lib';
use TxnTest;
use XPathTest;

my $app      = PGXN::Manager::Router->app;
my $mt       = PGXN::Manager::Locale->accept('en');
my $uri      = '/distributions';
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
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb  = shift;
    my $req = GET $uri, Authorization => 'Basic ' . encode_base64("$user:****");

    ok my $res = $cb->($req), "Get $uri with auth token";
    ok $res->is_success, 'Response should be success';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($req));
    $req->env->{REMOTE_USER} = $user;
    XPathTest->test_basics($tx, $req, $mt, {
        h1 => 'Your Distributions',
        page_title => 'Your distributions',
    });

    $tx->ok('/html/body/div[@id="content"]', 'Look at the content', sub {
        $tx->is('count(./*)', 2, '... Should have two subelements');
        $tx->ok('./table[@id="distlist"]', '... Test distlist table', sub {
            $tx->is(
                './@summary',
                $mt->maketext('List of distributions owned by [_1]', $user),
                '...... Summary should be correct'
            );
            $tx->is('count(./*)', 2, '...... Should have two subelements');
            $tx->ok('./thead', '...... Test thead', sub {
                $tx->is('count(./*)', 1, '......... Should have one subelement');
                $tx->ok('./tr', '......... Should be a row', sub {
                    $tx->is('count(./*)', 3, '............ Should have three subelements');
                    $tx->is('count(./th)', 3, '........... All should be th');
                    $tx->ok('./th[1]', '............ Test first th', sub {
                        $tx->is('./@scope', 'col', '............... Should be row scope');
                        $tx->is('./@class', 'nobg', '............... Should be class nobg');
                        $tx->is(
                            './text()',
                            $mt->maketext('Distributions'),
                            '............... Should be "Distributions" th'
                        );
                    });
                    $tx->ok('./th[2]', '............ Test second th', sub {
                        $tx->is('./@scope', 'col', '............... Should be row scope');
                        $tx->is(
                            './text()',
                            $mt->maketext('Status'),
                            '............... Should be "Status" th'
                        );
                    });
                    $tx->ok('./th[3]', '............ Test third th', sub {
                        $tx->is('./@scope', 'col', '............... Should be row scope');
                        $tx->is(
                            './text()',
                            $mt->maketext('Released'),
                            '............... Should be "Released" th'
                        );
                    });
                });
            });
            $tx->ok('./tbody', '...... Test tbody', sub {
                $tx->is('count(./*)', 1, '......... Should have one subelement');
                $tx->ok('./tr', '......... Should be a row', sub {
                    $tx->is('./@class', 'spec', '............ Should "spec" class');
                    $tx->is('count(./*)', 1, '............ Should have one subelement');
                    $tx->ok('./td[@colspan="3"]', '............ Test single row', sub {
                        my $msg = quotemeta $mt->maketext(
                            q{You haven't uploaded a distribution yet.}
                        );
                        $tx->like(
                            './text()',
                            qr/$msg/,
                            '............... Should have empty list message'
                        );
                        $tx->is(
                            './a[@id="iupload"]',
                            $mt->maketext('Release one now!'),
                            '............... And should have upload link',
                        );
                    });
                });
            });
        });
    });
};

##############################################################################
# Okay, let's upload a couple of distributions, eh?
my $tmpdir     = File::Spec->catdir(File::Spec->tmpdir, 'pgxn');
my $root       = PGXN::Manager->new->config->{mirror_root};
my $distdir    = File::Spec->catdir(qw(t dist widget));
my $distzip    = File::Spec->catdir(qw(t dist widget-0.2.5.zip));

# First, create a distribution.
my $dzip = Archive::Zip->new;
$dzip->addTree($distdir, 'widget-0.2.5') == AZ_OK or die 'tree error';
$dzip->writeToFileNamed($distzip) == AZ_OK or die 'write error';

END {
    unlink $distzip;
    remove_tree $tmpdir, $root;
}

ok my $dist = PGXN::Manager::Distribution->new(
    creator  => TxnTest->user,
    archive  => $distzip,
    basename => 'widget-0.2.5.zip',
), 'Create a widget-0.2.5 distribution';
ok $dist->process, 'Process the widget-0.2.5 distribution';

# Create another one, widget-0.2.6.'
my $meta = $dist->distmeta;
$meta->{version} = '0.2.6';
$meta->{release_status} = 'testing';
$dzip->memberNamed('widget-0.2.5/META.json')->contents(encode_json $meta);
$dzip->writeToFileNamed($distzip) == AZ_OK or die 'write error';

ok $dist = PGXN::Manager::Distribution->new(
    creator  => TxnTest->user,
    archive  => $distzip,
    basename => 'widget-0.2.6.zip',
), 'Create a widget-0.2.6 distribution';
ok $dist->process, 'Process the widget-0.2.6 distribution';

# Now one called pair.
$meta->{name} = 'pair';
$meta->{version} = '1.3.0';
delete $meta->{release_status};
$dzip->memberNamed('widget-0.2.5/META.json')->contents(encode_json $meta);
$dzip->writeToFileNamed($distzip) == AZ_OK or die 'write error';

ok $dist = PGXN::Manager::Distribution->new(
    creator  => TxnTest->user,
    archive  => $distzip,
    basename => 'pair-1.3.0.zip',
), 'Create a pair-1.3.0 distribution';
ok $dist->process, 'Process the pair-1.3.0 distribution';

# And finally, create one for the admin user.
$meta->{name} = 'pgTAP';
$meta->{version} = '0.35.0';
$meta->{provides} = { 'pgtap' => { file => 'sql/pgtap.sql', version => '0.35.0' } };
$dzip->memberNamed('widget-0.2.5/META.json')->contents(encode_json $meta);
$dzip->writeToFileNamed($distzip) == AZ_OK or die 'write error';

ok $dist = PGXN::Manager::Distribution->new(
    creator  => TxnTest->admin,
    archive  => $distzip,
    basename => 'pgTAP-0.35.0.zip',
), 'Create a pgTAP-0.35.0 distribution for admin';
ok $dist->process, 'Process the pgTAP-0.35.0 distribution' or diag $dist->localized_error;

##################################################################################
# Okay, now have the user fetch the list again.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb  = shift;
    my $req = GET $uri, Authorization => 'Basic ' . encode_base64("$user:****");

    ok my $res = $cb->($req), "Get $uri with auth token";
    ok $res->is_success, 'Response should be success';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($req));
    $req->env->{REMOTE_USER} = $user;
    XPathTest->test_basics($tx, $req, $mt, {
        h1 => 'Your Distributions',
        page_title => 'Your distributions',
    });

    $tx->ok('/html/body/div[@id="content"]', 'Look at the content', sub {
        $tx->is('count(./*)', 2, '... Should have two subelements');
        $tx->ok('./table[@id="distlist"]', '... Test distlist table', sub {
            $tx->is(
                './@summary',
                $mt->maketext('List of distributions owned by [_1]', $user),
                '...... Summary should be correct'
            );
            $tx->is('count(./*)', 2, '...... Should have two subelements');
            $tx->ok('./thead', '...... Test thead', sub {
                $tx->is('count(./*)', 1, '......... Should have one subelement');
                $tx->ok('./tr', '......... Should be a row', sub {
                    $tx->is('count(./*)', 3, '............ Should have three subelements');
                    $tx->is('count(./th)', 3, '........... All should be th');
                    $tx->ok('./th[1]', '............ Test first th', sub {
                        $tx->is('./@scope', 'col', '............... Should be row scope');
                        $tx->is('./@class', 'nobg', '............... Should be class nobg');
                        $tx->is(
                            './text()',
                            $mt->maketext('Distributions'),
                            '............... Should be "Distributions" th'
                        );
                    });
                    $tx->ok('./th[2]', '............ Test second th', sub {
                        $tx->is('./@scope', 'col', '............... Should be row scope');
                        $tx->is(
                            './text()',
                            $mt->maketext('Status'),
                            '............... Should be "Status" th'
                        );
                    });
                    $tx->ok('./th[3]', '............ Test third th', sub {
                        $tx->is('./@scope', 'col', '............... Should be row scope');
                        $tx->is(
                            './text()',
                            $mt->maketext('Released'),
                            '............... Should be "Released" th'
                        );
                    });
                });
            });
            $tx->ok('./tbody', '...... Test tbody', sub {
                $tx->is('count(./*)', 3, '......... Should have three subelements');
                $tx->is('count(./tr)', 3, '......... All three should be tr');
                $tx->ok('./tr[1]', '......... Test first tr', sub {
                    $tx->is('./@class', 'spec', '............ Class should be "spec"');
                    $tx->is('count(./*)', 3, '............ Should have three subelements');
                    $tx->ok('./th[@scope="row"]', '............ Test th', sub {
                        $tx->is('count(./*)', 1, '............... Should have 1 subelement');
                        $tx->ok('./a[@class="show"]', '............... Test anchor', sub {
                            $tx->is(
                                './@title',
                                $mt->maketext(q{See [_1]'s details}, 'pair-1.3.0'),
                                '.................. Should have link title'
                            );
                            $tx->is(
                                './@href',
                                $req->uri_for('/distributions/pair/1.3.0'),
                                '.................. Should have href'
                            );
                            $tx->is(
                                './img/@src',
                                $req->uri_for('/ui/img/play.svg'),
                                'It should have an image link'
                            );
                            $tx->like(
                                './text()',
                                qr/\Qpair-1.3.0/,
                                'Should have link text'
                            )
                        });
                    });
                    $tx->is(
                        './td[1]',
                        $mt->maketext('stable'),
                        'Should have status in second cell'
                    );
                    $tx->like(
                        './td[2]',
                        qr/^\d{4}-\d\d-\d\d$/,
                        'Should have date in third cell'
                    );
                });
                $tx->ok('./tr[2]', '......... Test second tr', sub {
                    $tx->is('./@class', 'specalt', '............ Class should be "specalt"');
                    $tx->is('count(./*)', 3, '............ Should have three subelements');
                    $tx->ok('./th[@scope="row"]', '............ Test th', sub {
                        $tx->is('count(./*)', 1, '............... Should have 1 subelement');
                        $tx->ok('./a[@class="show"]', '............... Test anchor', sub {
                            $tx->is(
                                './@title',
                                $mt->maketext(q{See [_1]'s details}, 'widget-0.2.5'),
                                '.................. Should have link title'
                            );
                            $tx->is(
                                './@href',
                                $req->uri_for('/distributions/widget/0.2.5'),
                                '.................. Should have href'
                            );
                            $tx->is(
                                './img/@src',
                                $req->uri_for('/ui/img/play.svg'),
                                'It should have an image link'
                            );
                            $tx->like(
                                './text()',
                                qr/\Qwidget-0.2.5/,
                                'Should have link text'
                            )
                        });
                    });
                    $tx->is(
                        './td[1]',
                        $mt->maketext('stable'),
                        'Should have status in second cell'
                    );
                    $tx->like(
                        './td[2]',
                        qr/^\d{4}-\d\d-\d\d$/,
                        'Should have date in third cell'
                    );
                });
                $tx->ok('./tr[3]', '......... Test third tr', sub {
                    $tx->is('./@class', 'spec', '............ Class should be "spec"');
                    $tx->is('count(./*)', 3, '............ Should have three subelements');
                    $tx->ok('./th[@scope="row"]', '............ Test th', sub {
                        $tx->is('count(./*)', 1, '............... Should have 1 subelement');
                        $tx->ok('./a[@class="show"]', '............... Test anchor', sub {
                            $tx->is(
                                './@title',
                                $mt->maketext(q{See [_1]'s details}, 'widget-0.2.6'),
                                '.................. Should have link title'
                            );
                            $tx->is(
                                './@href',
                                $req->uri_for('/distributions/widget/0.2.6'),
                                '.................. Should have href'
                            );
                            $tx->is(
                                './img/@src',
                                $req->uri_for('/ui/img/play.svg'),
                                'It should have an image link'
                            );
                            $tx->like(
                                './text()',
                                qr/\Qwidget-0.2.6/,
                                'Should have link text'
                            )
                        });
                    });
                    $tx->is(
                        './td[1]',
                        $mt->maketext('testing'),
                        'Should have status in second cell'
                    );
                    $tx->like(
                        './td[2]',
                        qr/^\d{4}-\d\d-\d\d$/,
                        'Should have date in third cell'
                    );
                });
            });
        });
    });
};

##################################################################################
# Great! Now have a look at admin's distributions.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb  = shift;
    my $req = GET $uri, Authorization => 'Basic ' . encode_base64("$admin:****");

    ok my $res = $cb->($req), "Get $uri with auth token";
    ok $res->is_success, 'Response should be success';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($req));
    $req->env->{REMOTE_USER} = $admin;
    XPathTest->test_basics($tx, $req, $mt, {
        h1 => 'Your Distributions',
        page_title => 'Your distributions',
    });

    $tx->ok('/html/body/div[@id="content"]', 'Look at the content', sub {
        $tx->is('count(./*)', 2, '... Should have two subelements');
        $tx->ok('./table[@id="distlist"]', '... Test distlist table', sub {
            $tx->is(
                './@summary',
                $mt->maketext('List of distributions owned by [_1]', $admin),
                '...... Summary should be correct'
            );
            $tx->is('count(./*)', 2, '...... Should have two subelements');
            $tx->ok('./thead', '...... Test thead', sub {
                $tx->is('count(./*)', 1, '......... Should have one subelement');
                $tx->ok('./tr', '......... Should be a row', sub {
                    $tx->is('count(./*)', 3, '............ Should have three subelements');
                    $tx->is('count(./th)', 3, '........... All should be th');
                    $tx->ok('./th[1]', '............ Test first th', sub {
                        $tx->is('./@scope', 'col', '............... Should be row scope');
                        $tx->is('./@class', 'nobg', '............... Should be class nobg');
                        $tx->is(
                            './text()',
                            $mt->maketext('Distributions'),
                            '............... Should be "Distributions" th'
                        );
                    });
                    $tx->ok('./th[2]', '............ Test second th', sub {
                        $tx->is('./@scope', 'col', '............... Should be row scope');
                        $tx->is(
                            './text()',
                            $mt->maketext('Status'),
                            '............... Should be "Status" th'
                        );
                    });
                    $tx->ok('./th[3]', '............ Test third th', sub {
                        $tx->is('./@scope', 'col', '............... Should be row scope');
                        $tx->is(
                            './text()',
                            $mt->maketext('Released'),
                            '............... Should be "Released" th'
                        );
                    });
                });
            });
            $tx->ok('./tbody', '...... Test tbody', sub {
                $tx->is('count(./*)', 1, '......... Should have one subelement');
                $tx->ok('./tr', '......... Should be a row', sub {
                    $tx->is('./@class', 'spec', '............ Class should be "spec"');
                    $tx->is('count(./*)', 3, '............ Should have three subelements');
                    $tx->ok('./th[@scope="row"]', '............ Test th', sub {
                        $tx->is('count(./*)', 1, '............... Should have 1 subelement');
                        $tx->ok('./a[@class="show"]', '............... Test anchor', sub {
                            $tx->is(
                                './@title',
                                $mt->maketext(q{See [_1]'s details}, 'pgTAP-0.35.0'),
                                '.................. Should have link title'
                            );
                            $tx->is(
                                './@href',
                                $req->uri_for('/distributions/pgTAP/0.35.0'),
                                '.................. Should have href'
                            );
                            $tx->is(
                                './img/@src',
                                $req->uri_for('/ui/img/play.svg'),
                                'It should have an image link'
                            );
                            $tx->like(
                                './text()',
                                qr/\QpgTAP-0.35.0/,
                                'Should have link text'
                            )
                        });
                    });
                    $tx->is(
                        './td[1]',
                        $mt->maketext('stable'),
                        'Should have status in second cell'
                    );
                    $tx->like(
                        './td[2]',
                        qr/^\d{4}-\d\d-\d\d$/,
                        'Should have date in third cell'
                    );
                });
            });
        });
    });
};
