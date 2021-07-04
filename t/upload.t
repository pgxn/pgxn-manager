#!/usr/bin/env perl -w

use 5.10.0;
use strict;
use warnings;
use utf8;

use Test::More tests => 198;
#use Test::More 'no_plan';
use Test::File;
use Test::MockModule;
use Plack::Test;
use HTTP::Request::Common;
use PGXN::Manager::Router;
use HTTP::Message::PSGI;
use Test::XML;
use Test::XPath;
use HTML::Entities;
use MIME::Base64;
use Encode;
use Archive::Zip qw(:ERROR_CODES);
use File::Path qw(remove_tree);
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
    desc       => $desc,
    keywords   => $keywords,
    h1         => $h1,
    page_title => 'Release a distribution archive on the network',
};

# Connect without authenticating.
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET '/upload'), 'GET /upload';
    is $res->code, 401, 'Should get 401 response';
    like $res->content, qr/Authorization required/,
        'The body should indicate need for authentication';
};

test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET(
        '/upload',
        Authorization => 'Basic ' . encode_base64("$user:test-passW0rd"),
    )), 'Fetch /upload';
    ok $res->is_success, 'Should get a successful response';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{REMOTE_USER} = $user;
    XPathTest->test_basics($tx, $req, $mt, $hparams);

    # Check content.
    $tx->ok('/html/body/div[@id="content"]', 'Look at the content', sub {
        $tx->is('count(./*)', 4, '... Should have four subelements');
        $tx->is(
            './p[1]',
            $mt->maketext(q{So you've developed a PGXN extension and what to distribute it on PGXN. This is the place to upload it! Just find your distribution archive (.zip, .tgz, etc.) in the upload field below and you'll be good to go.}),
            'Paragraph should be there'
        );
        my $t = quotemeta q{Don't know what this means? Want to know how to create great PostgreSQL extensions and distribute them to your fellow PostgreSQL enthusiasts via PGXN? Take a gander at our};
        $tx->like( './p[2]', qr/$t/, 'Should have second paragraph');
        $tx->ok('./form[@id="upform"]', 'Test upload form', sub {
            $tx->is(
                './@action',
                $req->uri_for('/upload'),
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
                    $tx->is('./@class', 'uploader', '............ It should have a class' );
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

# Okay, now try an upload.
my $tmpdir     = File::Spec->catdir(File::Spec->tmpdir, 'pgxn');
my $root       = PGXN::Manager->new->config->{mirror_root};
my $distdir    = File::Spec->catdir(qw(t dist widget));
my $distzip    = File::Spec->catdir(qw(t dist widget-0.2.5.zip));

# First, create a distribution.
my $dzip = Archive::Zip->new;
$dzip->addTree($distdir, 'widget-0.2.5') == AZ_OK or die 'tree error';
$dzip->writeToFileNamed($distzip) == AZ_OK or die 'write error';

END {
    unlink $distzip;
    remove_tree $tmpdir, $root;
}

# Make sure we don't try to send any tweets.
my $mock_pgxn = Test::MockModule->new('PGXN::Manager');
my %tweet_params = (
    body => 'widget 0.2.5 released by user: https://pgxn.org/dist/widget/',
    whom => 'user',
);
$mock_pgxn->mock(send_tweet => sub {
    shift;
    is_deeply shift, \%tweet_params, 'A tweet should have been sent';
});

# Make sure the expected files don't exist yet.
my %files = map { join('/', @{ $_ }) => File::Spec->catfile($root, @{ $_ } ) } (
   ['user',      'user.json'],
   ['dist',      'widget.json'],
   ['tag',       'gadget.json'],
   ['tag',       'widget.json'],
   ['extension', 'widget.json'],
   ['dist',      'widget', '0.2.5', 'META.json'],
   ['dist',      'widget', '0.2.5', 'widget-0.2.5.zip'],
   ['tag',       'full text search.json'],
);
file_not_exists_ok $files{$_}, "File $_ should not yet exist" for keys %files;

# Now upload it!
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(POST(
        '/upload',
        Authorization => 'Basic ' . encode_base64("$user:test-passW0rd"),
        Content_Type => 'form-data',
        Content => [ archive => [$distzip] ],
    )), 'POST zip archive to /upload';
    ok $res->is_redirect, 'Response should be a redirect';
    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    is $res->headers->header('location'),
        $req->uri_for('/distributions/widget/0.2.5'),
        'Should redirect to /distributions/widget/0.2.5';
};

# Let's have a look-see.
file_exists_ok $files{$_}, "File $_ should now exist" for keys %files;

##############################################################################
# Okay, let's try again, this time with an Ajax post.
TxnTest->restart;
$user = TxnTest->user;
remove_tree $root;
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(POST(
        '/upload',
        Authorization => 'Basic ' . encode_base64("$user:test-passW0rd"),
        'X-Requested-With' => 'XMLHttpRequest',
        Content_Type => 'form-data',
        Content => [ archive => [$distzip] ],
    )), 'POST zip archive to /upload';
    ok $res->is_success, 'Response should success';
    is $res->content, $mt->maketext('Success'),
        'And the content should say so';
};

file_exists_ok $files{$_}, "File $_ should again exist" for keys %files;

# Now let's see how we handle an error from the database.
# Need to mock user_is_admin to avoid transaction failure error.
my $rmock = Test::MockModule->new('PGXN::Manager::Request');
$rmock->mock(user_is_admin => 0);
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(POST(
        '/upload',
        Authorization => 'Basic ' . encode_base64("$user:test-passW0rd"),
        Content_Type => 'form-data',
        'X-Requested-With' => 'XMLHttpRequest',
        Accept => 'text/html',
        Content => [ archive => [$distzip] ],
    )), 'POST dupe zip archive to /upload';
    is $res->code, 409, 'Should get 409 response';
    is $res->content, '<p class="error">' . encode_utf8(encode_entities($mt->maketext(
        'Distribution “[_1]” already exists', 'widget 0.2.5'
    ))) . '</p>', 'And content should reflect that';
};

##############################################################################
# Start again, and make sure that the error appears in the redirect for a
# non-ajax request.
TxnTest->restart;
$user = TxnTest->user;
remove_tree $root;
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(POST(
        '/upload',
        Authorization => 'Basic ' . encode_base64("$user:test-passW0rd"),
        'X-Requested-With' => 'XMLHttpRequest',
        Content_Type => 'form-data',
        Content => [ archive => [$distzip] ],
    )), 'POST zip archive to /upload again';
    ok $res->is_success, 'Response should success';
    is $res->content, $mt->maketext('Success'),
        'And the content should say so';
};

file_exists_ok $files{$_}, "File $_ should again exist" for keys %files;

# Submit dupe, this time owned by someone else.
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(POST(
        '/upload',
        Authorization => 'Basic ' . encode_base64(TxnTest->admin . ":test-passW0rd"),
        Content_Type => 'form-data',
        Content => [ archive => [$distzip] ],
    )), 'POST dupe zip with non-owner to /upload';
    is $res->code, 409, 'Should get 409 response';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
    $req->env->{REMOTE_USER} = TxnTest->admin;
    XPathTest->test_basics($tx, $req, $mt, $hparams);

    # Now verify that we have the error message and that the form fields are
    # filled-in.
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        my $err = $mt->maketext('User “[_1]” does not own all provided extensions', 'admin');
        $tx->is('./p[@class="error"]', $err, '... Error paragraph should be set');
    });
};

