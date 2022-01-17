#!/usr/bin/env perl -w

use v5.10;
use strict;
use warnings;
use utf8;

use Test::More tests => 470;
# use Test::More 'no_plan';
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

my $app   = PGXN::Manager::Router->app;
my $mt    = PGXN::Manager::Locale->accept('en');
my $uri   = '/permissions';
my $user  = TxnTest->user;
my $admin = TxnTest->admin;

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
    my $req = GET $uri, Authorization => 'Basic ' . encode_base64("$user:test-passW0rd");

    ok my $res = $cb->($req), "Get $uri with auth token";
    ok $res->is_success, 'Response should be success';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($req));
    $req->env->{REMOTE_USER} = $user;
    XPathTest->test_basics($tx, $req, $mt, {
        h1 => 'View Permissions',
        page_title => 'View permissions',
    });

    $tx->ok('/html/body/div[@id="content"]', 'Look at the content', sub {
        $tx->is('count(./*)', 2, '... Should have two subelements');
        $tx->ok('./table[@id="privlist"]', '... Test privlist table', sub {
            $tx->is(
                './@summary',
                $mt->maketext('List of extensions owned or co-owned by [_1]', $user),
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
                            $mt->maketext('Extensions'),
                            '............... Should be "Extension" th'
                        );
                    });
                    $tx->ok('./th[2]', '............ Test second th', sub {
                        $tx->is('./@scope', 'col', '............... Should be row scope');
                        $tx->is(
                            './text()',
                            $mt->maketext('Owner'),
                            '............... Should be "Owner" th'
                        );
                    });
                    $tx->ok('./th[3]', '............ Test third th', sub {
                        $tx->is('./@scope', 'col', '............... Should be row scope');
                        $tx->is(
                            './text()',
                            $mt->maketext('Co-Owners'),
                            '............... Should be "Co-Owners" th'
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
                            q{You don’t own any extensions, yet.}
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

# Now one called pair.
my $meta = $dist->distmeta;
$meta->{name} = 'pair';
$meta->{version} = '1.3.0';
$meta->{provides} = {
    pair => { file => "sql/pair.sql", version => "1.3.0" }
};
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
    my $req = GET $uri, Authorization => 'Basic ' . encode_base64("$user:test-passW0rd");

    ok my $res = $cb->($req), "Get $uri with auth token";
    ok $res->is_success, 'Response should be success';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($req));
    $req->env->{REMOTE_USER} = $user;
    XPathTest->test_basics($tx, $req, $mt, {
        h1 => 'View Permissions',
        page_title => 'View permissions',
    });

    $tx->ok('/html/body/div[@id="content"]', 'Look at the content', sub {
        $tx->is('count(./*)', 2, '... Should have two subelements');
        $tx->ok('./table[@id="privlist"]', '... Test privlist table', sub {
            $tx->is(
                './@summary',
                $mt->maketext('List of extensions owned or co-owned by [_1]', $user),
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
                            $mt->maketext('Extensions'),
                            '............... Should be "Extensions" th'
                        );
                    });
                    $tx->ok('./th[2]', '............ Test second th', sub {
                        $tx->is('./@scope', 'col', '............... Should be row scope');
                        $tx->is(
                            './text()',
                            $mt->maketext('Owner'),
                            '............... Should be "Owner" th'
                        );
                    });
                    $tx->ok('./th[3]', '............ Test third th', sub {
                        $tx->is('./@scope', 'col', '............... Should be row scope');
                        $tx->is(
                            './text()',
                            $mt->maketext('Co-Owners'),
                            '............... Should be "Co-Owners" th'
                        );
                    });
                });
            });
            $tx->ok('./tbody', '...... Test tbody', sub {
                $tx->is('count(./*)', 2, '......... Should have two subelements');
                $tx->is('count(./tr)', 2, '......... Both should be tr');
                $tx->ok('./tr[1]', '......... Test first tr', sub {
                    $tx->is('./@class', 'spec', '............ Class should be "spec"');
                    $tx->is('count(./*)', 3, '............ Should have three subelements');
                    $tx->ok('./th[@scope="row"]', '............ Test th', sub {
                        $tx->is('count(./*)', 1, '............... Should have 1 subelement');
                        $tx->ok('./a[@class="show"]', '............... Test anchor', sub {
                            $tx->is(
                                './@title',
                                $mt->maketext(q{See [_1]'s details}, 'pair'),
                                '.................. Should have link title'
                            );
                            $tx->is(
                                './@href',
                                $req->uri_for('/permissions/pair'),
                                '.................. Should have href'
                            );
                            $tx->is(
                                './img/@src',
                                $req->uri_for('/ui/img/play.svg'),
                                'It should have an image link'
                            );
                            $tx->like(
                                './text()',
                                qr/\bpair\b/,
                                'Should have link text'
                            )
                        });
                    });
                    $tx->is(
                        './td[1]',
                        $user,
                        'Should have user in second cell'
                    );
                    $tx->is('./td[2]', '', 'Should have empty third cell');
                });
                $tx->ok('./tr[2]', '......... Test second tr', sub {
                    $tx->is('./@class', 'specalt', '............ Class should be "specalt"');
                    $tx->is('count(./*)', 3, '............ Should have three subelements');
                    $tx->ok('./th[@scope="row"]', '............ Test th', sub {
                        $tx->is('count(./*)', 1, '............... Should have 1 subelement');
                        $tx->ok('./a[@class="show"]', '............... Test anchor', sub {
                            $tx->is(
                                './@title',
                                $mt->maketext(q{See [_1]'s details}, 'widget'),
                                '.................. Should have link title'
                            );
                            $tx->is(
                                './@href',
                                $req->uri_for('/permissions/widget'),
                                '.................. Should have href'
                            );
                            $tx->is(
                                './img/@src',
                                $req->uri_for('/ui/img/play.svg'),
                                'It should have an image link'
                            );
                            $tx->like(
                                './text()',
                                qr/\bwidget\b/,
                                'Should have link text'
                            )
                        });
                    });
                    $tx->is(
                        './td[1]', $user,
                        'Should have user in second cell'
                    );
                    $tx->is('./td[2]', '', 'Should have empty third cell');
                });
            });
        });
    });
};

##################################################################################
# Great! Now have a look at admin's extensions.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb  = shift;
    my $req = GET $uri, Authorization => 'Basic ' . encode_base64("$admin:test-passW0rd");

    ok my $res = $cb->($req), "Get $uri with auth token";
    ok $res->is_success, 'Response should be success';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($req));
    $req->env->{REMOTE_USER} = $admin;
    XPathTest->test_basics($tx, $req, $mt, {
        h1 => 'View Permissions',
        page_title => 'View permissions',
    });

    $tx->ok('/html/body/div[@id="content"]', 'Look at the content', sub {
        $tx->is('count(./*)', 2, '... Should have two subelements');
        $tx->ok('./table[@id="privlist"]', '... Test privlist table', sub {
            $tx->is(
                './@summary',
                $mt->maketext('List of extensions owned or co-owned by [_1]', $admin),
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
                            $mt->maketext('Extensions'),
                            '............... Should be "Extensions" th'
                        );
                    });
                    $tx->ok('./th[2]', '............ Test second th', sub {
                        $tx->is('./@scope', 'col', '............... Should be row scope');
                        $tx->is(
                            './text()',
                            $mt->maketext('Owner'),
                            '............... Should be "Owner" th'
                        );
                    });
                    $tx->ok('./th[3]', '............ Test third th', sub {
                        $tx->is('./@scope', 'col', '............... Should be row scope');
                        $tx->is(
                            './text()',
                            $mt->maketext('Co-Owners'),
                            '............... Should be "Co-Owners" th'
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
                                $mt->maketext(q{See [_1]'s details}, 'pgtap'),
                                '.................. Should have link title'
                            );
                            $tx->is(
                                './@href',
                                $req->uri_for('/permissions/pgtap'),
                                '.................. Should have href'
                            );
                            $tx->is(
                                './img/@src',
                                $req->uri_for('/ui/img/play.svg'),
                                'It should have an image link'
                            );
                            $tx->like(
                                './text()',
                                qr/\bpgtap\b/,
                                'Should have link text'
                            )
                        });
                    });
                    $tx->is(
                        './td[1]', $admin,
                        'Should have admin user in second cell'
                    );
                    $tx->is('./td[2]', '', 'Should have empty third cell');
                });
            });
        });
    });
};

