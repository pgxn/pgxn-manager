#!/usr/bin/env perl

use 5.12.0;
use utf8;
use Test::More tests => 194;
#use Test::More 'no_plan';
use Plack::Test;
use HTTP::Request::Common;
use PGXN::Manager;
use PGXN::Manager::Router;
use HTTP::Message::PSGI;
use Test::XML;
use Test::XPath;
use lib 't/lib';
use TxnTest;
use XPathTest;
use MIME::Base64;

my $app      = PGXN::Manager::Router->app;
my $mt       = PGXN::Manager::Locale->accept('en');
my $uri      = '/auth/admin/moderate';
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

# Authenticate a non-admin user.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb  = shift;
    my $req = GET $uri, Authorization => 'Basic ' . encode_base64("$user:****");

    ok my $res = $cb->($req), "Get $uri with auth token";
    is $res->code, 403, 'Should get 403 response';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($req));
    $req->env->{REMOTE_USER} = $user;
    XPathTest->test_basics($tx, $req, $mt, { h1 => 'Permission Denied' });

    $tx->ok('/html/body/div[@id="content"]', 'Look at the content', sub {
        $tx->is('count(./*)', 2, '... Should have two subelements');
        $tx->is(
            './p[@class="error"]',
            $mt->maketext(q{Sorry, you do not have permission to access this page.}),
            '... Should have the error message'
        );
    });
};

# Create a couple of new users.
PGXN::Manager->conn->run(sub {
    my $dbh = shift;
    $dbh->do(
        'SELECT insert_user(?, ?, email := ?, uri := ?, full_name := ?, why := ?)',
        undef, 'joe', '****', 'joe@pgxn.org', 'http://foo.com/', 'Joe Dog', 'I am awesome',
    );
    $dbh->do(
        'SELECT insert_user(?, ?, email := ?, why := ?)',
        undef, 'bob', '****', 'bob@pgxn.org', 'You want me',
    );
});

