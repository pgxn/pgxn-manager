#!/usr/bin/env perl

use 5.12.0;
use utf8;
use Test::More tests => 41;
#use Test::More 'no_plan';
use Test::XML;
use Test::XPath;
use PGXN::Manager::Request;
use HTTP::Request::Common;
use HTTP::Message::PSGI;

BEGIN {
    use_ok 'PGXN::Manager::Templates';
}

Template::Declare->init( dispatch_to => ['PGXN::Manager::Templates'] );

ok my $req = PGXN::Manager::Request->new(req_to_psgi(GET '/')),
    'Create a Plack request object';
my $mt = PGXN::Manager::Maketext->accept($req->env->{HTTP_ACCEPT_LANGUAGE});

ok my $html = Template::Declare->show('home', $req, {
    description => 'Whatever desc',
    keywords    => 'yes,no',
}), 'Show home';

is_well_formed_xml $html, 'The HTML should be well-formed';
my $tx = Test::XPath->new( xml => $html, is_html => 1 );
test_basics($tx, $req, $mt, {
    desc        => 'Whatever desc',
    keywords    => 'yes,no',
    h1          => $mt->maketext('Welcome'),
});

# Try in french.
$req->env->{HTTP_ACCEPT_LANGUAGE} = 'fr';
ok $html = Template::Declare->show('home', $req ), 'Show French home';
is_well_formed_xml $html, 'French HTML should be well-formed';
my $tx = Test::XPath->new( xml => $html, is_html => 1 );
$tx->is(
    '/html/body/div[@id="content"]/h1',
    'Bienvenue',
    'French HTML should have localized h1'
);

# Call this function for every request to make sure that they all
# have the same basic structure.
sub test_basics {
    my ($tx, $req, $mt, $p) = @_;

    # Some basic sanity-checking.
    $tx->is( 'count(/html)',      1, 'Should have 1 html element' );
    $tx->is( 'count(/html/head)', 1, 'Should have 1 head element' );
    $tx->is( 'count(/html/body)', 1, 'Should have 1 body element' );

    # Check the head element.
    $tx->ok('/html/head', 'Test head', sub {
        $_->is('count(./*)', 6, 'Should have 6 elements below "head"');

        $_->is(
            './meta[@http-equiv="Content-Type"]/@content',
            'text/html; charset=UTF-8',
            'Should have the content-type set in a meta header',
        );

        $_->is('./title', $mt->maketext('main_title'), 'Title should be corect');

        $_->is(
            './meta[@name="generator"]/@content',
            'PGXN::Manager ' . PGXN::Manager->VERSION,
            'Should have generator'
        );

        $_->is(
            './meta[@name="description"]/@content',
            $p->{desc},
            'Should have the description meta header'
        ) if $p->{desc};

        $_->is(
            './meta[@name="keywords"]/@content',
            $p->{keywords},
            'Should have the keywords meta header'
        ) if $p->{keywords};

        $_->is(
            './link[@type="text/css"][@rel="stylesheet"]/@href',
            $req->base . 'ui/css/screen.css',
            'Should load the CSS',
        );

        my $ie_uri = $req->base . 'ui/css/fix.css';
        $_->is(
            './comment()',
            "[if IE 6]>\n"
            . qq{  <link rel="stylesheet" type="text/css" href="$ie_uri" />\n}
            . '  <![endif]',
            'Should have IE6 fix comment');
    });

    # Test the body.
    $tx->is('count(/html/body/*)', 2, 'Should have two elements below body');

    # Check the content section.
    $tx->ok('/html/body/div[@id="content"]', 'Test content', sub {
        $_->is('./h1', $p->{h1}, "Should have h1");
    });

    # Test the sidebar section.
    $tx->ok( '/html/body/div[@id="sidebar"]', 'Test sidebar', sub {
        $_->is('count(./*)', 4, 'Should have four sidebar subelements');

        $_->is('./img/@src', $req->base . 'ui/img/logo.png', 'Should have logo');
        $_->is('./h1', $mt->maketext('PGXN Manager'), 'Should have name');
        $_->is('./h2', $mt->maketext('tagline'), 'Should have tagline');

        $_->ok('./ul[@id="menu"]', 'Test menu', sub {
            $_->is('count(./*)', 5, 'Should have 7 menue subelements');
            $_->is('count(./li)', 5, 'And they should all be list items');

            my $i = 0;
            for my $spec (
                [ '/', 'Home' ],
                [ '/request', 'Request Account' ],
                [ '/forgot', 'Forgot Password' ],
                [ '/about', 'About' ],
                [ '/contact', 'Contact' ],
            ) {
                $i++;
                $_->is(
                    "count(./li[$i]/*)", 1,
                    "Should be one subelement of menu item $i"
                );
                $_->is(
                    "./li[$i]/a/\@class", 'active',
                    "Link $i should be active"
                ) if $req->path eq $spec->[0];
                my $uri = $req->uri_for($spec->[0]);
                $_->is(
                    qq{./li[$i]/a[\@href="$uri"]},
                    $spec->[1],
                    "Link $i should be to $uri"
                );
            }

        });

    });
}