##################################################################################
# Now grant co-ownership on pgTAP to the user.
PGXN::Manager->conn->run(sub {
    ok shift->selectcol_arrayref(
        'SELECT grant_coownership($1, $2, $3)',
        undef, $admin, $user, ['pgTAP'],
    )->[0], "Grant co-ownership on pgTAP to $user";
});

# Now we should have three items listed for the user.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb  = shift;
    my $req = GET $uri, Authorization => 'Basic ' . encode_base64("$user:test-passW0rd");

    ok my $res = $cb->($req), "Get $uri with auth token";
    ok $res->is_success, 'Response should be success';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($req));
    $req->env->{REMOTE_USER} = $user;
    XPathTest->test_basics($tx, $req, $mt, {
        h1 => 'View Permissions',
        page_title => 'View permissions',
    });

    $tx->ok('/html/body/div[@id="content"]', 'Look at the content', sub {
        $tx->is('count(./*)', 2, '... Should have two subelements');
        $tx->ok('./table[@id="privlist"]', '... Test privlist table', sub {
            $tx->is(
                './@summary',
                $mt->maketext('List of extensions owned or co-owned by [_1]', $user),
                '...... Summary should be correct'
            );
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
                                $mt->maketext(q{See [_1]'s details}, 'pair'),
                                '.................. Should have link title'
                            );
                            $tx->is(
                                './@href',
                                $req->uri_for('/permissions/pair'),
                                '.................. Should have href'
                            );
                            $tx->is(
                                './img/@src',
                                $req->uri_for('/ui/img/play.svg'),
                                'It should have an image link'
                            );
                            $tx->like(
                                './text()',
                                qr/\bpair\b/,
                                'Should have link text'
                            )
                        });
                    });
                    $tx->is(
                        './td[1]',
                        $user,
                        'Should have user in second cell'
                    );
                    $tx->is('./td[2]', '', 'Should have empty third cell');
                });
                $tx->ok('./tr[2]', '......... Test second tr', sub {
                    $tx->is('./@class', 'specalt', '............ Class should be "specalt"');
                    $tx->is('count(./*)', 3, '............ Should have three subelements');
                    $tx->ok('./th[@scope="row"]', '............ Test th', sub {
                        $tx->is('count(./*)', 1, '............... Should have 1 subelement');
                        $tx->ok('./a[@class="show"]', '............... Test anchor', sub {
                            $tx->is(
                                './@title',
                                $mt->maketext(q{See [_1]'s details}, 'pgtap'),
                                '.................. Should have link title'
                            );
                            $tx->is(
                                './@href',
                                $req->uri_for('/permissions/pgtap'),
                                '.................. Should have href'
                            );
                            $tx->is(
                                './img/@src',
                                $req->uri_for('/ui/img/play.svg'),
                                'It should have an image link'
                            );
                            $tx->like(
                                './text()',
                                qr/\bpgtap\b/,
                                'Should have link text'
                            )
                        });
                    });
                    $tx->is(
                        './td[1]', $admin,
                        'Should have admin user in second cell'
                    );
                    $tx->is('./td[2]', $user, 'Should have user in third cell');
                });
                $tx->ok('./tr[3]', '......... Test third tr', sub {
                    $tx->is('./@class', 'spec', '............ Class should be "spec"');
                    $tx->is('count(./*)', 3, '............ Should have three subelements');
                    $tx->ok('./th[@scope="row"]', '............ Test th', sub {
                        $tx->is('count(./*)', 1, '............... Should have 1 subelement');
                        $tx->ok('./a[@class="show"]', '............... Test anchor', sub {
                            $tx->is(
                                './@title',
                                $mt->maketext(q{See [_1]'s details}, 'widget'),
                                '.................. Should have link title'
                            );
                            $tx->is(
                                './@href',
                                $req->uri_for('/permissions/widget'),
                                '.................. Should have href'
                            );
                            $tx->is(
                                './img/@src',
                                $req->uri_for('/ui/img/play.svg'),
                                'It should have an image link'
                            );
                            $tx->like(
                                './text()',
                                qr/\bwidget\b/,
                                'Should have link text'
                            )
                        });
                    });
                    $tx->is(
                        './td[1]', $user,
                        'Should have user in second cell'
                    );
                    $tx->is('./td[2]', '', 'Should have empty third cell');
                });
            });
        });
    });
};

