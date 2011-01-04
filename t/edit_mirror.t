#!/usr/bin/env perl -w

use 5.12.0;
use utf8;
use Test::More tests => 762;
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
use Test::NoWarnings;

my $app      = PGXN::Manager::Router->app;
my $mt       = PGXN::Manager::Locale->accept('en');
my $uri      = '/auth/admin/mirrors/new';
my $user     = TxnTest->user;
my $admin    = TxnTest->admin;
my $h1       = $mt->maketext('Edit Mirror');
my $p        = $mt->maketext(q{All fields except "Note" are required. Thanks for keeping the rsync mirror index up-to-date!});

# Connect without authenticating.
test_psgi $app => sub {
    my $cb = shift;
    my $uri = '/auth/admin/mirrors/http://kineticode.com/pgxn/';
    ok my $res = $cb->(GET $uri), "GET $uri";
    is $res->code, 401, 'Should get 401 response';
    like $res->content, qr/Authorization required/,
        'The body should indicate need for authentication';
};

# Connect as non-admin user.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb  = shift;
    my $uri = '/auth/admin/mirrors/http://pgxn.justatheory.com/';
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

# Connect as authenticated user for non-existent mirror.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb  = shift;
    my $uri = '/auth/admin/mirrors/http://kineticode.com/pgxn/';
    my $req = GET $uri, Authorization => 'Basic ' . encode_base64("$admin:****");

    ok my $res = $cb->($req), "Get $uri with auth token";
    is $res->code, 404, 'Should get 404 response';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($req));
    $req->env->{REMOTE_USER} = $admin;
    $req->env->{SCRIPT_NAME} = '/auth';
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

# Okay, let's create a mirror to edit.
create_mirrors();

