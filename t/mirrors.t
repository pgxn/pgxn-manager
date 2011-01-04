#!/usr/bin/env perl -w

use 5.12.0;
use utf8;
use Test::More tests => 317;
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
use MIME::Base64;
use lib 't/lib';
use TxnTest;
use XPathTest;

my $app      = PGXN::Manager::Router->app;
my $mt       = PGXN::Manager::Locale->accept('en');
my $uri      = '/auth/admin/mirrors';
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

# Connect as non-admin user.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb  = shift;
    my $req = GET $uri, Authorization => 'Basic ' . encode_base64("$user:****");

    ok my $res = $cb->($req), "Get $uri with auth token";
    is $res->code, 403, 'Should get 403 response';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($req));
    $req->env->{REMOTE_USER} = $user;
    $req->env->{SCRIPT_NAME} = '/auth';
    XPathTest->test_basics($tx, $req, $mt, {
        h1 => 'Permission Denied',
        page_title => q{Whoops! I don't think you belong here},
    });

    $tx->ok('/html/body/div[@id="content"]', 'Look at the content', sub {
        $tx->is('count(./*)', 2, '... Should have two subelements');
        $tx->is(
            './p[@class="error"]',
            $mt->maketext(q{Sorry, you do not have permission to access this resource.}),
            '... Should have the error message'
        );
    });
};

# Connect as authenticated user.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb  = shift;
    my $req = GET $uri, Authorization => 'Basic ' . encode_base64("$admin:****");

    ok my $res = $cb->($req), "Get $uri with auth token";
    ok $res->is_success, 'Response should be success';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($req));
    $req->env->{REMOTE_USER} = $admin;
    $req->env->{SCRIPT_NAME} = '/auth';
    XPathTest->test_basics($tx, $req, $mt, {
        h1 => 'Mirrors',
        page_title  => 'Administer project rsync mirrors',
        with_jquery => 1,
        js          => 'PGXN.init_mirrors()',
    });

    $tx->ok('/html/body/div[@id="content"]', 'Look at the content', sub {
        $tx->is('count(./*)', 4, '... Should have four subelements');
        # Let's have a look at the content.
        $tx->is('./p', $mt->maketext(
            q{Thanks for administering rsync mirrors, [_1]. Here's how:}, $admin
        ), '... Should have intro paragraph');
        $tx->ok('./ul', '... Test directions list', sub {
            $tx->is('count(./*)', 3, '...... Should have three subelements');
            $tx->is('count(./li)', 3, '...... And they should be list items');
            $tx->is('./li[1]', $mt->maketext(
                q{Hit the green ✚ add a new mirror.}
            ), '...... First should be the add item');
            $tx->is('./li[2]', $mt->maketext(
                q{Hit the green ➔ to edit an existing mirror.}
            ), '...... Second should be the edit item');
            $tx->is('./li[3]', $mt->maketext(
                q{Hit the red ▬ to delete an existing mirror.}
            ), '...... Third should be the delete item');
        });

        $tx->ok('./table[@id="mirrorlist"]', '... Test mirrorlist table', sub {
            $tx->is(
                './@summary',
                $mt->maketext('List of project mirrors'),
                '...... Summary should be correct'
            );
            $tx->is('count(./*)', 2, '...... Should have two subelements');
            $tx->ok('./thead', '...... Test thead', sub {
                $tx->is('count(./*)', 1, '......... Should have one subelement');
                $tx->ok('./tr', '......... Should be a row', sub {
                    $tx->is('count(./*)', 4, '............ Should have four subelements');
                    $tx->is('count(./th)', 4, '........... All should be th');
                    $tx->ok('./th[1]', '............ Test first th', sub {
                        $tx->is('./@scope', 'col', '............... Should be row scope');
                        $tx->is('./@class', 'nobg', '............... Should be class nobg');
                        my $title = $mt->maketext('Mirrors');
                        $tx->like(
                            './text()',
                            qr{\Q$title},
                            '............... Should be "Mirrors" th'
                        );
                        $tx->ok('./span[@class="control"]/a', '............... Test control span', sub {
                            $tx->is('count(./*)', 1, '............... Should have one subelement');
                            $tx->is(
                                './@title',
                                $mt->maketext('Create a new Mirror'),
                                '............... Should have create title',
                            );
                            $tx->is(
                                './@href',
                                $req->uri_for('/admin/mirrors/new'),
                                '.................. Should have new href'
                            );
                            my $t = $mt->maketext('Add');
                            $tx->like(
                                './text()',
                                qr{\Q$t},
                                '.................. Should have title "Add"'
                            );
                            my $src = $req->uri_for('/ui/img/add.png');
                            $tx->ok(
                                qq{./img[\@src="$src"]},
                                '.................. Should have add.png image'
                            );
                        });
                    });
                    $tx->ok('./th[2]', '............ Test second th', sub {
                        $tx->is('./@scope', 'col', '............... Should be row scope');
                        $tx->is(
                            './text()',
                            $mt->maketext('Frequency'),
                            '............... Should be "Frequency" th'
                        );
                    });
                    $tx->ok('./th[3]', '............ Test third th', sub {
                        $tx->is('./@scope', 'col', '............... Should be row scope');
                        $tx->is(
                            './text()',
                            $mt->maketext('Contact'),
                            '............... Should be "Contact" th'
                        );
                    });
                    $tx->is(
                        './th[4][@scope="col"]', $mt->maketext('Delete'),
                        '............ Should have "Delete" header'
                    );
                });
            });
            $tx->ok('./tbody', '...... Test tbody', sub {
                $tx->is('count(./*)', 1, '......... Should have one subelement');
                $tx->ok('./tr', '......... Should be a row', sub {
                    $tx->is('./@class', 'spec', '............ Should "spec" class');
                    $tx->is('count(./*)', 1, '............ Should have one subelement');
                    $tx->ok('./td[@colspan="3"]', '............ Test single row', sub {
                        my $msg = quotemeta $mt->maketext(
                            q{No mirrors yet.}
                        );
                        $tx->like(
                            './text()',
                            qr/$msg/,
                            '............... Should have empty list message'
                        );
                        $tx->is(
                            './a[@id="addmirror"]',
                            $mt->maketext('Add one now!'),
                            '............... And should have upload link',
                        );
                    });
                });
            });
        });
    });
};