# $admin's view should still show one extension, but now list $user as co-owner.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb  = shift;
    my $req = GET $uri, Authorization => 'Basic ' . encode_base64("$admin:test-passW0rd");

    ok my $res = $cb->($req), "Get $uri with auth token";
    ok $res->is_success, 'Response should be success';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($req));
    $req->env->{REMOTE_USER} = $admin;
    XPathTest->test_basics($tx, $req, $mt, {
        h1 => 'View Permissions',
        page_title => 'View permissions',
    });

    $tx->ok('/html/body/div[@id="content"]', 'Look at the content', sub {
        $tx->is('count(./*)', 2, '... Should have two subelements');
        $tx->ok('./table[@id="privlist"]', '... Test privlist table', sub {
            $tx->is(
                './@summary',
                $mt->maketext('List of extensions owned or co-owned by [_1]', $admin),
                '...... Summary should be correct'
            );
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
                                $mt->maketext(q{See [_1]'s details}, 'pgtap'),
                                '.................. Should have link title'
                            );
                            $tx->is(
                                './@href',
                                $req->uri_for('/permissions/pgtap'),
                                '.................. Should have href'
                            );
                            $tx->is(
                                './img/@src',
                                $req->uri_for('/ui/img/play.svg'),
                                'It should have an image link'
                            );
                            $tx->like(
                                './text()',
                                qr/\bpgtap\b/,
                                'Should have link text'
                            )
                        });
                    });
                    $tx->is(
                        './td[1]', $admin,
                        'Should have admin user in second cell'
                    );
                    $tx->is('./td[2]', $user, 'Should have user in third cell');
                });
            });
        });
    });
};
