PGXN is the PostgreSQL Extension Network. If you're a PostgreSQL developer, you've no doubt created customizations to make your life simpler. This is possible because PostgreSQL today is not merely a database, it’s an application development platform. If you'd like to distribute such customizations in open-source releases for your fellow PostgreSQL enthusiasts to enjoy, PGXN is the place to do it.

This document explains how. There's some background information, too, but the goal is to provide the information and references you need to get started packaging your extensions and distributing them on PGXN. If anything is unclear, please do [let us know](/contact). It's our aim to make this the one stop for all of your PGXN distribution needs.

### OMG Distribution WTF? ###

First of all, what is a "distribution" in the PGXN sense? Basically, it's a collection of one or more [PostgreSQL](http://www.postgresql.org/) extensions. That's it.

Oh, so now you want to know what an "extension" is? Naturally. Traditionally, a PostgreSQL extension has been any code that can be built by [PGXS](http://www.postgresql.org/docs/current/static/xfunc-c.html#XFUNC-C-PGXS) and installed into the database. The PostgreSQL [contributed modules](http://www.postgresql.org/docs/current/static/contrib.html) provide excellent examples. On PGXN some examples are:

* [pair](http://pgxn.org/dist/pair/): a pure SQL data type
* [semver](http://pgxn.org/dist/semver/): a data type implemented in C
* [italian_fts](http://pgxn.org/dist/italian_fts/): An italian full-text search ditctionary

As of PostgreSQL 9.1, however, extensions have been integrated more deeply into the core. With just a bit more work, users who have installed an extension will be able to load it into the database with a simple command:

    CREATE EXTENSION pair;

No more need to run SQL scripts through `psql` or to maintain separate schemas to properly keep them packaged up. The documentation [has the details](http://www.postgresql.org/docs/9.1/static/extend-extensions.html "PostgreSQL Documentation: “Packaging Related Objects into an Extension”"). However, the build infrastructure is the same. From your point of view as a PostgreSQL extension developer, you're still going to use [PGXS](http://www.postgresql.org/docs/current/static/xfunc-c.html#XFUNC-C-PGXS) to configure and build your extension, and can distribute it via PGXN.

All this is not to say that PGXN extensions must be PostgreSQL extensions, except in the sense that they should add something to PostgreSQL. For example, You might want to distribute a command-line utility like [pg_top](http://pgxn.org/dist/pg_top/). That's cool. Just be creative and make PostgreSQL better and you'll be on the right track.

### That's So Meta ###

At its simplest, the only thing PGXN requires of a distribution is a single file, `META.json`, which describes the package. This is the file that PGXN Manager uses to index a distribution, so it's important to get it right. The [PGXN Meta Spec](http://pgxn.org/spec/) has all the details on what's required, but what follows is a pragmatic overview.

If you have only one `.sql` file for your extension and it's the same name as the distribution, then you can make it pretty simple. For example, the [`pair`](http://master.pgxn.org/dist/pair/) distribution has only one SQL file. So the `META.json` could be:

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

To really take advantage of PGXN, you'll want your extension to show up prominently in search results. Adding other keys to your `META.json` file will help. Other useful keys to include are:

* [`provides`](http://pgxn.org/spec/#provides): A list of included extensions. Useful if you have more than one in a single distribution. It also will assign ownership of the specified extension names to you -- if they haven't been claimed by any previous distribution. Strongly recommended.
* [`tags`](http://pgxn.org/spec/#tags): An array of tags to associate with a distribution. Will help with searching.
* [`prereqs`](http://pgxn.org/spec/#prereqs): A list of prerequisite extensions or PostgreSQL contrib modules (or PostgreSQL itself).
* [`release_status`](http://pgxn.org/spec/#release_status): To label a distribution as "stable," "unstable," or "testing." The latter two are useful for distributing extensions for testing but that should not be installed by automated clients or visible in the full-text search provided by the API server.
* [`resources`](http://pgxn.org/spec/#resources): A list of related links, such as to an SCM repository or bug tracker. The search site displays these links on the home page for the distribution.

So here's a more extended example from the `pair` data type:

    {
       "name": "pair",
       "abstract": "A key/value pair data type",
       "description": "This library contains a single PostgreSQL extension, a key/value pair data type called “pair”, along with a convenience function for constructing key/value pairs.",
       "version": "0.1.4",
       "maintainer": [
          "David E. Wheeler <david@justatheory.com>"
       ],
       "license": "postgresql",
       "provides": {
          "pair": {
             "abstract": "A key/value pair data type",
             "file": "sql/pair.sql",
             "docfile": "doc/pair.md",
             "version": "0.1.2"
          }
       },
       "resources": {
          "bugtracker": {
             "web": "http://github.com/theory/kv-pair/issues/"
          },
          "repository": {
            "url":  "git://github.com/theory/kv-pair.git",
            "web":  "http://github.com/theory/kv-pair/",
            "type": "git"
          }
       },
       "generated_by": "David E. Wheeler",
       "meta-spec": {
          "version": "1.0.0",
          "url": "http://pgxn.org/meta/spec.txt"
       },
       "tags": [
          "variadic function",
          "ordered pair",
          "pair",
          "key value",
          "key value pair"
       ]
    }

Thanks to all that metadata, the extension gets a [very nice page](http://pgxn.org/dist/pair/) on PGXN.  Note especially the `docfile` key in the `provides` section. This is the best way to tell PGXN where to find documentation to index. More on that below.

### We Have Assumed Control ###

A second file you should consider including in your distribution is a "control file". This file is required by the PostgreSQL 9.1 [extension support](http://www.postgresql.org/docs/9.1/static/extend-extensions.html "PostgreSQL Documentation: “Packaging Related Objects into an Extension”"). Like `META.json` it describes your extension, but it's actually much shorter. Really all it needs is a few keys. Here's an example from the [semver distribution](http://pgxn.org/dist/semver/) named `semver.control`:

    # semver extension
    comment = 'A semantic version data type'
    default_version = '0.2.1'
    module_pathname = '$libdir/semver'
    relocatable = true

The `default_version` value specifies the version of the extension you're distributing, the `module_pathname` value may be required for C extensions, and the `relocatable` value determines whether an extension can be moved from one schema to another. These are the keys you will most often use, but there are quite a few [other keys](http://www.postgresql.org/docs/9.1/static/extend-extensions.html) you might want to review as you develop your extension.

For database objects, you are *strongly encouraged* to include a control file and support for `CREATE EXTENSION` in your `Makefile`. This is the way of the future folks, and, frankly, quite easy to do.

### New Order ###

PGXN doesn't really care how distributions are structured, or if they use [PGXS](http://www.postgresql.org/docs/current/static/xfunc-c.html#XFUNC-C-PGXS). That said, the [pgxn client](http://github.com/dvarrazzo/pgxnclient/) currently supports only `./configure` and `make`, so PGXS is probably the best choice.

We strongly encourage that the files in distributions be organized into subdirectories:

* `src` for any C source code files
* `sql` for SQL source files
* `doc` for documentation files
* `test` for tests

The [`pair`](http://github.com/theory/kv-pair/) and [`semver`](http://github.com/theory/pg-semver/) distributions serve as examples of this. To make it all work, their `Makefile`s are written like so:

    EXTENSION    = pair
    EXTVERSION   = $(shell grep default_version $(EXTENSION).control | \
                   sed -e "s/default_version[[:space:]]*=[[:space:]]*'\([^']*\)'/\1/")

    DATA         = $(filter-out $(wildcard sql/*--*.sql),$(wildcard sql/*.sql))
    TESTS        = $(wildcard test/sql/*.sql)
    REGRESS      = $(patsubst test/sql/%.sql,%,$(TESTS))
    REGRESS_OPTS = --inputdir=test
    DOCS         = $(wildcard doc/*.md)
    # MODULES      = $(patsubst %.c,%,$(wildcard src/*.c))
    PG_CONFIG    = pg_config
    PG91         = $(shell $(PG_CONFIG) --version | grep -qE " 8\.| 9\.0" && echo no || echo yes)

    ifeq ($(PG91),yes)
    all: sql/$(EXTENSION)--$(EXTVERSION).sql

    sql/$(EXTENSION)--$(EXTVERSION).sql: sql/$(EXTENSION).sql
    	cp $< $@

    DATA = $(wildcard sql/*--*.sql) sql/$(EXTENSION)--$(EXTVERSION).sql
    EXTRA_CLEAN = sql/$(EXTENSION)--$(EXTVERSION).sql
    endif

    PGXS := $(shell $(PG_CONFIG) --pgxs)
    include $(PGXS)

The `EXTENSION` variable identifies the extension you're distributing. `EXTVERSION` identifies its version, which is here read from the control file, so you only have to edit it there (and in the `META.json` file).

The `DATA` variable identifies the SQL files containing the extension, while `TESTS` loads a list test files, which are in the `test/sql` directory. Note that the `pair` distribution uses `pg_regress` for tests, and `pg_reqress` expects that test files will have corresponding "expected" files to compare against. With the `REGRESS_OPTS = --inputdir=test` line, The distribution tells `pg_regess` to find the test files in [`test/sql`](http://github.com/theory/kv-pair/tree/master/test/sql/) and the expected output files in [`test/expected`](http://github.com/theory/kv-pair/tree/master/test/expected/). And finally, the `DOCS` variable finds all the files ending in `.md` in the [`doc` directory](http://github.com/theory/kv-pair/tree/master/doc/).

The `MODULES` variable finds `.c` files in the `src` directory. The `pair` data type has no C code, so it's commented-out. You'll want to uncomment it if you have C code or add C code later.

Next we have the `PG_CONFIG` variable. This points to the [`pg_config`](http://www.postgresql.org/docs/9.0/static/app-pgconfig.html) utility, which is required to find `PGXS` and build the extension. If a user has it in her path, it will just work. Otherwise, she can point to an alternate one when building:

    make PG_CONFIG=/path/to/pg_config

The `Makefile` next uses `pg_config` to determine whether the extension is being built against PostgreSQL 9.1 or higher. Based on what it finds, extra steps are taken in the following section. That is, if this line returns true:

    ifeq ($(PG91),yes)

Then we're building against 9.1 or higher. In that case, the extension SQL file gets copied to `$EXTENSION--$EXTVERSION.sql` and added to `EXTRA_CLEAN` so that `make clean` will delete it. The `DATA` variable, meanwhile, is changed to hold only SQL file names that contain `--`, because such is the required file naming convention for PostgreSQL 9.1 extensions.

The last two lines of the `Mafefile` do the actual building by including the `PGXS` `Makefile` distributed with PostgreSQL. `PGXS` knows all about building and installing extensions, based on the variables we've set, and including it makes it do just that.

So now, building and installing the extension should be as simple as:

    make
    make install
    make installcheck PGDATABASE=postgres

For more on PostgreSQL extension building support, please consult [the documentation](http://www.postgresql.org/docs/9/static/xfunc-c.html#XFUNC-C-PGXS).

### What's up, Doc? ###

To further raise the visibility and utility of your extension for users, you're encouraged to include a few other files, as well:

* A `README` is a great way to introduce the basics of your extension, to give folks a chance to determine its purpose. Installation instructions are also common here. Plus, it makes a a nice addition to the distribution page on PGXN ([example](http://pgxn.org/dist/explanation/)). To get the most benefit, mark it up and save it with a suffix recognized by [Text::Markup](http://search.cpan.org/perldoc?Text::Markup) and get nice HTML formatting on the site.
* A `Changes` file ([example](http://api.pgxn.org/src/explanation/explanation-0.3.0/Changes)). This file will make it easier for users to determine if they need to upgrade when a new version comes out. 
* `LICENSE`, `INSTALL`, `COPYING`, and `AUTHORS` are likewise also linked from the distribution page.

But perhaps the most important files to consider adding to your distribution are documentation files. Like the `README`, the API server will parse and index any file recognized by [Text::Markup](http://search.cpan.org/perldoc?Text::Markup). The main PGXN search index contains documentation files, so it's important to have great documentation. Files may be anywhere in the distribution, though of course a top-level `doc` or `docs` directory is recommended (and recognized by the `Makefile` example above).

To give you a feel for how important documentation is to the exposure of your PGXN distribution, try [searching for "sha"](http://pgxn.org/search?q=sha&in=docs). As of this writing, there are no results, despite the fact that there is, in fact, a [sha distribution](http://pgxn.org/dist/sha/1.0.0/). Note also that the [distribution page](http://pgxn.org/dist/sha/1.0.0/) lists "sha" as an extension, but unlike [other](http://pgxn.org/dist/tinyint/) [distribution](http://pgxn.org/dist/semver/) [pages](http://pgxn.org/dist/pair/), it does not link to documentation.

Even if you don't map a documentation file to an extension, adding documentation files can be great for your search mojo. See [pgmp](http://pgxn.org/dist/pgmp/), for example, which as of this writing does not link the extension to a documentation file, but a whole series of other documentation files are linked (and indexed).

To sum up, for maximum PGXN coverage, the only rules for documentation files are:

* They must be written in UTF-8 or specify their encodings via a [BOM](http://en.wikipedia.org/wiki/Byte_order_mark) or markup-specific tag (such as the `=encoding` Pod tag).
* They must be recognized by [Text::Markup](http://search.cpan.org/perldoc?Text::Markup).

### Zip Me Up ###

Once you've got your extension developed and well-tested, and your distribution just right -- with the `META.json` file all proof-read and solid a nice `README` and comprehensive docs -- it's time to wake up, and release it! What you want to do is to zip it up to create a distribution archive. Here's how the `pair` distribution -- which is maintained in Git -- was prepared:

    git archive --format zip --prefix=pair-0.1.2/ \
    --output ~/Desktop/pair-0.1.2.zip master

Then the `pair-0.1.0.zip` file was ready to release. Simple, eh?

Now, one can upload any kind of archive file to PGXN, including a tarball, or bzip2…um…ball? Basically, any kind of archive format recognized by [Archive::Extract](http://search.cpan.org/perldoc?Archive::Extract). A zip file is best because then PGXN::Manager won't have to rewrite it. It's also preferable that everything be packed into a directory with the name `$distribution-$version`, as in the `pair-0.1.2` example above. If not, PGXN will rewrite it that way. But it saves the server some effort if all it has to do is move a `.zip` file that's properly formatted, so it would be appreciated if you would upload stuff that's already nicely formatted for distribution in a zip archive.

### Release It! ###

And that's it! Not too bad, eh? Just please do be very careful cutting and pasting examples. Or better yet, give [pgxn-utils](https://github.com/guedes/pgxn-utils/) a try. It will create a skeleton distribution for you and make it easy to add new stuff as you develop. It also puts all the files in the recommended places.

Good hacking!
