#!/usr/bin/env perl -w

use 5.10.0;
use utf8;
use Test::More tests => 80;
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

# Test home page.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET '/'), 'Fetch /';
    is $res->code, 403, 'Should get 403 response';
    like $res->content, qr/Permission Denied/,
        'The body should indicate that permission is denied';
};

# Create a user who can authenticate.
my $admin = TxnTest->admin;

# Test home page with and without authentication
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET '/auth/'), 'Fetch /auth/';
    is $res->code, 200, 'Should get 200 response';
    like $res->content, qr/Welcome/, 'The body should look correct';

    my $req = GET '/auth/', Authorization => 'Basic ' . encode_base64("$admin:****");
    ok $res = $cb->($req), 'Fetch /auth/ with auth token';
    is $res->code, 200, 'Should still get 200 response';
    like $res->content, qr/Welcome/, 'The body should again look correct';
};

# Test static file.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb = shift;
    my $uri = '/auth/ui/css/screen.css';
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
    my $uri = '/auth/nonexistentpage';
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

# /auth should require authentication.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET '/auth'), 'Fetch /auth';
    is $res->code, 401, 'Should get 401 response';
    like $res->content, qr/Authorization required/,
        'The body should indicate need for authentication';
};

# Test invalid password.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb = shift;
    my $req = GET '/auth', Authorization => 'Basic ' . encode_base64("$admin:haha");
    ok my $res = $cb->($req), 'Fetch /auth with inhvalid auth token';
    is $res->code, 401, 'Should get 401 response';
    like $res->content, qr/Authorization required/,
        'The body should indicate need for authentication';
};

# Test inactive user.
my $user = TxnTest->user;
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb = shift;
    my $req = GET '/auth/', Authorization => 'Basic ' . encode_base64("$user:****");
    ok my $res = $cb->($req), 'Fetch /auth with user auth token';
    is $res->code, 200, 'Should get 200 response';
    like $res->content, qr/Welcome/,
        'The body should indicate we authenticated';
};

# Test /login.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET '/auth/login'), 'Fetch /auth/login';
    is $res->code, 401, 'Should get 401 response';
    like $res->content, qr/Authorization required/,
        'The body should indicate need for authentication';

    my $req = GET '/auth/login', Authorization => 'Basic ' . encode_base64("$user:****");
    ok $res = $cb->($req), 'Fetch /auth/login with user auth token';
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
    my $req = GET '/auth', Authorization => 'Basic ' . encode_base64("$user:****");
    ok my $res = $cb->($req), 'Fetch /auth with invalid user auth token';
    is $res->code, 401, 'Should get 401 response';
    like $res->content, qr/Authorization required/,
        'The body should indicate need for authentication';
};

# Test that old pub routes have been moved to auth.
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
        ok my $res = $cb->(GET "/pub/$uri"), "Fetch /pub/$uri";
        is $res->code, 301, 'Should get 301 response';
        my $req = PGXN::Manager::Request->new(req_to_psgi($res->request));
        is $res->headers->header('location'), $req->auth_uri_for("/$uri"),
            "Should redirect to /auth/$uri";
        is $res->content, '', 'Should have no content';
    }
};
