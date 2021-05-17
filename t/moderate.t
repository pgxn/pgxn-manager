#!/usr/bin/env perl -w

use 5.10.0;
use utf8;
BEGIN { $ENV{EMAIL_SENDER_TRANSPORT} = 'Test' }

use Test::More tests => 283;
#use Test::More 'no_plan';
use Plack::Test;
use HTTP::Request::Common;
use PGXN::Manager;
use Test::File;
use Test::File::Contents;
use PGXN::Manager::Router;
use HTTP::Message::PSGI;
use Test::XML;
use Test::XPath;
use MIME::Base64;
use File::Path 'remove_tree';
use lib 't/lib';
use TxnTest;
use XPathTest;

my $app   = PGXN::Manager::Router->app;
my $mt    = PGXN::Manager::Locale->accept('en');
my $uri   = '/admin/moderate';
my $user  = TxnTest->user;
my $admin = TxnTest->admin;
my $root  = PGXN::Manager->instance->config->{mirror_root};

END { remove_tree $root }

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

# Create a couple of new users.
PGXN::Manager->conn->run(sub {
    my $dbh = shift;
    $dbh->do(
        'SELECT insert_user(?, ?, email := ?, uri := ?, full_name := ?, why := ?)',
        undef, 'joe', '****', 'joe@pgxn.org', 'http://foo.com/', 'Joe Dög', 'I am awesome',
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
    XPathTest->test_basics($tx, $req, $mt, {
        h1 => 'Moderate Account Requests',
        with_jquery => 1,
        js => 1,
        page_title => 'User account moderation',
    });

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
                    $tx->ok('./th[1][@scope="row"]', '......... Test Nickname header', sub {
                        $tx->is('count(./*)', 2, '............ Should have two subelements');
                        $tx->ok('./a[@class="userplay"]', '......... Should have play link', sub {
                            $tx->is('./@href', '#', '............... It should have no-op href');
                            $tx->is(
                                'count(./*)', 1,
                                '............... It should have 1 subelement');
                            my $uri = $req->uri_for('/ui/img/play.svg');
                            $tx->ok(
                                qq{./img[\@src="$uri"]},
                                '............... Which should be the play image'
                            );
                            $tx->is(
                                './text()',
                                "\n        bob\n       ",
                                '............... Should have Nickname'
                            );
                        });
                        $tx->ok('./div[@class="userinfo"]', '............ And userinfo', sub {
                            $tx->is('count(./*)', 1, '............ Should have 1 subelement');
                            $tx->ok('./div[@class="why"]', '............ Which should be "why"', sub {
                                $tx->is('count(./*)', 2, '............... Should have 2 subelements');
                                $tx->is(
                                    './p', $mt->maketext('[_1] says:', 'bob'),
                                    '............... First should be intro'
                                );
                                $tx->is(
                                    './blockquote/p', 'You want me',
                                    '............... Second should be "why" text'
                                );
                            });
                        });
                    });
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
                        $tx->is('count(./*)', 2, '............... And two subelements');
                        $tx->is('count(./form)', 2, '............... Both forms');
                        $tx->ok('./form[1]', '............... Test first form', sub {
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
                                'accept',
                                '.................. It should have the "accept" class'
                            );
                            $tx->is(
                                './@action',
                                $req->uri_for('/admin/user/bob/status'),
                                '.................. It should have the status uri'
                            );
                            $tx->is(
                                'count(./*)', 2,
                                '.................. Should have 2 subelements'
                            );
                            $tx->ok(
                                './input[@type="hidden"]',
                                '.................. Test hidden input',
                                sub {
                                    $tx->is(
                                        './@name', 'status',
                                        '..................... Name should be "status"'
                                    );
                                    $tx->is(
                                        './@value', 'active',
                                        '..................... Value should be "active"'
                                    );
                                }
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
                                        $req->uri_for('/ui/img/accept.png'),
                                        '..................... Source should be accept.png'
                                    );
                                }
                            );
                        });
                        $tx->ok('./form[2]', '............... Test second form', sub {
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
                                'remove',
                                '.................. It should have the "remove" class'
                            );
                            $tx->is(
                                './@action',
                                $req->uri_for('/admin/user/bob/status'),
                                '.................. It should have the status uri'
                            );
                            $tx->is(
                                'count(./*)', 2,
                                '.................. Should have 2 subelements'
                            );
                            $tx->ok(
                                './input[@type="hidden"]',
                                '.................. Test hidden input',
                                sub {
                                    $tx->is(
                                        './@name', 'status',
                                        '..................... Name should be "status"'
                                    );
                                    $tx->is(
                                        './@value', 'deleted',
                                        '..................... Value should be "deleted"'
                                    );
                                }
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
                    });
                });
                $tx->ok('./tr[2]', '......... Test the second tbody row', sub {
                    $tx->is('./@class', 'specalt', '......... It should be class "spec"');
                    $tx->is('count(./*)', 4, '......... Should have four subelements');
                    $tx->ok('./th[1][@scope="row"]', '......... Test Nickname header', sub {
                        $tx->is('count(./*)', 2, '............ Should have two subelements');
                        $tx->ok('./a[@class="userplay"]', '......... Should have play link', sub {
                            $tx->is('./@href', '#', '............... It should have no-op href');
                            $tx->is(
                                'count(./*)', 1,
                                '............... It should have 1 subelement');
                            my $uri = $req->uri_for('/ui/img/play.svg');
                            $tx->ok(
                                qq{./img[\@src="$uri"]},
                                '............... Which should be the play image'
                            );
                            $tx->is(
                                './text()',
                                "\n        joe\n       ",
                                '............... Should have Nickname'
                            );
                        });
                        $tx->ok('./div[@class="userinfo"]', '............ And userinfo', sub {
                            $tx->is('count(./*)', 1, '............ Should have 1 subelement');
                            $tx->ok('./div[@class="why"]', '............ Which should be "why"', sub {
                                $tx->is('count(./*)', 2, '............... Should have 2 subelements');
                                $tx->is(
                                    './p', $mt->maketext('[_1] says:', 'joe'),
                                    '............... First should be intro'
                                );
                                $tx->is(
                                    './blockquote/p', 'I am awesome',
                                    '............... Second should be "why" text'
                                );
                            });
                        });
                    });

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
                                './text()', 'Joe Dög',
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
                        $tx->is('count(./*)', 2, '............... And two subelements');
                        $tx->is('count(./form)', 2, '............... Both forms');
                        $tx->ok('./form[1]', '............... Test first form', sub {
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
                                'accept',
                                '.................. It should have the "accept" class'
                            );
                            $tx->is(
                                './@action',
                                $req->uri_for('/admin/user/joe/status'),
                                '.................. It should have the status uri'
                            );
                            $tx->is(
                                'count(./*)', 2,
                                '.................. Should have 2 subelements'
                            );
                            $tx->ok(
                                './input[@type="hidden"]',
                                '.................. Test hidden input',
                                sub {
                                    $tx->is(
                                        './@name', 'status',
                                        '..................... Name should be "status"'
                                    );
                                    $tx->is(
                                        './@value', 'active',
                                        '..................... Value should be "active"'
                                    );
                                }
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
                                        $req->uri_for('/ui/img/accept.png'),
                                        '..................... Source should be accept.png'
                                    );
                                }
                            );
                        });
                        $tx->ok('./form[2]', '............... Test second form', sub {
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
                                'remove',
                                '.................. It should have the "remove" class'
                            );
                            $tx->is(
                                './@action',
                                $req->uri_for('/admin/user/joe/status'),
                                '.................. It should have the status uri'
                            );
                            $tx->is(
                                'count(./*)', 2,
                                '.................. Should have 2 subelements'
                            );
                            $tx->ok(
                                './input[@type="hidden"]',
                                '.................. Test hidden input',
                                sub {
                                    $tx->is(
                                        './@name', 'status',
                                        '..................... Name should be "status"'
                                    );
                                    $tx->is(
                                        './@value', 'deleted',
                                        '..................... Value should be "deleted"'
                                    );
                                }
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
    my $cb   = shift;
    my $json = File::Spec->catfile($root, qw(user bob.json));
    file_not_exists_ok $json, 'bob.json should not exist';
    my $req  = POST(
        '/admin/user/bob/status',
        Authorization => 'Basic ' . encode_base64("$admin:****"),
        Content => [ status => 'active' ],
    );

    ok my $res = $cb->($req), 'POST acceptance for bob';
    ok $res->is_redirect, 'Response should be a redirect';
    $req = PGXN::Manager::Request->new(req_to_psgi($req));
    is $res->headers->header('location'), $req->uri_for('/admin/moderate'),
        "Should redirect to $uri";

    # Did we write out the JSON file?
    file_exists_ok $json, 'bob.json should now exist';
    file_contents_eq_or_diff $json, '{
   "nickname": "bob",
   "name": "",
   "email": "bob@pgxn.org"
}
', 'And it should have the proper json';

    # Did we send him email?
    ok my @deliveries = Email::Sender::Simple->default_transport->deliveries,
        'Should have email deliveries.';
    is @deliveries, 1, 'Should have one message';
    is @{ $deliveries[0]{successes} }, 1, 'Should have been successfully delivered';
    my $email = $deliveries[0]{email};
    is $email->get_header('Subject'), 'Welcome to PGXN!',
        'The subject should be set';
    is $email->get_header('From'), PGXN::Manager->config->{admin_email},
        'From header should be set';
    is $email->get_header('To'), Email::Address->new(bob => 'bob@pgxn.org')->format,
        'To header should be set';
    like $email->get_body, qr{What up, bob[.]

Your PGXN account request has been approved[.] Ready to get started[?]
Great! Just click this link to set your password and get going:

    http://localhost/account/reset/\w{4,}

Best,

PGXN Management}ms,
        'Should have accept body';
    Email::Sender::Simple->default_transport->clear_deliveries
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
    my $req    = POST(
        '/admin/user/joe/status',
        'X-Requested-With' => 'XMLHttpRequest',
        Authorization => 'Basic ' . encode_base64("$admin:****"),
        Content => [status => 'deleted'],
    );

    ok my $res = $cb->($req), 'POST rejection for joe';
    ok $res->is_success, 'Response should be success';
    is $res->content, $mt->maketext('Success'),
        'And the content should say so';

    # Did we send him email?
    ok my @deliveries = Email::Sender::Simple->default_transport->deliveries,
        'Should have email deliveries.';
    is @deliveries, 1, 'Should have one message';
    is @{ $deliveries[0]{successes} }, 1, 'Should have been successfully delivered';
    my $email = $deliveries[0]{email};
    is $email->get_header('Subject'), 'Account Request Rejected',
        'The subject should be set';
    is $email->get_header('From'), PGXN::Manager->config->{admin_email},
        'From header should be set';
    is $email->get_header('To'), Email::Address->new(joe => 'joe@pgxn.org')->format,
        'To header should be set';
    is $email->get_body, q{I'm sorry to report that your request for a PGXN account has been
rejected. If you think there has been an error, please reply to this
message.

Best,

PGXN Management
}, 'Should have accept body';
    Email::Sender::Simple->default_transport->clear_deliveries
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

