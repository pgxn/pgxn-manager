#!/usr/bin/env perl

use 5.12.0;
use utf8;
use Test::More tests => 72;
#use Test::More 'no_plan';
use Plack::Test;
use HTTP::Request::Common;
use PGXN::Manager::Router;
use HTTP::Message::PSGI;
use Test::XML;
use Test::XPath;
use MIME::Base64;
use lib 't/lib';
use TxnTest;
use XPathTest;

my $user     = TxnTest->user;
my $app      = PGXN::Manager::Router->app;
my $mt       = PGXN::Manager::Locale->accept('en');
my $desc     = $mt->maketext(q{Upload an archive file with your PGXN extensions in it. It will be distributed on PGXN and mirrored to all the networks.});
my $keywords = 'pgxn,postgresql,distribution,upload,release,archive,extension,mirror,network';
my $h1       = $mt->maketext('Upload a Distribution');
my $p        = $mt->maketext(q{So you've developed a PGXN extension and what to distribute it on PGXN. This is the place to upload it! Just find your distribution archive (.zip, .tgz, etc.) in the upload field below and you'll be good to go.});
my $hparams  = {
    desc          => $desc,
    keywords      => $keywords,
    h1            => $h1,
};

# Connect without authenticating.
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET '/auth/upload'), 'GET /auth/upload';
    is $res->code, 401, 'Should get 401 response';
    like $res->content, qr/Authorization required/,
        'The body should indicate need for authentication';
};

test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET(
        '/auth/upload',
        Authorization => 'Basic ' . encode_base64("$user:****"),
    )), 'Fetch /auth/upload';
    ok $res->is_success, 'Should get a successful response';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{REMOTE_USER} = $user;
    XPathTest->test_basics($tx, $req, $mt, $hparams);

    # Check content.
    $tx->ok('/html/body/div[@id="content"]', 'Look at the content', sub {
        $tx->is('count(./*)', 3, '... Should have three subelements');
        $tx->is(
            './p',
            $mt->maketext(q{So you've developed a PGXN extension and what to distribute it on PGXN. This is the place to upload it! Just find your distribution archive (.zip, .tgz, etc.) in the upload field below and you'll be good to go.}),
            'Paragraph should be there'
        );
        $tx->ok('./form[@id="upform"]', 'Test upload form', sub {
            $tx->is(
                './@action',
                $req->uri_for('/auth/upload'),
                '......Should have proper action'
            );
            $tx->is('./@enctype', 'multipart/form-data', '...... Should have enctype');
            $tx->is('./@method', 'post', '...... Should have method=post');
            $tx->is('count(./*)', 2, '...... Should have two subelements');
            $tx->ok('./fieldset[@id="uploadit"]', '...... Test fieldset', sub {
                $tx->is('count(./*)', 3, '......... Should have three subelements');
                $tx->is(
                    './legend',
                    $mt->maketext('Upload a Distribution Archive'),
                    '......... Should have legend'
                );
                $tx->is(
                    './label[@for="archive"]',
                    $mt->maketext('Archive'),
                    '......... Should have upload label'
                );
                $tx->is(
                    './label[@for="archive"]/@title',
                    $mt->maketext('Select an archive file to upload.'),
                    '......... And it should have a title'
                );
                $tx->ok('./input[@id="archive"]', '......... Test archive', sub {
                    $tx->is('./@type', 'file', '............ It should be a file field' );
                    $tx->is('./@name', 'archive', '............ It should have a name' );
                    $tx->is(
                        './@title',
                        $mt->maketext('Upload your distribution archive file here.'),
                        '............ It should have a title'
                    );
                });
            });
            $tx->ok('./input[@id="submit"]', '...... Test submit', sub {
                $tx->is('./@name', 'submit', '.........It should have a name');
                $tx->is('./@type', 'submit', '.........It should have a type');
                $tx->is('./@class', 'submit', '.........It should have a class');
                $tx->is(
                    './@value',
                    $mt->maketext('Release It!'),
                    '.........It should have a value');
            });
        });
    });
};
