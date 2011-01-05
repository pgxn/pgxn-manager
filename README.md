PGXN/Manager version 0.6.1
==========================

This application provides a Web interface and REST API for extension owners to
upload and manage extensions on PGXN, the PostgreSQL Extension Network. It
also provides an administrative interface for PGXN administrators. For more
information, visit the [PGXN site](http://pgxn.org/). For a working
deployment, hit [PGXN Manager](http://manager.pgxn.org/).


Installation
------------

* First, you need to satisfy the dependencies. These include:

  + [Perl](http://www.perl.org/) 5.12.0 or higher.
  + [PostgreSQL](http://www.postgresql.org/) 9.0.0 or higher with support for
    PL/Perl included.

* Next, you'll need to install all CPAN dependencies. To determine what they
  are, simply run

      perl Build.PL

* Configure the PostgreSQL server to preload modules used by PL/Perl
  functions. Just add these lines to the end of your `postgresql.conf` file:

      custom_variable_classes = 'plperl'
      plperl.use_strict = on
      plperl.on_init='use 5.12.0; use JSON::XS; use Email::Valid; use Data::Validate::URI; use SemVer;'

* Create a "pgxn" system user and the master mirror directory:

      useradd pgxn -d /nonexistent
      mkdir -p /var/www/master.pgxn.org
      chown -R pgxn:pgxn /var/www/master.pgxn.org

  The "pgxn" user should not have any system access. You should also configure
  your Web server to serve this directory. For proper networking, it should
  also be copy-able via anonymous `rsync` connections.

* Create the configuration file. The easiest way is to copy one of the templates:

      cp conf/local.json conf/prod.json

  Change the DSN if you'd like to use a different database name or connect to
  another host. (Consult the [DBI](http://search.cpan.org/perldoc?DBI) and
  [DBD::Pg](http://search.cpan.org/perldoc?DBD::Pg) documentation for details
  on the attributes that can be included in the DSN). You can also change the
  templates for the files that will be managed on the master mirror, though
  only changing the extension of the "dist" template from ".pgz" to whatever
  is appropriate for your network is really recommended.

* Build PGXN::Manager:

      perl Build.PL --db_super_user postgres \
                    --db_client /usr/local/pgsql/bin/psql \
                    --context prod
      ./Build
      ./Build db

* If you'd like to run the test suite, create a test database database and
  install [pgTAP](http://pgtap.org/) into it under the schema named "tap":

      PATH=$PATH:/usr/local/pgsql/bin
      createdb -U postgres pgxn_manager_test
      make TAPSCHEMA=tap
      make install
      psql -U postgres -d pgxn_manager_test -f pgrap.sql

  Then edit the DSN in `conf/test.json` so that it will connect to the test
  database. Then run the tests, which will need to be able to find `psql` in
  the system path:

      PATH=$PATH:/usr/local/pgsql/bin ./Build test --context test

  You can then drop the test database if you like:

      /usr/local/pgsql/bin/dropdb -U postgres pgxn_manager_test

* Fire up the app:

      sudo -u pgxn plackup -E prod bin/pgxn_manager.psgi

* Connect to port 5000 on your host and you should see the UI!

* Now you need to make yourself an administrator. Click the "Request Account"
  link and request an account.

* Now connect to the database:

      /usr/local/pgsql/bin/psql -U postgres pgxn_manager

  And approve your account, making youself an admin while you're at it. Also,
  set your password to an empty string. Assuming you gave yourself the
  nickname "fred", the query is:

      UPDATE users
         SET status   = 'active',
             is_admin = true,
             set_by   = 'fred',
             password = ''
       WHERE nickname = 'fred';

* Then give yourself a proper password by executing the `change_password()`
  function. Make sure the third argument is your great new password:

    SELECT change_password('fred', '', 'changme!');

* Hit the "Log In" link and log yourself in.

* Profit!

Running a Proxy Server
----------------------

PGXN::Manager is actually two apps in one. The public site runs under /pub/
and the site for users authenticated via Basic Auth runs under /auth/. A nice
way to separate these is to set up two reverse proxy servers: One to serve
/pub/ on port 80 and one to serve /auth/ on port 443. Here's how to do that.

* Get or create an SSL certificate and install it in your system.

* Create the reverse proxy hosts. Here's what the
  [mod_proxy](http://httpd.apache.org/docs/2.2/mod/mod_proxy.html)
  configuration for manager.pgxn.org looks like, both apps to a a
  PGXN::Manager instance running locally on port 7496:

      <VirtualHost *:80>
          ServerName manager.pgxn.org
          ProxyPass / http://localhost:7496/pub/
          ProxyPassReverse / http://localhost:7496/pub/
          RequestHeader set X-Forwarded-HTTPS %{HTTPS}s
          RequestHeader set X-Forwaded-Proto http
          RequestHeader set X-Forwarded-Port 80
          RequestHeader set X-Forwarded-Script-Name ""
      </VirtualHost>

      <VirtualHost *:443>
          ServerName manager.pgxn.org
          SSLEngine On
          SSLCertificateFile /path/to/certs/manager.pgxn.org.crt
          SSLCertificateKeyFile /path/to/private/manager.pgxn.org.key
          SSLCipherSuite ALL:!ADH:!EXPORT:!SSLv2:RC4+RSA:+HIGH:+MEDIUM
          ProxyPass / http://localhost:7496/auth/
          ProxyPassReverse / http://localhost:7496/auth/
          RequestHeader set X-Forwarded-HTTPS %{HTTPS}s
          RequestHeader set X-Forwaded-Proto https
          RequestHeader set X-Forwarded-Port 443
          RequestHeader set X-Forwarded-Script-Name ""
      </VirtualHost>

  Note that to do this, you need to have
  [mod_proxy](http://httpd.apache.org/docs/2.2/mod/mod_proxy.html),
  [mod_headers](http://httpd.apache.org/docs/2.2/mod/mod_headers.html), and
  [mod_ssl](http://httpd.apache.org/docs/2.2/mod/mod_ssl.html) built and
  installed in your Apache server (most distributions do).

* Install
  [Plack::Middleware::ReverseProxy](http://search.cpan.org/perloc?Plack::Middleware::ReverseProxy)
  from CPAN:

      cpan Plack::Middleware::ReverseProxy

* Edit the production configuration file. The there are only a few additional
  keys to edit:

    1. Add the ReverseProxy middleware. The "middleware" key should end up
       looking something like this:

        "middleware": [
            ["ErrorDocument", 500, "/error", "subrequest", 1],
            ["HTTPExceptions"],
            ["StackTrace", "no_print_errors", 1],
            ["ReverseProxy"]
        ],

    2. Tell PGXN::Manager to use the X-Forwarded-Script-Name header to create
       proper URLs (otherwise no images, CSS, or JavaScript will work):

        "uri_script_name_key": "HTTP_X_FORWARDED_SCRIPT_NAME",

    3. Tell the public site what link to use to the authenticated site:

        "auth_uri": "https://manager.pgxn.org/",

    4. Configure the Twitter OAuth token so that PGXN::Manager can tweet
       uploads. The simplest way to do so is to run `bin/get_twitter_token -h`
       for helpful intructions and easy configuration.

  You'll also find these settings in `conf/proxied.json` to help get you
  started.

* Restart your Apache server and then your PGXN Manager server. You should now
  be able to hit the public site at the root of your domain on port 80, and at
  the authenticated site at the root of your domain on port 443.

Copyright and License
---------------------

Copyright (c) 2010 David E. Wheeler.

This module is free software; you can redistribute it and/or modify it under
the [PostgreSQL License](http://www.opensource.org/licenses/postgresql).

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
