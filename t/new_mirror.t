#!/usr/bin/env perl -w

use 5.10.0;
use strict;
use warnings;
use utf8;

use Test::More tests => 1068;
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
use Test::File;
use Test::File::Contents;
use Test::NoWarnings;
use Encode;
use lib 't/lib';
use TxnTest;
use XPathTest;

my $app      = PGXN::Manager::Router->app;
my $mt       = PGXN::Manager::Locale->accept('en');
my $uri      = '/admin/mirrors/new';
my $user     = TxnTest->user;
my $admin    = TxnTest->admin;
my $h1       = $mt->maketext('New Mirror');
my $p        = $mt->maketext(q{All fields except "Note" are required. Thanks for keeping the rsync mirror index up-to-date!});
my $hparams  = {
    h1 => 'New Mirror',
    validate_form => '#mirrorform',
    page_title => 'Enter the mirror information provided by the contact',
};

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
    my $req = GET $uri, Authorization => 'Basic ' . encode_base64("$user:test-passW0rd");

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

# Request a new mirror form as an authenticated user.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb  = shift;
    my $req = GET $uri, Authorization => 'Basic ' . encode_base64("$admin:test-passW0rd");

    ok my $res = $cb->($req), "Get $uri with auth token";
    ok $res->is_success, 'Response should be success';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($req));
    $req->env->{REMOTE_USER} = $admin;
    XPathTest->test_basics($tx, $req, $mt, $hparams);

    # Check the content
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 3, '... It should have three subelements');
        $tx->is('./h1', $h1, '... The title h1 should be set');
        $tx->is('./p', $p, '... Intro paragraph should be set');
    });

    # Now examine the form.
    $tx->ok('/html/body/div[@id="content"]/form[@id="mirrorform"]', sub {
        for my $attr (
            [action  => $req->uri_for('/admin/mirrors')],
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
                    phold => 'https://example.com/pgxn',
                    class => 'required url',
                },
                {
                    id    => 'organization',
                    title => $mt->maketext('Whom should we blame when the mirror dies?'),
                    label => $mt->maketext('Organization'),
                    type  => 'text',
                    phold => 'Full Organization Name',
                    class => 'required',
                },
                {
                    id    => 'email',
                    title => $mt->maketext('Where can we get hold of the responsible party?'),
                    label => $mt->maketext('Email'),
                    type  => 'email',
                    phold => 'pgxn@example.com',
                    class => 'required email',
                },
                {
                    id    => 'frequency',
                    title => $mt->maketext('How often is the mirror updated?'),
                    label => $mt->maketext('Frequency'),
                    type  => 'text',
                    phold => 'daily/bidaily/.../weekly',
                    class => 'required',
                },
                {
                    id    => 'location',
                    title => $mt->maketext('Where can we find this mirror, geographically speaking?'),
                    label => $mt->maketext('Location'),
                    type  => 'text',
                    phold => 'city, (area?, )country, continent (lon lat)',
                    class => 'required',
                },
                {
                    id    => 'timezone',
                    title => $mt->maketext('In what time zone can we find the mirror?'),
                    label => $mt->maketext('TZ'),
                    type  => 'text',
                    phold => 'area/Location zoneinfo tz',
                    class => 'required',
                },
                {
                    id    => 'bandwidth',
                    title => $mt->maketext('How big is the pipe?'),
                    label => $mt->maketext('Bandwidth'),
                    type  => 'text',
                    phold => '1Gbps, 100Mbps, DSL, etc.',
                    class => 'required',
                },
                {
                    id    => 'src',
                    title => $mt->maketext('From what source is the mirror syncing?'),
                    label => $mt->maketext('Source'),
                    type  => 'rsync',
                    phold => 'rsync://from.which.host/is/this/site/mirroring/from/',
                    class => 'required',
                },
                {
                    id    => 'rsync',
                    title => $mt->maketext('Is there a public rsync interface from which other hosts can mirror?'),
                    label => $mt->maketext('Rsync'),
                    type  => 'rsync',
                    phold => 'rsync://where.your.host/is/offering/a/mirror/',
                    class => '',
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
                $_->is('./text()', '', '......... And it should be empty')
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

# Set up the mirror root.
my $pgxn = PGXN::Manager->instance;
my $meta = File::Spec->catfile($pgxn->config->{mirror_root}, 'meta', 'mirrors.json');
END { remove_tree $pgxn->config->{mirror_root} }
file_not_exists_ok $meta, "mirrors.json should not exist";

# Okay, let's submit the form.
$uri = '/admin/mirrors';
test_psgi $app => sub {
    my $cb = shift;
    my $req = POST(
        $uri,
        Authorization => 'Basic ' . encode_base64("$admin:test-passW0rd"),
        Content       => [
            uri          => 'http://pgxn.justatheory.com/',
            frequency    => 'daily',
            location     => 'Portland, OR',
            organization => 'Jüst a Theory',
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
    is $res->headers->header('location'), $req->uri_for('/admin/mirrors'),
        'Should redirect to /admin/mirrors';

    # And now the mirror should exist.
    PGXN::Manager->conn->run(sub {
        is_deeply $_->selectrow_arrayref(q{
            SELECT frequency, location, organization, timezone, email,
                   bandwidth, src, rsync, notes, created_by
              FROM mirrors
             WHERE uri = ?
        }, undef, 'http://pgxn.justatheory.com/'), [
            'daily', 'Portland, OR', 'Jüst a Theory', 'America/Los_Angeles',
            'pgxn@justatheory.com', '1MBit', 'rsync://master.pgxn.org/pgxn',
            'rsync://pgxn.justatheory.com/pgxn', 'IM IN UR DATUH BASEZ.',
            $admin
        ], 'New mirror should exist';

        # And so should mirrors.json.
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

# Now try an XMLHttpRequest
test_psgi $app => sub {
    my $cb = shift;
    my $req = POST(
        $uri,
        Authorization => 'Basic ' . encode_base64("$admin:test-passW0rd"),
        'X-Requested-With' => 'XMLHttpRequest',
        Content       => [
            uri          => 'http://pgxn.kineticode.com/',
            frequency    => 'daily',
            location     => 'Portland, OR',
            organization => 'Kineticode, Inc.',
            timezone     => 'America/Los_Angeles',
            email        => 'pgxn@kineticode.com',
            bandwidth    => '24 baud',
            src          => 'rsync://master.pgxn.org/pgxn',
            rsync        => '',
            notes        => '',
        ]
    );

    # Send the request.
    ok my $res = $cb->($req), "POST mirror to $uri";
    ok $res->is_success, 'It should be a success';
    is $res->content, 'Success', 'And the content should say so';

    # And now the mirror should exist.
    PGXN::Manager->conn->run(sub {
        is_deeply $_->selectrow_arrayref(q{
            SELECT frequency, location, organization, timezone, email,
                   bandwidth, src, rsync, notes, created_by
              FROM mirrors
             WHERE uri = ?
        }, undef, 'http://pgxn.kineticode.com/'), [
            'daily', 'Portland, OR', 'Kineticode, Inc.', 'America/Los_Angeles',
            'pgxn@kineticode.com', '24 baud', 'rsync://master.pgxn.org/pgxn',
            '', '',
            $admin
        ], 'Second mirror should exist';


        # And so should mirrors.json.
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

# Need to mock user_is_admin to get around dead transactions.
my $rmock = Test::MockModule->new('PGXN::Manager::Request');
$rmock->mock(user_is_admin => 1);

# Awesome. Let's get a URI conflict and see how it handles it.
test_psgi $app => sub {
    my $cb = shift;
    my $req = POST(
        $uri,
        Authorization => 'Basic ' . encode_base64("$admin:test-passW0rd"),
        Content       => [
            uri          => 'http://pgxn.justatheory.com/',
            frequency    => 'daily',
            location     => 'Portland, OR',
            organization => 'Jüst a Theory',
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
    ok !$res->is_redirect, 'It should not be a redirect response';
    is $res->code, 409, 'Should have 409 status code';

    # So check the content.
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{REMOTE_USER} = $admin;
    XPathTest->test_basics($tx, $req, $mt, $hparams);

    # Now verify that we have the error message and that the form fields are
    # filled-in.
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 4, '... It should have four subelements');
        $tx->is('./h1', $h1, '... The title h1 should be set');
        $tx->is('./p[1]', $p, '... Intro paragraph should be set');
        my $err = $mt->maketext(
            'Looks like [_1] is already registered as a mirror.',
            'http://pgxn.justatheory.com/'
        );
        $tx->is('./p[@class="error"]', $err, '... Error paragraph should be set');

        # Check the form fields.
        $tx->ok('./form[@id="mirrorform"]/fieldset[1]', '... Check first fieldset', sub {
            for my $spec(
                [ uri          => '',                                  'required url highlight'],
                [ frequency    => 'daily',                             'required' ],
                [ location     => 'Portland, OR',                      'required' ],
                [ organization => 'Jüst a Theory',                     'required' ],
                [ timezone     => 'America/Los_Angeles',               'required' ],
                [ email        => 'pgxn@justatheory.com',              'required email' ],
                [ bandwidth    => '1MBit',                             'required' ],
                [ src          => 'rsync://master.pgxn.org/pgxn',      'required' ],
                [ rsync        => 'rsync://pgxn.justatheory.com/pgxn', '' ],
            ) {
                $tx->is(
                    qq{./input[\@id="$spec->[0]"]/\@value},
                    $spec->[1],
                    "...... $spec->[0] should be set",
                );
                $tx->is(
                    qq{./input[\@id="$spec->[0]"]/\@class},
                    $spec->[2],
                    "...... And $spec->[0] should have the proper class",
                );
            }
        });

        $tx->ok('./form[@id="mirrorform"]/fieldset[2]', '... Check second fieldset', sub {
            $tx->is(
                './textarea[@id="notes"]',
                'IM IN UR DATUH BASEZ.',
                '...... Notes textarea should be set'
            );
        });
    });
};

# Now try with missing values.
TxnTest->restart;
$admin = TxnTest->admin;
test_psgi $app => sub {
    my $cb = shift;
    my $req = POST(
        $uri,
        Authorization => 'Basic ' . encode_base64("$admin:test-passW0rd"),
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
    XPathTest->test_basics($tx, $req, $mt, $hparams);

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

# Try again with an XmlHttpRequest
test_psgi $app => sub {
    my $cb = shift;
    my $req = POST(
        $uri,
        Authorization => 'Basic ' . encode_base64("$admin:test-passW0rd"),
        'X-Requested-With' => 'XMLHttpRequest',
        Content       => [],
    );

    # Send the request.
    ok my $res = $cb->($req), "POST missing data to $uri";
    ok !$res->is_redirect, 'It should not be a redirect response';
    is $res->code, 409, 'Should have 409 status code';

    is $res->decoded_content, $mt->maketext(
        'Missing values for [qlist,_1].',
        [qw(uri email frequency organization location timezone bandwidth src)],
        'It should have the proper content',
    );
};

# Try with just a subset of missing values.
test_psgi $app => sub {
    my $cb = shift;
    my $req = POST(
        $uri,
        Authorization => 'Basic ' . encode_base64("$admin:test-passW0rd"),
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
    XPathTest->test_basics($tx, $req, $mt, $hparams);

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

# Try an invalid time zone.
test_psgi $app => sub {
    my $cb = shift;
    my $req = POST(
        $uri,
        Authorization => 'Basic ' . encode_base64("$admin:test-passW0rd"),
        Content       => [
            uri          => 'http://pgxn.justatheory.com/',
            frequency    => 'daily',
            location     => 'Portland, OR',
            organization => 'Jüst a Theory',
            timezone     => 'America/Funky_Time',
            email        => 'pgxn@justatheory.com',
            bandwidth    => '1MBit',
            src          => 'rsync://master.pgxn.org/pgxn',
            rsync        => 'rsync://pgxn.justatheory.com/pgxn',
            notes        => 'IM IN UR DATUH BASEZ.',
        ]
    );

    # Send the request.
    ok my $res = $cb->($req), "POST mirror to $uri with invalid time zone";
    ok !$res->is_redirect, 'It should not be a redirect response';
    is $res->code, 409, 'Should have 409 status code';

    # So check the content.
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{REMOTE_USER} = $admin;
    XPathTest->test_basics($tx, $req, $mt, $hparams);

    # Now verify that we have the error message and that the form fields are
    # filled-in.
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 4, '... It should have four subelements');
        $tx->is('./h1', $h1, '... The title h1 should be set');
        $tx->is('./p[1]', $p, '... Intro paragraph should be set');
        my $err = $mt->maketext(
            'Sorry, the time zone “[_1]” is invalid.',
            'America/Funky_Time',
        );
        $tx->is('./p[@class="error"]', $err, '... Error paragraph should be set');

        # Check the form fields.
        $tx->ok('./form[@id="mirrorform"]/fieldset[1]', '... Check first fieldset', sub {
            for my $spec(
                [ uri          => 'http://pgxn.justatheory.com/',      'required url'],
                [ frequency    => 'daily',                             'required' ],
                [ location     => 'Portland, OR',                      'required' ],
                [ organization => 'Jüst a Theory',                     'required' ],
                [ timezone     => '',                                  'required highlight' ],
                [ email        => 'pgxn@justatheory.com',              'required email' ],
                [ bandwidth    => '1MBit',                             'required' ],
                [ src          => 'rsync://master.pgxn.org/pgxn',      'required' ],
                [ rsync        => 'rsync://pgxn.justatheory.com/pgxn', '' ],
            ) {
                $tx->is(
                    qq{./input[\@id="$spec->[0]"]/\@value},
                    $spec->[1],
                    "...... $spec->[0] should be set",
                );
                $tx->is(
                    qq{./input[\@id="$spec->[0]"]/\@class},
                    $spec->[2],
                    "...... And $spec->[0] should have the proper class",
                );
            }
        });

        $tx->ok('./form[@id="mirrorform"]/fieldset[2]', '... Check second fieldset', sub {
            $tx->is(
                './textarea[@id="notes"]',
                'IM IN UR DATUH BASEZ.',
                '...... Notes textarea should be set'
            );
        });
    });
};

# Try an invalid time email.
TxnTest->restart;
$admin = TxnTest->admin;
test_psgi $app => sub {
    my $cb = shift;
    my $req = POST(
        $uri,
        Authorization => 'Basic ' . encode_base64("$admin:test-passW0rd"),
        Content       => [
            uri          => 'http://pgxn.justatheory.com/',
            frequency    => 'daily',
            location     => 'Portland, OR',
            organization => 'Jüst a Theory',
            timezone     => 'America/Los_Angeles',
            email        => 'foo at bar dot com',
            bandwidth    => '1MBit',
            src          => 'rsync://master.pgxn.org/pgxn',
            rsync        => 'rsync://pgxn.justatheory.com/pgxn',
            notes        => 'IM IN UR DATUH BASEZ.',
        ]
    );

    # Send the request.
    ok my $res = $cb->($req), "POST mirror to $uri with invalid email";
    ok !$res->is_redirect, 'It should not be a redirect response';
    is $res->code, 409, 'Should have 409 status code';

    # So check the content.
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{REMOTE_USER} = $admin;
    XPathTest->test_basics($tx, $req, $mt, $hparams);

    # Now verify that we have the error message and that the form fields are
    # filled-in.
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        $tx->is('count(./*)', 4, '... It should have four subelements');
        $tx->is('./h1', $h1, '... The title h1 should be set');
        $tx->is('./p[1]', $p, '... Intro paragraph should be set');
        my $err = $mt->maketext(
            q{Hrm, “[_1]” doesn't look like an email address. Care to try again?},
            'foo at bar dot com',
        );
        $tx->is('./p[@class="error"]', $err, '... Error paragraph should be set');

        # Check the form fields.
        $tx->ok('./form[@id="mirrorform"]/fieldset[1]', '... Check first fieldset', sub {
            for my $spec(
                [ uri          => 'http://pgxn.justatheory.com/',      'required url'],
                [ frequency    => 'daily',                             'required' ],
                [ location     => 'Portland, OR',                      'required' ],
                [ organization => 'Jüst a Theory',                     'required' ],
                [ timezone     => 'America/Los_Angeles',               'required' ],
                [ email        => '',              'required email highlight' ],
                [ bandwidth    => '1MBit',                             'required' ],
                [ src          => 'rsync://master.pgxn.org/pgxn',      'required' ],
                [ rsync        => 'rsync://pgxn.justatheory.com/pgxn', '' ],
            ) {
                $tx->is(
                    qq{./input[\@id="$spec->[0]"]/\@value},
                    $spec->[1],
                    "...... $spec->[0] should be set",
                );
                $tx->is(
                    qq{./input[\@id="$spec->[0]"]/\@class},
                    $spec->[2],
                    "...... And $spec->[0] should have the proper class",
                );
            }
        });

        $tx->ok('./form[@id="mirrorform"]/fieldset[2]', '... Check second fieldset', sub {
            $tx->is(
                './textarea[@id="notes"]',
                'IM IN UR DATUH BASEZ.',
                '...... Notes textarea should be set'
            );
        });
    });
};

# Try invalid URIs.
for my $field (qw(uri src rsync)) {
    TxnTest->restart;
    $admin = TxnTest->admin;
    my %content = (
        uri          => 'http://pgxn.justatheory.com/',
        frequency    => 'daily',
        location     => 'Portland, OR',
        organization => 'Jüst a Theory',
        timezone     => 'America/Los_Angeles',
        email        => 'foo@bar.com',
        bandwidth    => '1MBit',
        src          => 'rsync://master.pgxn.org/pgxn',
        rsync        => 'rsync://pgxn.justatheory.com/pgxn',
        notes        => 'IM IN UR DATUH BASEZ.',
    );
    $content{$field} = 'whatever man';
    my $err = $mt->maketext(
        q{Hrm, “[_1]” doesn't look like a URI. Care to try again?},
        'whatever man',
    );

    # Try an HTML request first.
    test_psgi $app => sub {
        my $cb = shift;
        $content{$field} = 'whatever man';
        my $req = POST(
            $uri,
            Authorization => 'Basic ' . encode_base64("$admin:test-passW0rd"),
            Content       => [%content],
        );

        # Send the request.
        ok my $res = $cb->($req), "POST mirror to $uri with invalid $field";
        ok !$res->is_redirect, 'It should not be a redirect response';
        is $res->code, 409, 'Should have 409 status code';

        # So check the content.
        is_well_formed_xml $res->content, 'The HTML should be well-formed';
        my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

        $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
        $req->env->{REMOTE_USER} = $admin;
            XPathTest->test_basics($tx, $req, $mt, $hparams);

        # Now verify that we have the error message and that the form fields are
        # filled-in.
        $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
            $tx->is('count(./*)', 4, '... It should have four subelements');
            $tx->is('./h1', $h1, '... The title h1 should be set');
            $tx->is('./p[1]', $p, '... Intro paragraph should be set');
            $tx->is('./p[@class="error"]', $err, '... Error paragraph should be set');

            # Check the form fields.
            $tx->ok('./form[@id="mirrorform"]/fieldset[1]', '... Check first fieldset', sub {
                my %specs = (
                    uri          => [ 'http://pgxn.justatheory.com/',      'required url'],
                    frequency    => [ 'daily',                             'required' ],
                    location     => [ 'Portland, OR',                      'required' ],
                    organization => [ 'Jüst a Theory',                     'required' ],
                    timezone     => [ 'America/Los_Angeles',               'required' ],
                    email        => [ 'foo@bar.com',                       'required email' ],
                    bandwidth    => [ '1MBit',                             'required' ],
                    src          => [ 'rsync://master.pgxn.org/pgxn',      'required' ],
                    rsync        => [ 'rsync://pgxn.justatheory.com/pgxn', '' ],
                );
                $specs{$field}[0] = '';
                $specs{$field}[1] = $specs{$field}[1]
                    ? "$specs{$field}[1] highlight"
                    : 'highlight';
                while (my ($param, $spec) = each %specs) {
                    $tx->is(
                        qq{./input[\@id="$param"]/\@value},
                        $spec->[0],
                        "...... $param should be set",
                    );
                    $tx->is(
                        qq{./input[\@id="$param"]/\@class},
                        $spec->[1],
                        "...... And $param should have the proper class",
                    );
                }
            });

            $tx->ok('./form[@id="mirrorform"]/fieldset[2]', '... Check second fieldset', sub {
                $tx->is(
                    './textarea[@id="notes"]',
                    'IM IN UR DATUH BASEZ.',
                    '...... Notes textarea should be set'
                );
            });
        });
    };

    # Now try an XmlHttpRequest request first.
    TxnTest->restart;
    $admin = TxnTest->admin;
    test_psgi $app => sub {
        my $cb = shift;
        my $req = POST(
            $uri,
            Authorization => 'Basic ' . encode_base64("$admin:test-passW0rd"),
            'X-Requested-With' => 'XMLHttpRequest',
            Content       => [%content],
        );

        # Send the request.
        ok my $res = $cb->($req), "XmlHttpRequest POST mirror to $uri with invalid $field";
        ok !$res->is_redirect, 'It should not be a redirect response';
        is $res->code, 409, 'Should have 409 status code';

        is $res->decoded_content, $err, 'It should return the expected error message';
    };
}