# Connect as authenticated user and get that mirror.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb  = shift;
    my $uri = '/auth/admin/mirrors/http://kineticode.com/pgxn/';
    my $req = GET $uri, Authorization => 'Basic ' . encode_base64("$admin:****");

    ok my $res = $cb->($req), "Get $uri with auth token";
    ok $res->is_success, 'Response should be success';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($req));
    $req->env->{REMOTE_USER} = $admin;
    $req->env->{SCRIPT_NAME} = '/auth';
    XPathTest->test_basics($tx, $req, $mt, {
        h1 => 'Edit Mirror',
        page_title  => 'Enter the mirror information provided by the contact',
        validate_form => 1,
    });

    # Check the content
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 3, '... It should have three subelements');
        $tx->is('./h1', $h1, '... The title h1 should be set');
        $tx->is('./p', $p, '... Intro paragraph should be set');
    });

    # Now examine the form.
    $tx->ok('/html/body/div[@id="content"]/form[@id="mirrorform"]', sub {
        for my $attr (
            [action  => $req->uri_for('/admin/mirrors/http://kineticode.com/pgxn/', 'x-tunneled-method' => 'put')],
            [enctype => 'application/x-www-form-urlencoded; charset=UTF-8'],
            [method  => 'post']
        ) {
            $tx->is(
                "./\@$attr->[0]",
                $attr->[1],
                qq{... Its $attr->[0] attribute should be "$attr->[1]"},
            );
        }
        $tx->is('count(./*)', 3, '... It should have three subelements');

        $tx->ok('./fieldset[1]', '... Test first fieldset', sub {
            $tx->is('./@id', 'mirroressentials', '...... It should have the proper id');
            $tx->is('./@class', 'essentials', '...... It should have the proper class');
            $tx->is('count(./*)', 28, '...... It should have 22 subelements');
            $tx->is(
                './legend',
                $mt->maketext('The Essentials'),
                '...... Its legend should be correct'
            );

            my $i = 0;
            for my $spec (
                {
                    id    => 'uri',
                    title => $mt->maketext('What is the base URI for the mirror?'),
                    label => $mt->maketext('URI'),
                    type  => 'url',
                    phold => 'http://example.com/pgxn',
                    class => 'required url',
                    value => 'http://kineticode.com/pgxn/',
                },
                {
                    id    => 'organization',
                    title => $mt->maketext('Whom should we blame when the mirror dies?'),
                    label => $mt->maketext('Organization'),
                    type  => 'text',
                    phold => 'Full Organization Name',
                    class => 'required',
                    value => 'Kineticode, Inc.',
                },
                {
                    id    => 'email',
                    title => $mt->maketext('Where can we get hold of the responsible party?'),
                    label => $mt->maketext('Email'),
                    type  => 'email',
                    phold => 'pgxn@example.com',
                    class => 'required email',
                    value => 'pgxn@kineticode.com',
                },
                {
                    id    => 'frequency',
                    title => $mt->maketext('How often is the mirror updated?'),
                    label => $mt->maketext('Frequency'),
                    type  => 'text',
                    phold => 'daily/bidaily/.../weekly',
                    class => 'required',
                    value => 'hourly',
                },
                {
                    id    => 'location',
                    title => $mt->maketext('Where can we find this mirror, geographically speaking?'),
                    label => $mt->maketext('Location'),
                    type  => 'text',
                    phold => 'city, (area?, )country, continent (lon lat)',
                    class => 'required',
                    value => 'Portland, OR, USA',
                },
                {
                    id    => 'timezone',
                    title => $mt->maketext('In what time zone can we find the mirror?'),
                    label => $mt->maketext('TZ'),
                    type  => 'text',
                    phold => 'area/Location zoneinfo tz',
                    class => 'required',
                    value => 'America/Los_Angeles',
                },
                {
                    id    => 'bandwidth',
                    title => $mt->maketext('How big is the pipe?'),
                    label => $mt->maketext('Bandwidth'),
                    type  => 'text',
                    phold => '1Gbps, 100Mbps, DSL, etc.',
                    class => 'required',
                    value => '10MBps',
                },
                {
                    id    => 'src',
                    title => $mt->maketext('From what source is the mirror syncing?'),
                    label => $mt->maketext('Source'),
                    type  => 'url',
                    phold => 'rsync://from.which.host/is/this/site/mirroring/from/',
                    class => 'required',
                    value => 'rsync://master.pgxn.org/pgxn/',
                },
                {
                    id    => 'rsync',
                    title => $mt->maketext('Is there a public rsync interface from which other hosts can mirror?'),
                    label => $mt->maketext('Rsync'),
                    type  => 'url',
                    phold => 'rsync://where.your.host/is/offering/a/mirror/',
                    class => '',
                    value => 'rsync://pgxn.kineticode.com/pgxn/',
                },
            ) {
                ++$i;
                $tx->ok("./label[$i]", "...... Test $spec->{id} label", sub {
                    $_->is('./@for', $spec->{id}, '......... Check "for" attr' );
                    $_->is('./@title', $spec->{title}, '......... Check "title" attr' );
                    $_->is('./text()', $spec->{label}, '......... Check its value');
                });
                $tx->ok("./input[$i]", "...... Test $spec->{id} input", sub {
                    $_->is('./@id', $spec->{id}, '......... Check "id" attr' );
                    $_->is('./@name', $spec->{id}, '......... Check "name" attr' );
                    $_->is('./@type', $spec->{type}, '......... Check "type" attr' );
                    $_->is('./@title', $spec->{title}, '......... Check "title" attr' );
                    $_->is('./@class', $spec->{class}, '......... Check "class" attr' );
                    $_->is('./@placeholder', $spec->{phold}, '......... Check "placeholder" attr' );
                    $_->is('./@value', $spec->{value}, '......... Check "value" attr' );
                });
                $tx->ok("./p[$i]", "...... Test $spec->{id} hint", sub {
                    $_->is('./@class', 'hint', '......... Check "class" attr' );
                    $_->is('./text()', $spec->{title}, '......... Check hint body' );
                });
            }
        });

        $tx->ok('./fieldset[2]', '... Test second fieldset', sub {
            $tx->is('./@id', 'mirrornotes', '...... It should have the proper id');
            $tx->is('count(./*)', 4, '...... It should have four subelements');
            $tx->is('./legend', $mt->maketext('Notes'), '...... It should have a legend');
            my $t = $mt->maketext('Anything else we should know about this mirror?');
            $tx->ok('./label', '...... Test the label', sub {
                $_->is('./@for', 'notes', '......... It should be for the right field');
                $_->is('./@title', $t, '......... It should have the title');
                $_->is('./text()', $mt->maketext('Notes'), '......... It should have label');
            });
            $tx->ok('./textarea', '...... Test the textarea', sub {
                $_->is('./@id', 'notes', '......... It should have its id');
                $_->is('./@name', 'notes', '......... It should have its name');
                $_->is('./@title', $t, '......... It should have the title');
                $_->is('./text()', 'This is a note', '......... And it should have the note')
            });
            $tx->is('./p[@class="hint"]', $t, '...... Should have the hint');
        });

        $tx->ok('./input[@type="submit"]', '... Test input', sub {
            for my $attr (
                [id => 'submit'],
                [name => 'submit'],
                [class => 'submit'],
                [value => $mt->maketext('Mirror, Mirror')],
            ) {
                $_->is(
                    "./\@$attr->[0]",
                    $attr->[1],
                    qq{...... Its $attr->[0] attribute should be "$attr->[1]"},
                );
            }
        });
    });
};

