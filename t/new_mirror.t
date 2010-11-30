#!/usr/bin/env perl -w

use 5.12.0;
use utf8;
use Test::More tests => 252;
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
my $uri      = '/auth/admin/mirrors/new';
my $user     = TxnTest->user;
my $admin    = TxnTest->admin;
my $h1       = $mt->maketext('New Mirror');
my $p        = $mt->maketext(q{If someone has created a new mirror and sent in the essentials, update the mirror list by adding it here.});

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

# Request a new mirror form as an authenticated user.
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
        h1 => 'New Mirror',
        validate_form => '#mirrorform',
        page_title => 'Enter the mirror information provided by the contact',
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
            $tx->is('count(./*)', 22, '...... It should have 22 subelements');
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
                },
                {
                    id    => 'email',
                    title => $mt->maketext('Whom should we blame when the mirror dies?'),
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
                    type  => 'url',
                    phold => 'rsync://from.which.host/is/this/site/mirroring/from/',
                    class => 'required',
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
