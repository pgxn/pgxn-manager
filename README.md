PGXN/Manager
============

[![Test Status](https://github.com/pgxn/pgxn-manager/workflows/CI/badge.svg)](https://github.com/pgxn/pgxn-manager/actions)

This application provides a Web interface and REST API for extension owners to
upload and manage extensions on PGXN, the PostgreSQL Extension Network. It
also provides an administrative interface for PGXN administrators. For more
information, visit the [PGXN site](https://pgxn.org/). For a working
deployment, hit [PGXN Manager](https://manager.pgxn.org/).

Installation
------------

*   First, you need to satisfy the dependencies. These include:

  +   [Perl](https://www.perl.org/) 5.10.0 or higher (5.12 or higher strongly
      recommended)
  +   [PostgreSQL](https://www.postgresql.org/) 12.0 or higher with support for
      PL/Perl included.

*   Next, you'll need to install all CPAN dependencies. To determine what they
    are, run

        perl Build.PL

    To install them, run

        ./Build installdeps

*   Configure the PostgreSQL server to pre-load modules used by PL/Perl
    functions. Just add these lines to the end of your `postgresql.conf` file:

        plperl.use_strict = on
        plperl.on_init='use 5.12.0; use JSON::XS; use Email::Valid; use Data::Validate::URI; use SemVer; use PGXN::Meta::Validator;'

    If you would also like those modules to load in the parent PostgreSQL process,
    rather than for each connection, add:

        shared_preload_libraries = '$libdir/plperl'

*   Install these PostgreSQL core
    [extensions](https://www.postgresql.org/docs/current/static/contrib.html):

    +   [citext](https://www.postgresql.org/docs/current/static/citext.html)
    +   [hstore](https://www.postgresql.org/docs/current/static/hstore.html)
    +   [pgcrypto](https://www.postgresql.org/docs/current/static/pgcrypto.html)

    If you installed from source, you can either install all the core
    extensions, like so:

        cd contrib/
        gmake
        gmake install

    Or if you like, you can install individual extensions like so:

        cd contrib
        for ext in citext hstore pgcrypto
        do
            cd citext
            gmake
            gmake install
            cd ..
        done

*   Install the PostgreSQL `semver` extension v0.31.1 or higher. It's available
    from PGXN itself. Grab [the latest release](https://pgxn.org/dist/semver/)
    and follow its installation instructions.

*   Create a "pgxn" system user and the master mirror directory:

        useradd pgxn -d /nonexistent
        mkdir -p /var/www/master.pgxn.org
        chown -R pgxn:pgxn /var/www/master.pgxn.org

    The "pgxn" user should not have any system access. You should also configure
    your web server to serve this directory. For proper networking, it should
    also be copy-able via anonymous `rsync` connections.

*   Create the configuration file. The easiest way is to copy one of the
    templates:

        cp conf/local.json conf/prod.json

    Change the DSN if you'd like to use a different database name or connect to
    another host. (Consult the [DBI](https://metacpan.org/pod/DBI) and
    [DBD::Pg](https://metacpan.org/pod/DBD::Pg) documentation for details on the
    attributes that can be included in the DSN). You can also change the
    templates for the files that will be managed on the master mirror.

*   Build PGXN::Manager:

        perl Build.PL --db_super_user postgres \
                      --db_client /path/to/pgsql/bin/psql \
                      --context local
        ./Build
        ./Build db

*   If you'd like to run the test suite, you'll need to install pgTAP from
    [pgTAP](https://pgxn.org/dist/pgtap/). Download it and install it like so:

        gmake
        gmake install

    Then repeat the steps above but use the "test" context, specified by the
    call to `Build.PL` like so:

        perl Build.PL --db_super_user postgres \
                      --db_client /path/to/pgsql/bin/psql \
                      --context test

    Next, edit the DSN in `conf/test.json` so that it will connect to the test
    database. Then run the tests, which will need to be able to find `psql` in
    the system path:

        ./Build test

    You can then drop the test database if you like:

        dropdb -U postgres pgxn_manager_test

*   Fire up the app:

        sudo -u pgxn plackup -E prod bin/pgxn_manager.psgi

*   Connect to http://localhost:5000/ and you should see the UI!

*   Now you need to make yourself an administrator. Click the "Request Account"
    link and request an account.

*   Now connect to the database:

        psql -U postgres pgxn_manager

    And approve your account, making yourself an admin while you're at it. Also,
    set your password using `crypt()`. Assuming you gave yourself the nickname
    "fred" and you want the password `change me!`, the query is:

        UPDATE users
           SET status   = 'active',
               is_admin = true,
               set_by   = 'fred',
               password = crypt('change me!', _salt())
         WHERE nickname = 'fred';

*   Hit the "Log In" link and log yourself in.

*   Profit!

Running a Proxy Server
----------------------

Here's how to run PGXN::Manager behind a reverse proxy server:

*   Get or create an SSL certificate and install it in your system.

*   Create the reverse proxy hosts. Here's what the
    [mod_proxy](https://httpd.apache.org/docs/current/mod/mod_proxy.html)
    configuration for manager.pgxn.org looks like, both apps to a a
    PGXN::Manager instance running locally on port 7496:

        <VirtualHost *:443>
          ServerName manager.pgxn.org
          SSLEngine On
          SSLCertificateFile /path/to/certs/manager.pgxn.org.crt
          SSLCertificateKeyFile /path/to/private/manager.pgxn.org.key
          SSLCipherSuite ALL:!ADH:!EXPORT:!SSLv2:RC4+RSA:+HIGH:+MEDIUM
          ProxyPass / http://localhost:7496/
          ProxyPassReverse / http://localhost:7496/
          RequestHeader set X-Forwarded-HTTPS %{HTTPS}s
          RequestHeader set X-Forwarded-Proto https
          RequestHeader set X-Forwarded-Port 443
          RequestHeader set X-Forwarded-Script-Name ""
        </VirtualHost>

    Note that to do this, you need to have
    [mod_proxy](https://httpd.apache.org/docs/current/mod/mod_proxy.html),
    [mod_headers](https://httpd.apache.org/docs/current/mod/mod_headers.html),
    and [mod_ssl](https://httpd.apache.org/docs/current/mod/mod_ssl.html) built
    and installed in your Apache server (most distributions do). The value of
    `X-Forwarded-Script-Name` should be the relative path to the app from the
    proxy server. Here `ProxyPass` is set to `/`, so the value should be the
    empty string. The other headers need to be set to ensure that URLs are
    properly rewritten by
    [Plack::Middleware::ReverseProxy](https://metacpan.org/pod/Plack::Middleware::ReverseProxy)
    and clients can't spoof the values to fool the server into thinking it's
    running under HTTPS when it's not.

    If you're updating a from an earlier version of PGXN::Manager that used to
    serve up the /pub app, Update the port 80 configuration to redirect to the
    TLS / app, like so:

        <VirtualHost *:80>
          ServerName manager.pgxn.org
          Redirect "/" "https://manager.pgxn.org/"
        </VirtualHost>

    Here's the equivalent configuration using
    [NGINX ngx_http_proxy_module](https://nginx.org/en/docs/http/ngx_http_proxy_module.html):

        server {
            server_name manager.pgxn.org
            listen 443;
            merge_slashes: off;
            ssl on;
            ssl_certificate /path/to/certs/manager.pgxn.org.crt;
            ssl_certificate_key /path/to/certs/manager.pgxn.org.key;

            location / {
                proxy_pass        http://127.0.0.1:7496/;
                proxy_redirect    off;
                proxy_set_header  X-Forwarded-Host        $host;
                proxy_set_header  X-Forwarded-For         $proxy_add_x_forwarded_for;
                proxy_set_header  X-Forwarded-HTTPS       ON;
                proxy_set_header  X-Forwarded-Proto       https;
                proxy_set_header  X-Forwarded-Port        443;
                proxy_set_header  X-Forwarded-Script-Name "";
            }
        }

        server {
            server_name manager.pgxn.org
            listen 80;
            return 301 https://manager.pgxn.org$request_uri;
        }

    Again, it's important to get the headers rewritten properly in order for the
    routing and writing of URLs to be correct and so that clients can't spoof
    them. Also, be sure to disable `merge_slashes` or else the mirror management
    interface will not work.

*   Install
    [Plack::Middleware::ReverseProxy](https://metacpan.org/pod/Plack::Middleware::ReverseProxy)
    from CPAN:

        cpan Plack::Middleware::ReverseProxy

*   Edit the production configuration file. The there are only a few additional
    keys to edit:

    1.  Add the ReverseProxy middleware. The "middleware" key should end up
        looking something like this:

            "middleware": [
               ["ErrorDocument", 500, "/error", "subrequest", 1],
               ["HTTPExceptions"],
               ["StackTrace", "no_print_errors", 1],
               ["ReverseProxy"]
            ],

    2.  If you elect to host PGXN::Manager under a subpath, such as /pgxn/, tell
        PGXN::Manager to use the `X-Forwarded-Script-Name` header to create
        proper URLs. otherwise no images, CSS, or JavaScript will work):

            "uri_script_name_key": "HTTP_X_FORWARDED_SCRIPT_NAME",

    3.  Configure the Twitter OAuth token so that PGXN::Manager can tweet
        uploads. The simplest way to do so is to run `bin/get_twitter_token -h`
        for helpful instructions and easy configuration.

    You'll also find these settings in `conf/proxied.json` to help get you
    started.

*   Restart your proxy server and then your PGXN Manager server. You should now
    be able to load the site at the root of your domain on port 443.

Monitoring Mirrors
------------------

Once you have mirrors syncing from the master mirror directory (via `rsync` or
however else), you might want to use the `check_mirrors` utility in a cron job.
It simply iterates over teh list of mirrors maintained by PGXN::Manager and
reports of any of them appear to be more than a specified number of days, hours,
or minutes behind. This will allow you to determine when a mirror may no longer
be available, so that you can contact the owner or remove the mirror from the
system.

Copyright and License
---------------------

Copyright (c) 2010-2024 David E. Wheeler.

This module is free software; you can redistribute it and/or modify it under
the [PostgreSQL License](https://www.opensource.org/licenses/postgresql).

Permission to use, copy, modify, and distribute this software and its
documentation for any purpose, without fee, and without a written agreement is
hereby granted, provided that the above copyright notice and this paragraph
and the following two paragraphs appear in all copies.

In no event shall David E. Wheeler be liable to any party for direct,
indirect, special, incidental, or consequential damages, including lost
profits, arising out of the use of this software and its documentation, even
if David E. Wheeler has been advised of the possibility of such damage.

David E. Wheeler specifically disclaims any warranties, including, but not
limited to, the implied warranties of merchantability and fitness for a
particular purpose. The software provided hereunder is on an "as is" basis,
and David E. Wheeler has no obligations to provide maintenance, support,
updates, enhancements, or modifications.
