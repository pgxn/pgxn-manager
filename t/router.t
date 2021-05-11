#!/usr/bin/env perl -w

use 5.10.0;
use utf8;
use Test::More tests => 117;
#use Test::More 'no_plan';
use Plack::Test;
use HTTP::Request::Common;
use Test::File::Contents;
use PGXN::Manager;
use HTTP::Message::PSGI;
use lib 't/lib';
use TxnTest;
use MIME::Base64;
use Encode;

BEGIN {
    use_ok 'PGXN::Manager::Router' or die;
}

# Create a user who can authenticate.
my $admin = TxnTest->admin;

# Test home page with and without authentication
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET '/'), 'Fetch /';
    is $res->code, 200, 'Should get 200 response';
    like $res->content, qr/Welcome/, 'The body should look correct';

    my $req = GET '/', Authorization => 'Basic ' . encode_base64("$admin:****");
    ok $res = $cb->($req), 'Fetch / with auth token';
    is $res->code, 200, 'Should still get 200 response';
    like $res->content, qr/Welcome/, 'The body should again look correct';
};

# Test static file.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb = shift;
    my $uri = '/ui/css/screen.css';
    ok my $res = $cb->(GET $uri), "Fetch $uri";
    is $res->code, 200, 'Should get 200 response';
    file_contents_is 'www/ui/css/screen.css', $res->content,
        'The file should have been served';

    my $req = GET $uri, Authorization => 'Basic ' . encode_base64("$admin:****");
    ok $res = $cb->($req), "Fetch $uri with auth token";
    is $res->code, 200, 'Should still get 200 response';
    file_contents_is 'www/ui/css/screen.css', $res->content,
        'The file should have been served again';
};

# Test bogus URL.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb = shift;
    my $uri = '/nonexistentpage';
    ok my $res = $cb->(GET $uri), "Fetch $uri";
    is $res->code, 401, 'Should get 401 response';
    like $res->content, qr/Authorization required/,
        'The body should indicate need for authentication';

    my $req = GET $uri, Authorization => 'Basic ' . encode_base64("$admin:****");
    ok $res = $cb->($req), "Fetch $uri with auth token";
    is $res->code, 404, 'Should now get 404 response';
    like decode_utf8($res->content), qr/Where’d It Go\?/,
        'The body should have the error';
};

# /account should require authentication.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET '/account'), 'Fetch /account';
    is $res->code, 401, 'Should get 401 response';
    like $res->content, qr/Authorization required/,
        'The body should indicate need for authentication';
};

# Test invalid password.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb = shift;
    my $req = GET '/account', Authorization => 'Basic ' . encode_base64("$admin:haha");
    ok my $res = $cb->($req), 'Fetch /account with inhvalid auth token';
    is $res->code, 401, 'Should get 401 response';
    like $res->content, qr/Authorization required/,
        'The body should indicate need for authentication';
};

# Test inactive user.
my $user = TxnTest->user;
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb = shift;
    my $req = GET '/', Authorization => 'Basic ' . encode_base64("$user:****");
    ok my $res = $cb->($req), 'Fetch / with user auth token';
    is $res->code, 200, 'Should get 200 response';
    like $res->content, qr/Welcome/,
        'The body should indicate we authenticated';
};

# Test /login.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET '/login'), 'Fetch /login';
    is $res->code, 401, 'Should get 401 response';
    like $res->content, qr/Authorization required/,
        'The body should indicate need for authentication';

    my $req = GET '/login', Authorization => 'Basic ' . encode_base64("$user:****");
    ok $res = $cb->($req), 'Fetch /login with user auth token';
    is $res->code, 307, 'Should get 307 response';
    is $res->content, '', 'Should have no content';
};


# Deactivate the user.
PGXN::Manager->conn->run(sub {
    $_->do(
        'SELECT set_user_status(?, ?, ?)',
        undef, $admin, $user, 'inactive',
    );
});

test_psgi +PGXN::Manager::Router->app => sub {
    my $cb = shift;
    my $req = GET '/account', Authorization => 'Basic ' . encode_base64("$user:****");
    ok my $res = $cb->($req), 'Fetch /account with invalid user auth token';
    is $res->code, 401, 'Should get 401 response';
    like $res->content, qr/Authorization required/,
        'The body should indicate need for authentication';
};

# Test that old pub and auth routes have been moved to /.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb = shift;
    for my $uri ('', qw(
        error
        about
        contact
        howto
        ui
        account/register
        account/forgotten
        account/thanks
        nonesuch
    )) {
        for my $app (qw(pub auth)) {
            $app_uri = "/$app/$uri";
            ok my $res = $cb->(GET $app_uri), "Fetch $app_uri";
            is $res->code, 301, "Should get 301 response from $app_uri";
            my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
            is $res->headers->header('location'), "/$uri",
                "Should redirect from $app_uri to /$uri";
            is $res->content, '', "Should have no content from $app_uri";
        }
    }
};
