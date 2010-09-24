package XPathTest;

use 5.12.0;
use utf8;

# Call this function for every request to make sure that they all
# have the same basic structure.
sub test_basics {
    my ($self, $tx, $req, $mt, $p) = @_;

    # Some basic sanity-checking.
    $tx->is( 'count(/html)',      1, 'Should have 1 html element' );
    $tx->is( 'count(/html/head)', 1, 'Should have 1 head element' );
    $tx->is( 'count(/html/body)', 1, 'Should have 1 body element' );

    # Check the head element.
    $tx->ok('/html/head', 'Test head', sub {
        my $c = $p->{validate_form} ? 8
              : $p->{with_jquery}   ? 6
                                    : 5;
        $c++ if $p->{desc};
        $c++ if $p->{keywords};
        $_->is('count(./*)', $c, 'Should have 7 elements below "head"');

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

        $_->is(
            './link[@rel="shortcut icon"]/@href',
            $req->base . 'ui/img/favicon.png',
            'Should specify the favicon',
        );

        if ($p->{with_jquery} || $p->{validate_form}) {
            $_->is(
                './script[1][@type="text/javascript"]/@src',
                $req->uri_for('/ui/js/jquery-1.4.2.min.js'),
                'Should load jQuery'
            );
            if (my $id = $p->{validate_form}) {
                $_->is(
                    './script[2][@type="text/javascript"]/@src',
                    $req->uri_for('/ui/js/jquery.validate.min.js'),
                    'Should load load jQuery Validate plugin'
                );
                my $js = quotemeta "\$(document).ready(function(){ \$('#$id').validate";
                $_->like(
                    './script[3][@type="text/javascript"]',
                    qr/$js/,
                    'Should have the validation function'
                );
            }
        }

    });

    # Test the body.
    $tx->is('count(/html/body/*)', 2, 'Should have two elements below body');

    # Check the content section.
    $tx->ok('/html/body/div[@id="content"]', 'Test content', sub {
        $_->is('./h1', $p->{h1}, "Should have h1");
    });

    # Test the sidebar section.
    $tx->ok( '/html/body/div[@id="sidebar"]', 'Test sidebar', sub {
        my $c = $req->user_is_admin ? 7 : 5;
        $_->is('count(./*)', $c, 'Should have four sidebar subelements');

        $_->ok('./a[@id="logo"]', 'Should have logo link', sub {
            $_->is(
                './@href',
                $req->base . ($req->user ? 'auth' : ''),
               'It should link to the right place'
            );
            $_->is('./img/@src', $req->base . 'ui/img/logo.png', 'Should have logo');
        });
        $_->is('./h1', $mt->maketext('PGXN Manager'), 'Should have name');
        $_->is('./h2', $mt->maketext('tagline'), 'Should have tagline');

        if ($req->user) {
            # Test user menu.
            $_->ok('./ul[@id="usermenu"]', 'Test user menu', sub {
                $_->is('count(./*)', 5, 'Should have 5 menu subelements');
                $_->is('count(./li)', 5, 'And they should all be list items');

                my $i = 0;
                for my $spec (
                    [ '/auth/upload',      'Upload a Distribution', 'upload'      ],
                    [ '/auth/show',        'Show my Files',         'show',       ],
                    [ '/auth/permissions', 'Show Permissions',      'permissions' ],
                    [ '/auth/user',        'Edit Account',          'account'     ],
                    [ '/auth/pass',        'Change Password',       'passwd'      ],
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
                        qq{./li[$i]/a[\@id="$spec->[2]"][\@href="$uri"]},
                        $mt->maketext($spec->[1]),
                        "Link $i, id $spec->[2], href $uri, should have proper text"
                    );
                }
            });
            if ($req->user_is_admin) {
                # We have another menu.
                $_->is('./h3', $mt->maketext('Admin Menu'), 'Should have admin menu header');
                $_->ok('./ul[@id="adminmenu"]', 'Test admin menu', sub {
                    $_->is('count(./*)', 1, 'Should have 1 menu subelement');
                    $_->is('count(./li)', 1, 'And it should be a list item');

                    my $i = 0;
                    for my $spec (
                        [ '/auth/admin/moderate', 'Moderate Requests', 'moderate' ],
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
                            qq{./li[$i]/a[\@id="$spec->[2]"][\@href="$uri"]},
                            $mt->maketext($spec->[1]),
                            "Link $i, id $spec->[2], href $uri, should have proper text"
                        );
                    }
                });
            }
        } else {
            $_->ok('./ul[@id="publicmenu"]', 'Test public menu', sub {
                $_->is('count(./*)', 3, 'Should have 7 menu subelements');
                $_->is('count(./li)', 3, 'And they should all be list items');

                my $i = 0;
                for my $spec (
                    [ '/auth',     'Log In',          'login'   ],
                    [ '/register', 'Request Account', 'request' ],
                    [ '/reset',    'Reset Password',  'reset'   ],
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
                        qq{./li[$i]/a[\@id="$spec->[2]"][\@href="$uri"]},
                        $mt->maketext($spec->[1]),
                        "Link $i, id $spec->[2], href $uri, should have proper text"
                    );
                }
            });
        }

        # Test the menu present for everyone.
        $_->ok('./ul[@id="allmenu"]', 'Test permanent menu', sub {
            $_->is('count(./*)', 2, 'Should have 2 menu subelements');
            $_->is('count(./li)', 2, 'And they should all be list items');

            my $i = 0;
            for my $spec (
                [ '/about',   'About' ],
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
                    $mt->maketext($spec->[1]),
                    "Link $i should be to $uri and have proper text"
                );
            }
        });
    });
}

1;
