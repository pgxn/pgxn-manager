#!/usr/bin/env perl -w

use 5.10.0;
use utf8;
use Test::More tests => 514;
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
use Test::File;
use Test::File::Contents;
use Encode;
use JSON::XS;
use lib 't/lib';
use TxnTest;
use XPathTest;

my $app      = PGXN::Manager::Router->app;
my $mt       = PGXN::Manager::Locale->accept('en');
my $uri      = '/admin/mirrors';
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
                            my $src = $req->uri_for('/ui/img/plus.svg');
                            $tx->ok(
                                qq{./img[\@src="$src"]},
                                '.................. Should have plus.svg image'
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
                            my $src = $req->uri_for('/ui/img/plus.svg');
                            $tx->ok(
                                qq{./img[\@src="$src"]},
                                '.................. Should have plus.svg image'
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


# Okay, now let's delete a mirror. Start without authenticating.
test_psgi $app => sub {
    my $cb = shift;
    my $uri = '/admin/mirrors/http://kineticode.com/pgxn/?x-tunneled-method=delete';
    ok my $res = $cb->(POST $uri), "POST $uri";
    is $res->code, 401, 'Should get 401 response';
    like $res->content, qr/Authorization required/,
        'The body should indicate need for authentication';
};

# Try a non-admin user.
test_psgi $app => sub {
    my $cb = shift;
    my $uri = '/admin/mirrors/http://kineticode.com/pgxn/?x-tunneled-method=delete';
    my $req = POST $uri, Authorization => 'Basic ' . encode_base64("$user:****");
    ok my $res = $cb->($req), "POST $uri";

    is $res->code, 403, 'Should get 403 response';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($req));
    $req->env->{REMOTE_USER} = $user;
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

# Now try without the requisite tunneled DELETE method.
test_psgi $app => sub {
    my $cb = shift;
    my $uri = '/admin/mirrors/http://kineticode.com/pgxn/';
    my $req = POST $uri, Authorization => 'Basic ' . encode_base64("$admin:****");
    ok my $res = $cb->($req), "POST $uri";

    ok !$res->is_success, 'It should not be a success';
    is $res->code, 405, 'It should be "405 - not allowed"';

    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($req));
    $req->env->{REMOTE_USER} = $admin;
    XPathTest->test_basics($tx, $req, $mt, {
        h1 => 'Not Allowed',
    });

    $tx->ok('/html/body/div[@id="content"]', 'Look at the content', sub {
        $tx->is('count(./*)', 2, '... Should have two subelements');
        $tx->is(
            './p[@class="error"]',
            $mt->maketext(q{Sorry, but the [_1] method is not allowed on this resource.}, 'POST'),
            '... Should have the error message'
        );
    });
};

# Set up the mirror root.
my $pgxn = PGXN::Manager->instance;
my $meta = File::Spec->catfile($pgxn->config->{mirror_root}, 'meta', 'mirrors.json');
END { remove_tree $pgxn->config->{mirror_root} }
file_not_exists_ok $meta, "mirrors.json should not exist";

# Now delete one of these bad boys!
test_psgi $app => sub {
    my $cb = shift;
    my $uri = '/admin/mirrors/http://kineticode.com/pgxn/?x-tunneled-method=delete';
    my $req = POST $uri, Authorization => 'Basic ' . encode_base64("$admin:****");

    # Send the request.
    ok my $res = $cb->($req), "POST $uri";
    ok $res->is_redirect, 'It should be a redirect response';

    # Validate we got the expected response.
    $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    is $res->headers->header('location'), $req->uri_for('/admin/mirrors'),
        'Should redirect to /admin/mirrors';

    # And we should find a mirror with the new URL, but not the old one.
    PGXN::Manager->conn->run(sub {
        is_deeply $_->selectrow_arrayref(
            'SELECT uri FROM mirrors ORDER BY uri',
         ), ['http://pgxn.justatheory.com'],
         'Should now have only one mirror in the database';

        # And mirrors.json should have been updated.
        file_exists_ok $meta, 'mirrors.json should now exist';
        file_contents_is $meta, encode_utf8 $_->selectrow_arrayref(
            'SELECT get_mirrors_json()'
        )->[0], 'And it should contain the updated list of mirrors';
        open my $fh, '<:raw', $meta or die "Cannot open $meta: $!\n";
        my $json = join '', <$fh>;
        close $fh;
        ok decode_json $json, 'Should be able to parse mirror.json';
    });
};

# Try deleting the same mirror; should get a 404.
test_psgi $app => sub {
    my $cb = shift;
    my $uri = '/admin/mirrors/http://kineticode.com/pgxn/?x-tunneled-method=delete';
    my $req = POST $uri, Authorization => 'Basic ' . encode_base64("$admin:****");

    # Send the request.
    ok my $res = $cb->($req), "POST $uri";
    is $res->code, 404, 'Should get 404 response';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($req));
    $req->env->{REMOTE_USER} = $admin;
    XPathTest->test_basics($tx, $req, $mt, {
        h1 => 'Where’d It Go?',
    });

    $tx->ok('/html/body/div[@id="content"]', 'Look at the content', sub {
        $tx->is('count(./*)', 2, '... Should have two subelements');
        $tx->is(
            './p[@class="warning"]',
            $mt->maketext(q{Hrm. I can’t find a resource at this address. I looked over here and over there and could find nothing. Sorry about that, I’m fresh out of ideas.}),
            '... Should have the error message'
        );
    });
};

# Try again with an XMLHttpRequest.
test_psgi $app => sub {
    my $cb = shift;
    my $uri = '/admin/mirrors/http://kineticode.com/pgxn/?x-tunneled-method=delete';
    my $req = POST $uri, Authorization => 'Basic ' . encode_base64("$admin:****"),
        'X-Requested-With' => 'XMLHttpRequest';

    # Send the request.
    ok my $res = $cb->($req), "POST $uri";
    is $res->code, 404, 'Should get 404 response';
    is $res->decoded_content,
        $mt->maketext(q{Hrm. I can’t find a resource at this address. I looked over here and over there and could find nothing. Sorry about that, I’m fresh out of ideas.}),
            'Should get the 404 error message';
};

# Now delete the other mirror using XMLHttpRequest.
test_psgi $app => sub {
    my $cb = shift;
    my $uri = '/admin/mirrors/http://pgxn.justatheory.com?x-tunneled-method=delete';
    my $req = POST $uri, Authorization => 'Basic ' . encode_base64("$admin:****"),
        'X-Requested-With' => 'XMLHttpRequest';

    # Send the request.
    ok my $res = $cb->($req), "POST $uri";
    ok $res->is_success, 'The request should be successful';
    is $res->content, 'Success', 'The body should say as much';
};

