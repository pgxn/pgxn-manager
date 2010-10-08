PGXN/Manager version 0.1.1
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

* Edit the `conf/prod.json` configuration file. Change the DSN if you'd like
  to use a different database name or connect to another host. (Consult the
  [DBI](http://search.cpan.org/perldoc?DBI) and
  [DBD::Pg](http://search.cpan.org/perldoc?DBD::Pg) documentation for details
  on the attributes that can be included in the DSN). You can also change the
  templates for the files that will be managed on the master mirror, though
  only changing the extension of the "dist" template from ".pgz" to whatever
  is appropriate for your network is really recommended.

* Build PGXN:

      perl Build.PL --db_super_user postgres \
                    --db_client /usr/local/pgsql/bin/psql \
                    --context prod
      ./Build
      ./Build db

* If you'd like to run the test suite, edit `conf/test.json` so that it will
  connect to a separate database then run the tests. Create that database and
  install [pgTAP](http://pgtap.org/) into it under the schema named "tap":

      PATH=$PATH:/usr/local/pgsql/bin
      createdb -U postgres pgxn_manager_test
      make TAPSCHEMA=tap
      make install
      psql -U postgres -d pgxn_manager_test -f pgrap.sql

  Then run the tests:

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

Installation
------------

To install this module, type the following:

    perl Build.PL
    ./Build
    ./Build test
    ./Build install

Copyright and Licence
---------------------

Copyright (c) 2010 PostgreSQL Experts and David E. Wheeler.

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