# Try to update without specifying PUT.
test_psgi $app => sub {
    my $cb = shift;
    my $req = POST(
        $uri,
        Authorization => 'Basic ' . encode_base64("$admin:****"),
        Content       => [
            uri          => 'http://pgxn.justatheory.com/',
            frequency    => 'daily',
            location     => 'Portland, OR',
            organization => 'Just a Theory',
            timezone     => 'America/Los_Angeles',
            email        => 'pgxn@justatheory.com',
            bandwidth    => '1MBit',
            src          => 'rsync://master.pgxn.org/pgxn',
            rsync        => 'rsync://pgxn.justatheory.com/pgxn',
            notes        => 'IM IN UR DATUH BASEZ.',
        ]
    );

    # Send the request.
    ok my $res = $cb->($req), "POST mirror to $uri";
    ok !$res->is_success, 'It should not be a success';
    is $res->code, 405, 'It should be "405 - not allowed"';

    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($req));
    $req->env->{REMOTE_USER} = $admin;
    $req->env->{SCRIPT_NAME} = '/auth';
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

# Now try with the PUT but nonexistent URI.
test_psgi $app => sub {
    my $uri = '/auth/admin/mirrors/http://pgxn.justatheory.com/?x-tunneled-method=put';
    my $cb = shift;
    my $req = POST(
        $uri,
        Authorization => 'Basic ' . encode_base64("$admin:****"),
        Content       => [
            uri          => 'http://pgxn.justatheory.com/',
            frequency    => 'daily',
            location     => 'Portland, OR',
            organization => 'Just a Theory',
            timezone     => 'America/Los_Angeles',
            email        => 'pgxn@justatheory.com',
            bandwidth    => '1MBit',
            src          => 'rsync://master.pgxn.org/pgxn',
            rsync        => 'rsync://pgxn.justatheory.com/pgxn',
            notes        => 'IM IN UR DATUH BASEZ.',
        ]
    );

    # Send the request.
    ok my $res = $cb->($req), "POST mirror to $uri";
    ok !$res->is_success, 'It should not be a success';
    is $res->code, 404, 'It should be "404 - notfound"';

    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($req));
    $req->env->{REMOTE_USER} = $admin;
    $req->env->{SCRIPT_NAME} = '/auth';
    XPathTest->test_basics($tx, $req, $mt, {
        h1 => 'Edit Mirror',
        page_title  => 'Enter the mirror information provided by the contact',
        validate_form => 1,
    });

    $tx->ok('/html/body/div[@id="content"]', 'Look at the content', sub {
        $tx->is('count(./*)', 4, '... Should have four subelements');
        $tx->is(
            './p[@class="error"]',
            $mt->maketext(q{Update failed; maybe someone deleted this mirror?}),
            '... Should have the error message'
        );
    });
};