# Authenticate an admin user.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb  = shift;
    my $req = GET $uri, Authorization => 'Basic ' . encode_base64("$admin:****");

    ok my $res = $cb->($req), "Get $uri with auth token";
    ok $res->is_success, 'Response should be success';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($req));
    $req->env->{REMOTE_USER} = $admin;
    XPathTest->test_basics($tx, $req, $mt, { h1 => 'Moderate Account Requests' });

    $tx->ok('/html/body/div[@id="content"]', 'Look at the content', sub {
        $tx->is('count(./*)', 4, '... Should have four subelements');
        # Let's have a look at the content.
        $tx->is('./p', $mt->maketext(
            q{Thanks for moderating user requests, [_1]. Here's how:}, $admin
        ), '... Should have intro paragraph');
        $tx->ok('./ul', '... Test directions list', sub {
            $tx->is('count(./*)', 3, '...... Should have three subelements');
            $tx->is('count(./li)', 3, '...... And they should be list items');
            $tx->is('./li[1]', $mt->maketext(
                q{Hit the green ▶ to review a requestor's reasons for wanting an account.}
            ), '...... First should be the review item');
            $tx->is('./li[2]', $mt->maketext(
                q{Hit the blue ✔ to approve an account request.}
            ), '...... Second should be the approve item');
            $tx->is('./li[3]', $mt->maketext(
                q{Hit the red ▬ to deny an account request.}
            ), '...... Third should be the reject item');
        });

        # And we should have an empty table with no users.
        $tx->ok('./table[@id="userlist"]', '... Test userlist table', sub {
            $tx->is('count(./*)', 2, '...... Should have two subelements');
            $tx->ok('./thead', '...... Test the table head', sub {
                $tx->is('count(./*)', 1, '......... Should have one subelement');
                $tx->ok('./tr', '......... Test the thead row', sub {
                    $tx->is('count(./*)', 4, '......... Should have four subelements');
                    $tx->is(
                        './th[1][@scope="col"]',
                        $mt->maketext('Requests'),
                        '............ Should have "Requests" header'
                    );
                    $tx->is('./th[1]/@class', 'nobg', '............ It should have "nobg" class');
                    $tx->is(
                        './th[2][@scope="col"]', $mt->maketext('Name'),
                        '............ Should have "Name" header'
                    );
                    $tx->is(
                        './th[3][@scope="col"]', $mt->maketext('Email'),
                        '............ Should have "Email" header'
                    );
                    $tx->is(
                        './th[4][@scope="col"]', $mt->maketext('Actions'),
                        '............ Should have "Actions" header'
                    );
                });
            });
            $tx->ok('./tbody', '...... Test the table body', sub {
                $tx->is('count(./*)', 2, '......... Should have two subelements');
                $tx->ok('./tr[1]', '......... Test the first tbody row', sub {
                    $tx->is('./@class', 'spec', '......... It should be class "spec"');
                    $tx->is('count(./*)', 4, '......... Should have four subelements');
                    $tx->is(
                        './th[1][@scope="row"]',
                        'bob',
                        '............ Should have "Nickname" header'
                    );
                    $tx->is(
                        './td[1]', $mt->maketext('~[none given~]'),
                        'Should have name'
                    );
                    $tx->ok('./td[2]', '............ Test third column', sub {
                        $tx->is(
                            './@title',
                            $mt->maketext('Send email to [_1]', 'bob'),
                            '............... It should have a title'
                        );
                        $tx->ok('./a', '............... It should have an anchor', sub {
                            $tx->is(
                                './@href', 'mailto:bob@pgxn.org',
                                '.................. With link to mail'
                            );
                            $tx->is(
                                './text()', 'bob@pgxn.org',
                                '.................. Displaying address'
                            );
                        });
                    });
                    $tx->ok('./td[3]', '............ Test fourth column', sub {
                        $tx->is(
                            './@class', 'actions',
                            '............... It should have a class'
                        );
                        $tx->is('count(./*)', 3, '............... And three subelements');
                        $tx->is('count(./a)', 3, '............... All anchors');
                        $tx->ok('./a[1]', '............... Test first anchor', sub {
                            $tx->is(
                                'count(./*)', 1,
                                '.................. Should have 1 subelement');
                            my $uri = $req->uri_for('/ui/img/play.png');
                            $tx->ok(
                                qq{./img[\@src="$uri"]},
                                '.................. Which should be the play image'
                            );
                        });
                        $tx->ok('./a[2]', '............... Test second anchor', sub {
                            $tx->is(
                                './@href',
                                $req->uri_for("/auth/admin/accept/bob"),
                                '.................. It should have the accept uri'
                            );
                            $tx->is(
                                'count(./*)', 1,
                                '.................. Should have 1 subelement'
                            );
                            my $uri = $req->uri_for('/ui/img/accept.png');
                            $tx->ok(
                                qq{./img[\@src="$uri"]},
                                '.................. Which should be the accept image'
                            );
                        });
                        $tx->ok('./a[3]', '............... Test third anchor', sub {
                            $tx->is(
                                'count(./*)', 1,
                                '.................. Should have 1 subelement'
                            );
                            $tx->is(
                                './@href',
                                $req->uri_for("/auth/admin/reject/bob"),
                                '.................. It should have the reject uri'
                            );
                            my $uri = $req->uri_for('/ui/img/reject.png');
                            $tx->ok(
                                qq{./img[\@src="$uri"]},
                                '.................. Which should be the reject image'
                            );
                        });
                    });
                });
                $tx->ok('./tr[2]', '......... Test the second tbody row', sub {
                    $tx->is('./@class', 'specalt', '......... It should be class "spec"');
                    $tx->is('count(./*)', 4, '......... Should have four subelements');
                    $tx->is(
                        './th[1][@scope="row"]',
                        'joe',
                        '............ Should have "Nickname" header'
                    );
                    $tx->ok('./td[1]', '............ Test second column', sub {
                        $tx->is(
                            './@title', $mt->maketext(q{Visit [_1]'s site}, 'joe'),
                            '............ It should have a title'
                        );
                        $tx->is('count(./*)', 1, 'It should have a subelement');
                        $tx->ok('./a', '............ Test anchor subelement', sub {
                            $tx->is(
                                './@href', 'http://foo.com/',
                                '............... It should have the user uri'
                            );
                            $tx->is(
                                './text()', 'Joe Dog',
                                '............... And the text shoul be the full name');
                        });
                    });
                    $tx->ok('./td[2]', '............ Test third column', sub {
                        $tx->is(
                            './@title',
                            $mt->maketext('Send email to [_1]', 'joe'),
                            '............... It should have a title'
                        );
                        $tx->ok('./a', '............... It should have an anchor', sub {
                            $tx->is(
                                './@href', 'mailto:joe@pgxn.org',
                                '.................. With link to mail'
                            );
                            $tx->is(
                                './text()', 'joe@pgxn.org',
                                '.................. Displaying address'
                            );
                        });
                    });
                    $tx->ok('./td[3]', '............ Test fourth column', sub {
                        $tx->is(
                            './@class', 'actions',
                            '............... It should have a class'
                        );
                        $tx->is('count(./*)', 3, '............... And three subelements');
                        $tx->is('count(./a)', 3, '............... All anchors');
                        $tx->ok('./a[1]', '............... Test first anchor', sub {
                            $tx->is(
                                'count(./*)', 1,
                                '.................. Should have 1 subelement');
                            my $uri = $req->uri_for('/ui/img/play.png');
                            $tx->ok(
                                qq{./img[\@src="$uri"]},
                                '.................. Which should be the play image'
                            );
                        });
                        $tx->ok('./a[2]', '............... Test second anchor', sub {
                            $tx->is(
                                'count(./*)', 1,
                                '.................. Should have 1 subelement'
                            );
                            $tx->is(
                                './@href',
                                $req->uri_for("/auth/admin/accept/joe"),
                                '.................. It should have the accept uri'
                            );
                            my $uri = $req->uri_for('/ui/img/accept.png');
                            $tx->ok(
                                qq{./img[\@src="$uri"]},
                                '.................. Which should be the accept image'
                            );
                        });
                        $tx->ok('./a[3]', '............... Test third anchor', sub {
                            $tx->is(
                                'count(./*)', 1,
                                '.................. Should have 1 subelement'
                            );
                            $tx->is(
                                './@href',
                                $req->uri_for("/auth/admin/reject/joe"),
                                '.................. It should have the reject uri'
                            );
                            my $uri = $req->uri_for('/ui/img/reject.png');
                            $tx->ok(
                                qq{./img[\@src="$uri"]},
                                '.................. Which should be the reject image'
                            );
                        });
                    });
                });
            });
        });
    });
};

# Have the admin user approve these accounts.
PGXN::Manager->conn->run(sub {
    my $dbh = shift;
    $dbh->do(
        'SELECT set_user_status(?, ?, ?)',
        undef, $admin, $_, 'active'
    ) for qw(joe bob);
});

# Send the request again.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb  = shift;
    my $req = GET $uri, Authorization => 'Basic ' . encode_base64("$admin:****");

    ok my $res = $cb->($req), "Get $uri with auth token again";
    ok $res->is_success, 'Response should be success';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($req));

    # There now should be only a blank row indicating no pending requests.
    $tx->ok('//table[@id="userlist"]', '... Test userlist table', sub {
        $tx->ok('./tbody/tr[1]', '...... Test first body row', sub {
            $tx->is('count(./*)', 1, 'Should have only one subelement');
            $tx->is(
                './td[@colspan="4"]',
                $mt->maketext('No pending requests. Time for a beer?'),
                'And it should show that there are no pending users'
            );
        });
    });
};

# Okay, make them new again.
PGXN::Manager->conn->run(sub {
    my $dbh = shift;
    $dbh->do(
        'SELECT set_user_status(?, ?, ?)',
        undef, $admin, $_, 'new'
    ) for qw(joe bob);
});

# Accept bob.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb     = shift;
    my $req    = GET(
        '/auth/admin/accept/bob',
        Authorization => 'Basic ' . encode_base64("$admin:****")
    );

    ok my $res = $cb->($req), 'GET acceptance for bob';
    ok $res->is_redirect, 'Response should be a redirect';
    is $res->headers->header('location'), $uri, 'Should redirect to /moderate';
};

