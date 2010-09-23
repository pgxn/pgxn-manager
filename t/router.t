#!/usr/bin/env perl

use 5.12.0;
use utf8;
use Test::More tests => 22;
#use Test::More 'no_plan';
use Plack::Test;
use HTTP::Request::Common;
use Test::File::Contents;
use PGXN::Manager;
use lib 't/lib';
use TxnTest;
use MIME::Base64;

BEGIN {
    use_ok 'PGXN::Manager::Router' or die;
}

test_psgi +PGXN::Manager::Router->app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET '/'), 'Fetch /';
    is $res->code, 200, 'Should get 200 response';
    like $res->content, qr/Welcome/, 'The body should look correct';
};

test_psgi +PGXN::Manager::Router->app => sub {
    my $cb = shift;
    ok my $res = $cb->(GET '/ui/css/screen.css'), 'Fetch /ui/css/screen.css';
    is $res->code, 200, 'Should get 200 response';
    file_contents_is 'www/ui/css/screen.css', $res->content,
        'The file should have been served';
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
    my $req = GET '/auth', Authorization => 'Basic ' . encode_base64("$admin:****");
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
    my $req = GET '/auth', Authorization => 'Basic ' . encode_base64("$user:****");
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