# Okay, now submit the PUT for the proper resource, hrm?
test_psgi $app => sub {
    my $uri = '/auth/admin/mirrors/http://kineticode.com/pgxn/?x-tunneled-method=put';
    my $cb = shift;
    my $req = POST(
        $uri,
        Authorization => 'Basic ' . encode_base64("$admin:****"),
        Content       => [
            uri          => 'http://pgxn.kineticode.com/',
            frequency    => 'daily',
            location     => 'Portland, OR',
            organization => 'Just a Theory',
            timezone     => 'America/Los_Angeles',
            email        => 'pgxn@justatheory.com',
            bandwidth    => '1MBit',
            src          => 'rsync://master.pgxn.org/pgxn',
            rsync        => 'rsync://pgxn.justatheory.com/pgxn',
            notes        => 'IM IN UR DATUH BASEZ.',
        ]
    );

    # Send the request.
    ok my $res = $cb->($req), "POST mirror to $uri";
    ok $res->is_redirect, 'It should be a redirect response';

    # Validate we got the expected response.
    $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{SCRIPT_NAME} = '/auth';
    is $res->headers->header('location'), $req->uri_for('/admin/mirrors'),
        'Should redirect to /admin/mirrors';

    # And we should find a mirror with the new URL, but not the old one.
    PGXN::Manager->conn->run(sub {
        is_deeply $_->selectrow_arrayref(q{
            SELECT frequency, location, organization, timezone, contact,
                   bandwidth, src, rsync, notes, created_by
              FROM mirrors
             WHERE uri = ?
        }, undef, 'http://pgxn.kineticode.com/'), [
            'daily', 'Portland, OR', 'Just a Theory', 'America/Los_Angeles',
            'pgxn@justatheory.com', '1MBit', 'rsync://master.pgxn.org/pgxn',
            'rsync://pgxn.justatheory.com/pgxn', 'IM IN UR DATUH BASEZ.',
            $admin
        ], 'Mirror should be updated';

        is_deeply $_->selectcol_arrayref('SELECT uri FROM mirrors ORDER BY uri'),
            ['http://pgxn.example.com/', 'http://pgxn.kineticode.com/'],
            'And there should be only the two expected mirrors';
    });
};

# Now try an XMLHttpRequest
test_psgi $app => sub {
    my $uri = '/auth/admin/mirrors/http://pgxn.kineticode.com/?x-tunneled-method=put';
    my $cb = shift;
    my $req = POST(
        $uri,
        Authorization => 'Basic ' . encode_base64("$admin:****"),
        'X-Requested-With' => 'XMLHttpRequest',
        Content       => [
            uri          => 'http://pgxn.kineticode.com/',
            frequency    => 'hourly',
            location     => 'Portland, OR',
            organization => 'Just a Theory',
            timezone     => 'America/Los_Angeles',
            email        => 'pgxn@justatheory.com',
            bandwidth    => '1MBit',
            src          => 'rsync://master.pgxn.org/pgxn',
            rsync        => 'rsync://pgxn.justatheory.com/pgxn',
            notes        => 'IM IN UR DATUH BASEZ.',
        ]
    );

    # Send the request.
    ok my $res = $cb->($req), "POST mirror to $uri";
    ok $res->is_success, 'It should be a success';
    is $res->content, 'Success', 'And the content should say so';

    # And we should find a mirror with the new data, but not the old one.
    PGXN::Manager->conn->run(sub {
        is $_->selectcol_arrayref(
            'SELECT frequency FROM mirrors WHERE uri = ?',
            undef, 'http://pgxn.kineticode.com/'
        )->[0], 'hourly', 'The frequency should have been updatd';

        is_deeply $_->selectcol_arrayref('SELECT uri FROM mirrors ORDER BY uri'),
            ['http://pgxn.example.com/', 'http://pgxn.kineticode.com/'],
            'And there should still be only the two expected mirrors';
    });
};

# Need to mock user_is_admin to get around dead transactions.
my $rmock = Test::MockModule->new('PGXN::Manager::Request');
$rmock->mock(user_is_admin => 1);

