PGXN is the PostgreSQL Extension Network. If you're a PostgreSQL developer, you've no doubt created customizations to make your life simpler. This is possible because PostgreSQL today is not merely a database, it’s an application development platform. If you'd like to distribute such customizations in open-source releases for your fellow PostgreSQL enthusiasts to enjoy, PGXN is the place to do it.

This document explains how. There's some background information, too, but the goal is to provide the information and references you need to get started packaging your extensions and distributing them on PGXN. If anything is unclear, please do [let us know](/contact). It's our aim to make this the one stop for all of your PGXN distribution needs.

### OMG Distribution WTF? ###

First of all, what is a "distribution" in the PGXN sense? Basically, it's a collection of one or more [PostgreSQL](http://www.postgresql.org/) extensions. That's it.

Oh, so now you want to know what an "extension" is? Naturally. Well, as of this writing it's somewhat in flux. Traditionally, a PostgreSQL extension has been any code that can be built by [PGXS](http://www.postgresql.org/docs/current/static/xfunc-c.html#XFUNC-C-PGXS) and installed into the database. The PostgreSQL [contributed modules](http://www.postgresql.org/docs/current/static/contrib.html) provide excellent examples.

There is ongoing work to integrate the idea of extensions more deeply into the PostgreSQL core in 9.1. Dimitri Fontaine has [the details](http://blog.tapoueh.org/blog.dim.html#%20Introducing%20Extensions). However, the build infrastructure is the same. From your point of view as a PostgreSQL extension developer, you're still going to use [PGXS](http://www.postgresql.org/docs/current/static/xfunc-c.html#XFUNC-C-PGXS) to configure and build your extension, and can distribute it via PGXN.

### That's So Meta ###

At its simplest, the only thing PGXN requires of a distribution is a single file, `META.json`, which describes the package. This is (currently) the only file that PGXN Manager uses to index a distribution, so it's important to get it right. The [PGXN Meta Spec](http://pgxn.org/spec/) has a rather complete example of a hypothetical pgTAP `META.json`. 

If you have only one .sql file for your extension and it's the same name as the distribution (which is commonly the case), then you can make it pretty simple. For example, the [`pair`](http://master.pgxn.org/dist/pair/) distribution has only one SQL file. So the `META.json` could be:

    {
       "name": "pair",
       "abstract": "A key/value pair data type",
       "version": "0.1.0",
       "maintainer": "David E. Wheeler <david@justatheory.com>",
       "license": "postgresql",
       "meta-spec": {
          "version": "1.0.0",
          "url": "http://pgxn.org/meta/spec.txt"
       },
    }
    
That's it. The only thing that may not be obvious from this example is that all version numbers in a `META.json` *must* be [semantic versions](http://semver.org/), including for core dependencies like plperl or PostgreSQL itself. If they're not, PGXN will make them so. So "1.2" would become "1.2.0" -- and so would "1.02". So do try to use semantic version strings and don't worry about it.

In the short run, you won't need anything more in your `META.json` file. But once the proposed [search site](http://wiki.postgresql.org/wiki/PGXN#Search_Site) and [command-line client](http://wiki.postgresql.org/wiki/PGXN#PGXN_Client) have been implemented, you're probably going to want to do more. Other useful keys to include are:

* [`tags`](http://pgxn.org/spec/#tags): An array of tags to associate with a distribution. Will help with searching.
* [`prereqs`](http://pgxn.org/spec/#prereqs): A list of prerequisite extensions or PostgreSQL contrib modules (or PostgreSQL itself).
* [`provides`](http://pgxn.org/spec/#provides): A list of included extensions. Useful if you have more than one in a single distribution. It also will assign ownership of the specified extension names to you -- if they haven't been claimed by any previous distribution.
* [`release_status`](http://pgxn.org/spec/#release_status): To label a distribution as "stable," "unstable," or "testing." The latter two are useful for distributing extensions for testing but that should not be installed by automated clients.
* [`resources`](http://pgxn.org/spec/#resources): A list of related links, such as to an SCM repository or bug tracker. The search site will output these links.

Have a look at the [`pair` `META.json` file](http://github.com/theory/kv-pair/blob/master/META.json) for an extended example.

### New Order ###

PGXN doesn't really care how distributions are structured, or if they use [PGXS](http://www.postgresql.org/docs/current/static/xfunc-c.html#XFUNC-C-PGXS). That said, the proposed [download and installation client](http://wiki.postgresql.org/wiki/PGXN#PGXN_Client) will assume the use of PGXS (unless and until the PostgreSQL core adds some other kind of extension-building support), so it's probably the best choice.

Most PGXS-powered distributions have the code files in the main directory, with documentation in a `README.extension_name` file. What we'd like to see instead, and will encourage via the forthcoming [search site](http://wiki.postgresql.org/wiki/PGXN#Search_Site), is that things be organized into subdirectories:

* `src` for any C source code files
* `sql` for SQL source files. These usually are responsible for installing an extension into a database
* `doc` for documentation files (the search site will likely look there for Markdown, Textile, HTML, and other document formats)
* `test` for tests

The `pair` distribution serves as an [example of this](http://github.com/theory/kv-pair/blob/). To make it all work, the [Makefile](http://github.com/theory/kv-pair/blob/master/Makefile) is written like so:

    DATA = sql/pair.sql sql/uninstall_pair.sql
    TESTS = $(wildcard test/sql/*.sql)
    REGRESS = $(patsubst test/sql/%.sql,%,$(TESTS))
    REGRESS_OPTS = --inputdir=test
    DOCS = doc/pair.txt

    ifdef NO_PGXS
    top_builddir = ../..
    include $(top_builddir)/src/Makefile.global
    include $(top_srcdir)/contrib/contrib-global.mk
    else
    PG_CONFIG = pg_config
    PGXS := $(shell $(PG_CONFIG) --pgxs)
    include $(PGXS)
    endif

The `DATA` variable identifies the SQL files containing the extension, while `TESTS` loads a list test files, which are in the `test/sql` directory. Note that the `pair` distribution uses `pg_regress` for tests, and `pg_reqress` expects that test files will have corresponding "expected" files to compare against. With the `REGRESS_OPTS = --inputdir=test` line, The distribution tells `pg_regess` to find the test files in [`test/sql`](http://github.com/theory/kv-pair/tree/master/test/sql/) and the expected output files in [`test/expected`](http://github.com/theory/kv-pair/tree/master/test/expected/). And finally, the `DOCS` variable points to a single file with the documentation, [`doc/pair.txt`](http://github.com/theory/kv-pair/blob/master/doc/pair.txt). If this extension had required any C code (like [pgTAP](http://pgtap.org/) or [PostGIS](http://postgis.org/) do), The `Makefile` would have pointed the `MODULES` variable at files in a `src` directory.

The remainder of the `Mafefile` consists of build instructions. If executed with `make NO_PGXS=1`, it assumes that the distribution directory has been put in the "contrib" directory of the PostgreSQL source tree used to build PostgreSQL. That's probably only important if one is installing on PostgreSQL 8.1 or lower. Otherwise, it assumes a plain `make` and uses the [`pg_config`](http://www.postgresql.org/docs/current/static/app-pgconfig.html) in the system path to find `pg_config` to do the build. And even with that, a sys admin can always point directly to it by executing `PG_CONFIG=/path/to/pg_config make`.

Either way, building and installing the extension should be as simple as:

    make
    make install
    make installcheck PGDATABASE=postgres

For more on PostgreSQL extension building support, please consult [the documentation](http://www.postgresql.org/docs/9/static/xfunc-c.html#XFUNC-C-PGXS).

### Zip Me Up ###

Once you've got your extension developed and well-tested, and your distribution just right and the `META.json` file all proof-read and solid, it's time to upload the distribution to PGXN. What you want to do is to zip it up to create a distribution archive. Here's what how the `pair` distribution -- which is maintained in Git -- was prepared:

    git checkout-index -af --prefix ~/Desktop/pair-0.1.0/
    cd ~/Desktop/
    rm pair-0.1.0/.gitignore
    zip -r pair-0.1.0.zip pair-0.1.0

Then the `pair-0.1.0.zip` file was ready to upload. Simple, eh?

Now, one can upload any kind of archive file to PGXN, including a tarball, or bzip2…um…ball? Basically, any kind of archive format recognized by [Archive::Extract](http://search.cpan.org/perldoc?Archive::Extract). A zip file is best because then PGXN::Manager won't have to rewrite it. It's also preferable that everything be packed into a directory with the name `$distribution-$version`, as in the example `pair-0.1.0` example above. If not, PGXN will rewrite it that way. But it saves the server some effort if all it has to do is move a .zip file that's properly formatted, so it would be appreciated if you would upload stuff that's already nicely formatted for distribution in a zip archive.

### Release It! ###

And that's it! Not too bad, eh? Just please do be very careful cutting and pasting examples. Hopefully we'll be able to build things up to the point where a lot of this stuff can be automated (especially the creation of the `META.json`), but for now it's done by hand. So be careful out there, and good luck!
