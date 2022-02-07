package XPathTest;

use 5.10.0;
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
        my $c = $p->{validate_form} ? 12
              : $p->{with_jquery}   ? 10
                                    : 8;
        $c++ if $p->{desc};
        $c++ if $p->{keywords};
        $c++ if $p->{js};

        $_->is('count(./*)', $c, qq{Should have $c elements below "head"});

        $_->is(
            './meta[@http-equiv="Content-Type"]/@content',
            'text/html; charset=UTF-8',
            'Should have the content-type set in a meta header',
        );

        my $title = PGXN::Manager->config->{name} || 'PGXN Manager';
        if (my $page = $p->{page_title}) {
            $title .= ' — ' . $mt->maketext($page);
        }
        $_->is('./title', $title, 'Title should be correct');

        $_->is(
            './meta[@name="generator"]/@content',
            'PGXN::Manager ' . PGXN::Manager->version_string,
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
            $req->uri_for('/ui/css/screen.css'),
            'Should load the CSS',
        );

        my $ie_uri = $req->uri_for('/ui/css/fix.css');
        $_->is(
            './comment()',
            "[if IE 6]>\n"
            . qq{  <link rel="stylesheet" type="text/css" href="$ie_uri" />\n}
            . '  <![endif]',
            'Should have IE6 fix comment');

        $_->is(
            './link[@rel="icon"][@type="image/svg+xml"]/@href',
            $req->uri_for('/ui/img/icon.svg'),
            'Should specify the SVG icon',
        );
        $_->is(
            './link[@rel="icon"][2]/@href',
            $req->uri_for('/ui/img/icon.ico'),
            'Should specify the ICO icon',
        );
        $_->is(
            './link[@rel="apple-touch-icon"][@sizes="180x180"]/@href',
            $req->uri_for('/ui/img/icon-180.png'),
            'Should specify the Apple touch icon',
        );
        $_->is(
            './link[@rel="manifest"]/@href',
            $req->uri_for('/ui/manifest.json'),
            'Should specify the manifest for Android',
        );

        if ($p->{with_jquery} || $p->{validate_form}) {
            $_->is(
                './script[1][@type="text/javascript"]/@src',
                $req->uri_for('/ui/js/jquery-3.6.0.min.js'),
                'Should load jQuery'
            );
            $_->is(
                './script[2][@type="text/javascript"]/@src',
                $req->uri_for('/ui/js/lib.js'),
                'Should load JavaScript library'
            );
            if (my $id = $p->{validate_form}) {
                $_->is(
                    './script[3][@type="text/javascript"]/@src',
                    $req->uri_for('/ui/js/jquery.validate.min.js'),
                    'Should load load jQuery Validate plugin'
                );
            }
        }

    });

    # Test the body.
    $tx->is('count(/html/body/*)', 3, 'Should have three elements below body');

    # Check the content section.
    $tx->ok('/html/body/div[@id="content"]', 'Test content', sub {
        $_->is('./h1', $p->{h1}, "Should have h1");
    });

    # Test the sidebar section.
    $tx->ok( '/html/body/div[@id="sidebar"]', 'Test sidebar', sub {
        my $c = $req->user_is_admin ? 8 : 6;
        $_->is('count(./*)', $c, 'Should have four sidebar subelements');

        $_->ok('./a[@id="logo"]', 'Should have logo link', sub {
            $_->is(
                './@href',
                $req->uri_for('/'),
               'It should link to the right place'
            );
            $_->is('./img/@src', $req->uri_for('/ui/img/icon.svg'), 'Should have logo');
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
                    [ '/upload',           'Upload a Distribution', 'upload'      ],
                    [ '/distributions',    'Your Distributions',    'dists'       ],
                    [ '/permissions',      'Show Permissions',      'permissions' ],
                    [ '/account',          'Edit Account',          'account'     ],
                    [ '/account/password', 'Change Password',       'passwd'      ],
                ) {
                    $i++;
                    $_->is(
                        "count(./li[$i]/*)", 1,
                        "Should be one subelement of menu item $i"
                    );
                    my $uri = $req->uri_for($spec->[0]);
                    $_->is(
                        "./li[$i]/a/\@class", 'active',
                        "Link $i should be active"
                    ) if $req->path eq $uri->path;
                    $_->is(
                        qq{./li[$i]/a[\@id="$spec->[2]"][\@href="$uri"]},
                        $mt->maketext($spec->[1]),
                        "Link $i, id $spec->[2], href $uri, should have proper text"
                    );
                }
            });
            if ($req->user_is_admin) {
                # We have another menu.
                $_->ok('./hr', 'Should have an hr' );
                $_->ok('./ul[@id="adminmenu"]', 'Test admin menu', sub {
                    $_->is('count(./*)', 3, 'Should have 3 menu subelements');
                    $_->is('count(./li)', 3, 'And they should be list items');

                    my $i = 0;
                    for my $spec (
                        [ '/admin/moderate', 'Moderate Requests',     'moderate' ],
                        [ '/admin/users',    'User Administration',   'users'    ],
                        [ '/admin/mirrors',  'Mirror Administration', 'mirrors'  ],
                    ) {
                        $i++;
                        $_->is(
                            "count(./li[$i]/*)", 1,
                            "Should be one subelement of menu item $i"
                        );
                        my $uri = $req->uri_for($spec->[0]);
                        $_->is(
                            "./li[$i]/a/\@class", 'active',
                            "Link $i should be active"
                        ) if $req->path eq $uri->path;
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
                    [ '/login',             'Log In',          'login'   ],
                    [ '/account/register',  'Request Account', 'request' ],
                    [ '/account/forgotten', 'Reset Password',  'reset'   ],
                ) {
                    $i++;
                    $_->is(
                        "count(./li[$i]/*)", 1,
                        "Should be one subelement of menu item $i"
                    );
                    my $uri = $spec->[0] =~ m{^/account/} ?  $req->uri_for($spec->[0])
                            : $req->uri_for($spec->[0]);
                    $_->is(
                        "./li[$i]/a/\@class", 'active',
                        "Link $i should be active"
                    ) if $req->path eq $uri->path;
                    $_->is(
                        qq{./li[$i]/a[\@id="$spec->[2]"][\@href="$uri"]},
                        $mt->maketext($spec->[1]),
                        "Link $i, id $spec->[2], href $uri, should have proper text"
                    );
                }
            });
        }

        # Test the menu present for everyone.
        $_->ok('./hr', 'Should have an hr' );
        $_->ok('./ul[@id="allmenu"]', 'Test permanent menu', sub {
            $_->is('count(./*)', 3, 'Should have 3 menu subelements');
            $_->is('count(./li)', 3, 'And they should all be list items');

            my $i = 0;
            for my $spec (
                [ '/about',   'About'   ],
                [ '/howto',   'How To'  ],
                [ '/contact', 'Contact' ],
            ) {
                $i++;
                $_->is(
                    "count(./li[$i]/*)", 1,
                    "Should be one subelement of menu item $i"
                );
                my $uri = $req->uri_for($spec->[0]);
                $_->is(
                    "./li[$i]/a/\@class", 'active',
                    "Link $i should be active"
                ) if $req->path eq $uri->path;
                $_->is(
                    qq{./li[$i]/a[\@href="$uri"]},
                    $mt->maketext($spec->[1]),
                    "Link $i should be to $uri and have proper text"
                );
            }
        });
    });

    # Test the footer.
    $tx->ok('/html/body/div[@id="footer"]', 'Test footer', sub {
        $tx->is('count(./*)', 1, 'Should have 1 subelement');
        $tx->like('./p', qr/PostgreSQL License/, 'It should have the license');
    });
}

1;