# Awesome. Let's get a URI conflict and see how it handles it.
test_psgi $app => sub {
    my $uri = '/auth/admin/mirrors/http://pgxn.kineticode.com/?x-tunneled-method=put';
    my $cb = shift;
    my $req = POST(
        $uri,
        Authorization => 'Basic ' . encode_base64("$admin:****"),
        Content       => [
            uri          => 'http://pgxn.example.com/',
            frequency    => 'hourly',
            location     => 'Portland, OR',
            organization => 'Just a Theory',
            timezone     => 'America/Los_Angeles',
            email        => 'pgxn@justatheory.com',
            bandwidth    => '1MBit',
            src          => 'rsync://master.pgxn.org/pgxn',
            rsync        => 'rsync://pgxn.justatheory.com/pgxn',
            notes        => 'IM IN UR DATUH BASEZ.',
        ]
    );

    # Send the request.
    ok my $res = $cb->($req), "POST missing data to $uri";
    ok !$res->is_redirect, 'It should not be a redirect response';
    is $res->code, 409, 'Should have 409 status code';

    # So check the content.
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{REMOTE_USER} = $admin;
    $req->env->{SCRIPT_NAME} = '/auth';
    XPathTest->test_basics($tx, $req, $mt, {
        h1 => 'Edit Mirror',
        page_title  => 'Enter the mirror information provided by the contact',
        validate_form => 1,
    });

    # Now verify that we have the error message and that the form fields are
    # higlighted
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 4, '... It should have four subelements');
        $tx->is('./h1', $h1, '... The title h1 should be set');
        $tx->is('./p[1]', $p, '... Intro paragraph should be set');
        my $err = $mt->maketext(
            'Looks like http://pgxn.example.com/ is already registered as a mirror.',
        );
        $tx->is('./p[@class="error"]', $err, '... Error paragraph should be set');

        # Check the form fields.
        $tx->ok('./form[@id="mirrorform"]/fieldset[1]', '... Check first fieldset', sub {
            for my $spec(
                [ uri          => 'required url highlight', 'http://pgxn.kineticode.com/' ],
                [ frequency    => 'required',               'hourly' ],
                [ location     => 'required',               'Portland, OR' ],
                [ organization => 'required',               'Just a Theory' ],
                [ timezone     => 'required',               'America/Los_Angeles' ],
                [ email        => 'required email',         'pgxn@justatheory.com' ],
                [ bandwidth    => 'required',               '1MBit' ],
                [ src          => 'required',               'rsync://master.pgxn.org/pgxn' ],
                [ rsync        => '',                       'rsync://pgxn.justatheory.com/pgxn', ],
            ) {
                $tx->is(
                    qq{./input[\@id="$spec->[0]"]/\@value},
                    $spec->[2],
                    "...... $spec->[0] should have its value",
                );
                $tx->is(
                    qq{./input[\@id="$spec->[0]"]/\@class},
                    $spec->[1],
                    "...... And $spec->[0] should have the proper class",
                );
            }
        });

        $tx->ok('./form[@id="mirrorform"]/fieldset[2]', '... Check second fieldset', sub {
            $tx->is(
                './textarea[@id="notes"]',
                'IM IN UR DATUH BASEZ.',
                '...... Notes textarea should have its value'
            );
        });
    });
};

# Now try with missing values.
TxnTest->restart;
$admin = TxnTest->admin;
create_mirrors();
test_psgi $app => sub {
    my $cb  = shift;
    my $uri = '/auth/admin/mirrors/http://kineticode.com/pgxn/?x-tunneled-method=put';
    my $req = POST(
        $uri,
        Authorization => 'Basic ' . encode_base64("$admin:****"),
        Content       => [],
    );

    # Send the request.
    ok my $res = $cb->($req), "POST missing data to $uri";
    ok !$res->is_redirect, 'It should not be a redirect response';
    is $res->code, 409, 'Should have 409 status code';

    # So check the content.
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{REMOTE_USER} = $admin;
    $req->env->{SCRIPT_NAME} = '/auth';
    XPathTest->test_basics($tx, $req, $mt, {
        h1 => 'Edit Mirror',
        page_title  => 'Enter the mirror information provided by the contact',
        validate_form => 1,
    });

    # Now verify that we have the error message and that the form fields are
    # higlighted
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 4, '... It should have four subelements');
        $tx->is('./h1', $h1, '... The title h1 should be set');
        $tx->is('./p[1]', $p, '... Intro paragraph should be set');
        my $err = $mt->maketext(
            'I think you left something out. Please fill in the missing data in the highlighted fields below.',
        );
        $tx->is('./p[@class="error"]', $err, '... Error paragraph should be set');

        # Check the form fields.
        $tx->ok('./form[@id="mirrorform"]/fieldset[1]', '... Check first fieldset', sub {
            for my $spec(
                [ uri          => 'required url highlight' ],
                [ frequency    => 'required highlight' ],
                [ location     => 'required highlight' ],
                [ organization => 'required highlight' ],
                [ timezone     => 'required highlight' ],
                [ email        => 'required email highlight' ],
                [ bandwidth    => 'required highlight' ],
                [ src          => 'required highlight' ],
                [ rsync        => '' ],
            ) {
                $tx->is(
                    qq{./input[\@id="$spec->[0]"]/\@value},
                    '',
                    "...... $spec->[0] should be empty",
                );
                $tx->is(
                    qq{./input[\@id="$spec->[0]"]/\@class},
                    $spec->[1],
                    "...... And $spec->[0] should have the proper class",
                );
            }
        });

        $tx->ok('./form[@id="mirrorform"]/fieldset[2]', '... Check second fieldset', sub {
            $tx->is(
                './textarea[@id="notes"]',
                '',
                '...... Notes textarea should be empty'
            );
        });
    });
};

