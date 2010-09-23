#!/usr/bin/env perl

use 5.12.0;
use utf8;
use Test::More tests => 108;
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

my $mt = PGXN::Manager::Locale->accept('en');

# Request a registration form.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET '/request'), 'Fetch /request';
    is $res->code, 200, 'Should get 200 response';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    XPathTest->test_basics($tx, $req, $mt, {
        desc        => $mt->maketext('Request a PGXN Account and start distributing your PostgreSQL extensions!'),
        keywords    => 'pgxn,postgresql,distribution,register,account,user,nickname',
        h1          => $mt->maketext('Request an Account'),
    });

    # Examine the form.
    $tx->ok('/html/body/div[@id="content"]/form[@id="reqform"]', sub {
        my $tx = shift;
        for my $attr (
            [action  => '/register'],
            [enctype => 'application/x-www-form-urlencoded'],
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
            my $tx = shift;
            $tx->is('./@id', 'reqessentials', '...... It should have the proper id');
            $tx->is('count(./*)', 9, '...... It should have nine subelements');
            $tx->is(
                './legend',
                $mt->maketext('The Essentials'),
                '...... Its legend should be correct'
            );
            my $i = 0;
            for my $spec (
                {
                    id    => 'name',
                    title => $mt->maketext('What does your mother call you?'),
                    label => $mt->maketext('Name'),
                    type  => 'text',
                    phold => 'Barack Obama',
                },
                {
                    id    => 'email',
                    title => $mt->maketext('Where can we get hold of you?'),
                    label => $mt->maketext('Email'),
                    type  => 'email',
                    phold => 'you@example.com',
                },
                {
                    id    => 'uri',
                    title => $mt->maketext('Got a blog or personal site?'),
                    label => $mt->maketext('URI'),
                    type  => 'url',
                    phold => 'http://blog.example.com/',
                },
                {
                    id    => 'nickname',
                    title => $mt->maketext('By what name would you like to be known? Letters, numbers, and dashes only, please.'),
                    label => $mt->maketext('Nickname'),
                    type  => 'text',
                    phold => 'bobama',
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
                    $_->is('./@placeholder', $spec->{phold}, '......... Check "placeholder" attr' );
                });
            }
        });
        $tx->ok('./fieldset[2]', '... Test second fieldset', sub {
            $tx->is('./@id', 'reqwhy', '...... It should have the proper id');
            $tx->is('count(./*)', 3, '...... It should have three subelements');
            $tx->is('./legend', $mt->maketext('Your Plans'), '...... It should have a legend');
            my $t = $mt->maketext('So what are your plans for PGXN? What do you wanna release?');
            $tx->ok('./label', '...... Test the label', sub {
                $_->is('./@for', 'why', '......... It should be for the right field');
                $_->is('./@title', $t, '......... It should have the title');
                $_->is('./text()', $mt->maketext('Why'), '......... It should have label');
            });
            $tx->ok('./textarea', '...... Test the textarea', sub {
                $_->is('./@id', 'why', '......... It should have its id');
                $_->is('./@name', 'why', '......... It should have its name');
                $_->is('./@title', $t, '......... It should have the title');
                $_->is('./@placeholder', $mt->maketext('I would like to release the following killer extensions on PGXN:

* foo
* bar
* baz', '......... It should have its placeholder'));
                $_->is('./text()', '', '......... And it should be empty')
            });
        });
        $tx->ok('./input[@type="submit"]', '... Test input', sub {
            for my $attr (
                [id => 'submit'],
                [name => 'submit'],
                [class => 'submit'],
                [value => $mt->maketext('Pretty Please!')],
            ) {
                $_->is(
                    "./\@$attr->[0]",
                    $attr->[1],
                    qq{...... Its $attr->[0] attribute should be "$attr->[1]"},
                );
            }
        });
    }, 'Test request form');
};
