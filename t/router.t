#!/usr/bin/env perl -w

use 5.10.0;
use utf8;
use Test::More tests => 28;
#use Test::More 'no_plan';
use Plack::Test;
use HTTP::Request::Common;
use Test::File::Contents;
use PGXN::Manager;
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

# Test home page.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET '/pub/'), 'Fetch /pub/';
    is $res->code, 200, 'Should get 200 response';
    like $res->content, qr/Welcome/, 'The body should look correct';
};

# Test static file.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET '/pub/ui/css/screen.css'), 'Fetch /pub/ui/css/screen.css';
    is $res->code, 200, 'Should get 200 response';
    file_contents_is 'www/ui/css/screen.css', $res->content,
        'The file should have been served';
};

# Test bogus URL.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET '/pub/nonexistentpage'), 'Fetch /pub/nonexistentpage';
    is $res->code, 404, 'Should get 404 response';
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

# Create a user who can authenticate.
my $admin = TxnTest->admin;

# Test authentication.
test_psgi +PGXN::Manager::Router->app => sub {
    my $cb = shift;
    my $req = GET '/auth/', Authorization => 'Basic ' . encode_base64("$admin:****");
    ok my $res = $cb->($req), 'Fetch /auth with auth token';
    is $res->code, 200, 'Should get 200 response';
    like $res->content, qr/Welcome/,
        'The body should indicate we authenticated';
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