##############################################################################
# Now try a submit with no file.
TxnTest->restart;
$user = TxnTest->user;
remove_tree $root;
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(POST(
        '/upload',
        Authorization => 'Basic ' . encode_base64("$user:test-passW0rd"),
        Content_Type => 'form-data',
        Content => [ archive => [] ],
    )), 'POST no archive to /upload again';
    ok !$res->is_success, 'Response should not be success';
    is $res->code, 400, 'Should get 400 response';
    is_well_formed_xml $res->content, 'The HTML should be well-formed';
    my $tx = Test::XPath->new( xml => $res->content, is_html => 1 );

    # Now verify that we have the error message.
    $tx->ok('/html/body/div[@id="content"]', 'Test the content', sub {
        my $err = $mt->maketext('Oops! I think you forgot to select a file to upload.');
        $tx->is('./p[@class="error"]', $err, '... Error paragraph should be set');
    });
};

# Now try an Ajax request.
test_psgi $app => sub {
    my $cb = shift;
    ok my $res = $cb->(POST(
        '/upload',
        Authorization => 'Basic ' . encode_base64("$user:test-passW0rd"),
        'X-Requested-With' => 'XMLHttpRequest',
        Content_Type => 'form-data',
        Content => [ archive => [] ],
    )), 'POST no zip archive to /upload via Ajax';
    ok !$res->is_success, 'Response should not be success';
    is $res->code, 400, 'Should get 400 response';
    is $res->content, 'Bad request: no archive parameter.'
};