# Try with just a subset of missing values.
test_psgi $app => sub {
    my $cb  = shift;
    my $uri = '/auth/admin/mirrors/http://kineticode.com/pgxn/?x-tunneled-method=put';
    my $req = POST(
        $uri,
        Authorization => 'Basic ' . encode_base64("$admin:****"),
        Content       => [
            uri          => 'http://pgxn.justatheory.com/',
            frequency    => 'daily',
            location     => 'Portland, OR',
        ],
    );

    # Send the request.
    ok my $res = $cb->($req), "POST missing data to $uri";
    ok !$res->is_redirect, 'It should not be a redirect response';
    is $res->code, 409, 'Should have 409 status code';

    # So check the content.
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{REMOTE_USER} = $admin;
    $req->env->{SCRIPT_NAME} = '/auth';
    XPathTest->test_basics($tx, $req, $mt, {
        h1 => 'Edit Mirror',
        page_title  => 'Enter the mirror information provided by the contact',
        validate_form => 1,
    });

    # Now verify that we have the error message and that the form fields are
    # higlighted
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 4, '... It should have four subelements');
        $tx->is('./h1', $h1, '... The title h1 should be set');
        $tx->is('./p[1]', $p, '... Intro paragraph should be set');
        my $err = $mt->maketext(
            'I think you left something out. Please fill in the missing data in the highlighted fields below.',
        );
        $tx->is('./p[@class="error"]', $err, '... Error paragraph should be set');

        # Check the form fields.
        $tx->ok('./form[@id="mirrorform"]/fieldset[1]', '... Check first fieldset', sub {
            for my $spec(
                [ uri          => 'required url',  'http://pgxn.justatheory.com/'],
                [ frequency    => 'required',      'daily'],
                [ location     => 'required',       'Portland, OR'],
                [ organization => 'required highlight' ],
                [ timezone     => 'required highlight' ],
                [ email        => 'required email highlight' ],
                [ bandwidth    => 'required highlight' ],
                [ src          => 'required highlight' ],
                [ rsync        => '' ],
            ) {
                $tx->is(
                    qq{./input[\@id="$spec->[0]"]/\@value},
                    $spec->[2] || '',
                    "...... $spec->[0] should have the expected value",
                );
                $tx->is(
                    qq{./input[\@id="$spec->[0]"]/\@class},
                    $spec->[1],
                    "...... And $spec->[0] should have the proper class",
                );
            }
        });

        $tx->ok('./form[@id="mirrorform"]/fieldset[2]', '... Check second fieldset', sub {
            $tx->is(
                './textarea[@id="notes"]',
                '',
                '...... Notes textarea should be empty'
            );
        });
    });
};

sub create_mirrors {
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
                contact      := $8,
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
            'http://pgxn.example.com/',
            'weekly',
            'Springfield, USA',
            '1KBps',
            'Simpsonvile',
            'America/Chicago',
            'pgxn@example.com',
            'rsync://master.pgxn.org/pgxn/',
            '',
            '',
        );
    });
}