##############################################################################
# Okay, let's add a couple of mirrors, eh?
PGXN::Manager->conn->run(sub {
    my $dbh = shift;
    my $sth = $dbh->prepare(q{
        SELECT insert_mirror(
            admin        := $1,
            uri          := $2,
            frequency    := $3,
            location     := $4,
            bandwidth    := $5,
            organization := $6,
            timezone     := $7,
            email        := $8,
            src          := $9,
            rsync        := $10,
            notes        := $11
        )
    });
    $sth->execute(
        $admin,
        'http://kineticode.com/pgxn/',
        'hourly',
        'Portland, OR, USA',
        '10MBps',
        'Kineticode, Inc.',
        'America/Los_Angeles',
        'pgxn@kineticode.com',
        'rsync://master.pgxn.org/pgxn/',
        'rsync://pgxn.kineticode.com/pgxn/',
        'This is a note',
    );

    $sth->execute(
        $admin,
        'http://pgxn.justatheory.com',
        'daily',
        'Portland, OR, USA',
        '1MBps',
        'Just a Theory',
        'America/Los_Angeles',
        'pgxn@justatheory.com',
        'rsync://master.pgxn.org/pgxn/',
        undef,
        ''
    );
});

##############################################################################
# Okay, fetch the list again.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb  = shift;
    my $req = GET $uri, Authorization => 'Basic ' . encode_base64("$admin:****");

    ok my $res = $cb->($req), "Get $uri with auth token";
    ok $res->is_success, 'Response should be success';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($req));
    $req->env->{REMOTE_USER} = $admin;
    $req->env->{SCRIPT_NAME} = '/auth';
    XPathTest->test_basics($tx, $req, $mt, {
        h1          => 'Mirrors',
        page_title  => 'Administer project rsync mirrors',
        with_jquery => 1,
        js          => 'PGXN.init_mirrors()',
    });

    $tx->ok('/html/body/div[@id="content"]', 'Look at the content', sub {
        $tx->is('count(./*)', 4, '... Should have four subelements');
        $tx->ok('./table[@id="mirrorlist"]', '... Test mirrorlist table', sub {
            $tx->is(
                './@summary',
                $mt->maketext('List of project mirrors'),
                '...... Summary should be correct'
            );
            $tx->is('count(./*)', 2, '...... Should have two subelements');
            $tx->ok('./thead', '...... Test thead', sub {
                $tx->is('count(./*)', 1, '......... Should have one subelement');
                $tx->ok('./tr', '......... Should be a row', sub {
                    $tx->is('count(./*)', 4, '............ Should have four subelements');
                    $tx->is('count(./th)', 4, '........... All should be th');
                    $tx->ok('./th[1]', '............ Test first th', sub {
                        $tx->is('./@scope', 'col', '............... Should be row scope');
                        $tx->is('./@class', 'nobg', '............... Should be class nobg');
                        my $title = $mt->maketext('Mirrors');
                        $tx->like(
                            './text()',
                            qr{\Q$title},
                            '............... Should be "Mirrors" th'
                        );
                        $tx->ok('./span[@class="control"]/a', '............... Test control span', sub {
                            $tx->is('count(./*)', 1, '............... Should have one subelement');
                            $tx->is(
                                './@title',
                                $mt->maketext('Create a new Mirror'),
                                '............... Should have create title',
                            );
                            $tx->is(
                                './@href',
                                $req->uri_for('/admin/mirrors/new'),
                                '.................. Should have new href'
                            );
                            my $t = $mt->maketext('Add');
                            $tx->like(
                                './text()',
                                qr{\Q$t},
                                '.................. Should have title "Add"'
                            );
                            my $src = $req->uri_for('/ui/img/add.png');
                            $tx->ok(
                                qq{./img[\@src="$src"]},
                                '.................. Should have add.png image'
                            );
                        });
                    });
                    $tx->ok('./th[2]', '............ Test second th', sub {
                        $tx->is('./@scope', 'col', '............... Should be row scope');
                        $tx->is(
                            './text()',
                            $mt->maketext('Frequency'),
                            '............... Should be "Frequency" th'
                        );
                    });
                    $tx->ok('./th[3]', '............ Test third th', sub {
                        $tx->is('./@scope', 'col', '............... Should be row scope');
                        $tx->is(
                            './text()',
                            $mt->maketext('Contact'),
                            '............... Should be "Contact" th'
                        );
                    });
                });
            });
            $tx->ok('./tbody', '...... Test tbody', sub {
                $tx->is('count(./*)', 2, '......... Should have two subelements');
                $tx->is('count(./tr)', 2, '......... Both should be tr');
                $tx->ok('./tr[1]', '......... Test first tr', sub {
                    $tx->is('./@class', 'spec', '............ Class should be "spec"');
                    $tx->is('count(./*)', 4, '............ Should have four subelements');
                    $tx->is('count(./th)', 1, '............ One should be a th');
                    $tx->is('count(./td)', 3, '............ The rest should be a td');
                    $tx->ok('./th[@scope="row"]', '............ Test th', sub {
                        $tx->is('count(./*)', 1, '............... Should have 1 subelement');
                        $tx->ok('./a[@class="show"]', '............... Test anchor', sub {
                            $tx->is(
                                './@title',
                                $mt->maketext(q{See details for [_1]}, 'http://kineticode.com/pgxn/'),
                                '.................. Should have link title'
                            );
                            $tx->is(
                                './@href',
                                $req->uri_for('/admin/mirrors/http://kineticode.com/pgxn/'),
                                '.................. Should have href'
                            );
                            $tx->is(
                                './img/@src',
                                $req->uri_for('/ui/img/forward.png'),
                                'It should have an image link'
                            );
                            $tx->like(
                                './text()',
                                qr{\Qhttp://kineticode.com/pgxn/},
                                'Should have link text'
                            )
                        });
                    });
                    $tx->is(
                        './td[1]',
                        'hourly',
                        'Should have status in second cell'
                    );
                    $tx->ok('./td[2]', '............ Test second td', sub {
                        $tx->is('count(./*)', 1, '............... Should have 1 subelement');
                        $tx->ok('./a', '............... Test mailto anchor', sub {
                            $tx->is(
                                './@title',
                                $mt->maketext(q{Email [_1]}, 'Kineticode, Inc.'),
                                '.................. Should have mailto link title'
                            );
                            $tx->is(
                                './@href',
                                URI->new('mailto:pgxn@kineticode.com')->canonical,
                                '.................. Should have mailto href'
                            );
                            $tx->is(
                                './text()',
                                'Kineticode, Inc.',
                                'Should have mailto link text'
                            )
                        });
                    });
                    $tx->ok('./td[3]', '............ Test third td', sub {
                        $tx->is(
                            './@class', 'actions',
                            '............... It should have a class'
                        );
                        $tx->is('count(./*)', 1, '............... And one subelement');
                        $tx->is('count(./form)', 1, '............... A form');
                        $tx->ok('./form', '............... Test form', sub {
                            $tx->is(
                                './@enctype',
                                'application/x-www-form-urlencoded; charset=UTF-8',
                                '................. Should have enctype');
                            $tx->is(
                                './@method',
                                'post',
                                '.................. Should have method=post'
                            );
                            $tx->is(
                                './@class',
                                'delete',
                                '.................. It should have the "delete" class'
                            );
                            $tx->is(
                                './@action',
                                $req->uri_for(
                                    '/admin/mirrors/http://kineticode.com/pgxn/',
                                    'x-tunneled-method' => 'DELETE'
                                ),
                                '.................. It should have the delete uri'
                            );
                            $tx->is(
                                'count(./*)', 1,
                                '.................. Should have 1 subelement'
                            );
                            $tx->ok(
                                './input[@type="image"]',
                                '.................. Test image input',
                                sub {
                                    $tx->is(
                                        './@class', 'button',
                                        '..................... Class should be "button"'

                                    );
                                    $tx->is(
                                        './@name', 'submit',
                                        '..................... Name should be "submit"'

                                    );
                                    $tx->is(
                                        './@src',
                                        $req->uri_for('/ui/img/remove.png'),
                                        '..................... Source should be remove.png'
                                    );
                                }
                            );
                        });
                    })
                });
                $tx->ok('./tr[2]', '......... Test second tr', sub {
                    $tx->is('./@class', 'specalt', '............ Class should be "specalt"');
                    $tx->is('count(./*)', 4, '............ Should have four subelements');
                    $tx->ok('./th[@scope="row"]', '............ Test th', sub {
                        $tx->is('count(./*)', 1, '............... Should have 1 subelement');
                        $tx->ok('./a[@class="show"]', '............... Test anchor', sub {
                            $tx->is(
                                './@title',
                                $mt->maketext(q{See details for [_1]}, 'http://pgxn.justatheory.com'),
                                '.................. Should have link title'
                            );
                            $tx->is(
                                './@href',
                                $req->uri_for('/admin/mirrors/http://pgxn.justatheory.com'),
                                '.................. Should have href'
                            );
                            $tx->is(
                                './img/@src',
                                $req->uri_for('/ui/img/forward.png'),
                                'It should have an image link'
                            );
                            $tx->like(
                                './text()',
                                qr{\Qhttp://pgxn.justatheory.com},
                                'Should have link text'
                            )
                        });
                    });
                    $tx->is(
                        './td[1]',
                        'daily',
                        'Should have status in second cell'
                    );
                    $tx->ok('./td[2]', '............ Test second td', sub {
                        $tx->is('count(./*)', 1, '............... Should have 1 subelement');
                        $tx->ok('./a', '............... Test mailto anchor', sub {
                            $tx->is(
                                './@title',
                                $mt->maketext(q{Email [_1]}, 'Just a Theory'),
                                '.................. Should have mailto link title'
                            );
                            $tx->is(
                                './@href',
                                URI->new('mailto:pgxn@justatheory.com')->canonical,
                                '.................. Should have mailto href'
                            );
                            $tx->is(
                                './text()',
                                'Just a Theory',
                                'Should have mailto link text'
                            )
                        });
                    });
                    $tx->ok('./td[3]', '............ Test third td', sub {
                        $tx->is(
                            './@class', 'actions',
                            '............... It should have a class'
                        );
                        $tx->is('count(./*)', 1, '............... And one subelement');
                        $tx->is('count(./form)', 1, '............... A form');
                        $tx->ok('./form', '............... Test form', sub {
                            $tx->is(
                                './@enctype',
                                'application/x-www-form-urlencoded; charset=UTF-8',
                                '................. Should have enctype');
                            $tx->is(
                                './@method',
                                'post',
                                '.................. Should have method=post'
                            );
                            $tx->is(
                                './@class',
                                'delete',
                                '.................. It should have the "delete" class'
                            );
                            $tx->is(
                                './@action',
                                $req->uri_for(
                                    '/admin/mirrors/http://pgxn.justatheory.com',
                                    'x-tunneled-method' => 'DELETE'
                                ),
                                '.................. It should have the delete uri'
                            );
                            $tx->is(
                                'count(./*)', 1,
                                '.................. Should have 1 subelement'
                            );
                            $tx->ok(
                                './input[@type="image"]',
                                '.................. Test image input',
                                sub {
                                    $tx->is(
                                        './@class', 'button',
                                        '..................... Class should be "button"'

                                    );
                                    $tx->is(
                                        './@name', 'submit',
                                        '..................... Name should be "submit"'

                                    );
                                    $tx->is(
                                        './@src',
                                        $req->uri_for('/ui/img/remove.png'),
                                        '..................... Source should be remove.png'
                                    );
                                }
                            );
                        });
                    })
                });
            });
        });
    });
};