# Has bob been accepted?
PGXN::Manager->conn->run(sub {
    my $dbh = shift;
    ok $dbh->selectcol_arrayref(
        'SELECT status = ? FROM users WHERE nickname = ?',
        undef, 'active', 'bob'
    )->[0], 'Bob should be active';
    ok $dbh->selectcol_arrayref(
        'SELECT status = ? FROM users WHERE nickname = ?',
        undef, 'new', 'joe'
    )->[0], 'Joe should still be new';
});

# Send an Ajax request to reject joe.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb     = shift;
    my $req    = GET(
        '/auth/admin/reject/joe',
        'X-Requested-With' => 'XMLHttpRequest',
        Authorization => 'Basic ' . encode_base64("$admin:****")
    );

    ok my $res = $cb->($req), 'GET rejection for joe';
    ok $res->is_success, 'Response should be success';
    is $res->content, 'success', 'And the content should say so';
};

# Has joe been rejected?
PGXN::Manager->conn->run(sub {
    my $dbh = shift;
    ok $dbh->selectcol_arrayref(
        'SELECT status = ? FROM users WHERE nickname = ?',
        undef, 'active', 'bob'
    )->[0], 'Bob should be active';
    ok $dbh->selectcol_arrayref(
        'SELECT status = ? FROM users WHERE nickname = ?',
        undef, 'deleted', 'joe'
    )->[0], 'Joe should be deleted';
});
