PGXN is the PostgreSQL Extension Network. If you're a PostgreSQL developer,
you've no doubt created customizations to make your life simpler. This is
possible because PostgreSQL today is not merely a database, it’s an application
development platform. If you'd like to distribute such customizations in
open-source releases for your fellow PostgreSQL enthusiasts to enjoy, PGXN is
the place to do it.

This document explains how. There's some background information, too, but the
goal is to provide the information and references you need to get started
packaging your extensions and distributing them on PGXN. If anything is unclear,
please do [let us know]. It's our aim to make this the one stop for all of your
PGXN distribution needs.

<h3>Contents</h3>

{{TOC}}

### OMG Distribution WTF?

First of all, what is a "distribution" in the PGXN sense? Basically, it's a
collection of one or more [PostgreSQL] extensions. That's it. The PostgreSQL
[additional supplied modules] provide excellent examples. On PGXN some examples
are:

*   [pair]: a pure SQL data type
*   [semver]: a data type implemented in C
*   [italian_fts]: An italian full-text search dictionary

Traditionally, a PostgreSQL extension was any code that could be built by [PGXS]
and installed into the database. PostgreSQL 9.1 integrated extensions more
deeply into the core. With just a bit more work, users who have installed an
extension will be able to load it into the database with a simple command:

    CREATE EXTENSION pair;

The documentation [has the details][extensions]. As a PostgreSQL extension
developer, use [PGXS] to configure and build your extension.

All this is not to say that PGXN extensions must be PostgreSQL extensions,
except in the sense that they should add something to PostgreSQL. For example,
you might want to distribute a command-line utility like [pg_top]. That's cool.
Just be creative and make PostgreSQL better and you'll be on the right track.

### That's So Meta

At its simplest, the only thing PGXN requires of a distribution is a single
file, `META.json`, which describes the package. PGXN Manager uses this file to
index a distribution, so it's important to get it right. The [PGXN Meta Spec]
has all the details on what's required, but what follows is a pragmatic
overview.

If you have only one `.sql` file for your extension and it's the same name as
the distribution, then you can make it pretty simple. For example, the [pair]
distribution has only one SQL file. So the `META.json` could be:

``` json
{
   "name": "pair",
   "abstract": "A key/value pair data type",
   "version": "0.1.0",
   "maintainer": "David E. Wheeler <david@justatheory.com>",
   "license": "postgresql",
   "provides": {
      "pair": {
         "abstract": "A key/value pair data type",
         "file": "sql/pair.sql",
         "docfile": "doc/pair.md",
         "version": "0.1.0"
      }
   },
   "meta-spec": {
      "version": "1.0.0",
      "url": "https://pgxn.org/meta/spec.txt"
   }
}
```
    
That's it. Note that all version numbers in a `META.json` *must* be [semantic
versions][semver], including for core dependencies like [PL/Perl] or PostgreSQL
itself. If they're not, PGXN cannot index your distribution. If you don't want
to read through the [Semantic Versioning 2.0.0 spec][semver], just use thee-part
dotted integers (such as "1.2.0") and don't worry about it.

One thing that might be confusing here is the redundant information in the
`provides` section. While the `name`, `abstract`, and `version` keys at the top
level of the JSON describe the distribution itself, the `provides` section
contains a list of all the extensions provided by the distribution. There is
only one extension in this distribution, hence the duplication. But in some
cases, such as [pgTAP], there will be multiple extensions, each with its own
information. PGXN also uses this information to assign ownership of the
specified extension names to you -- if they haven't been claimed by any previous
distribution.

To really take advantage of PGXN, you'll want your extension to show up
prominently in search results. Adding other keys to your `META.json` file will
help. Other useful keys to include are:

*   [`tags`]: An array of tags to associate with a distribution. Will help with
    searching.
*   [`prereqs`]: A list of prerequisite extensions or PostgreSQL contrib modules
    (or PostgreSQL itself).
*   [`release_status`]: To label a distribution as "stable," "unstable," or
    "testing." The latter two are useful for distributing extensions for testing
    but that should not typically be installed by automated clients or visible
    in the full-text search provided by the API server.
*   [`resources`]: A list of related links, such as to an SCM repository or bug
    tracker. The search site displays these links on the home page for the
    distribution.

So here's a more extended example from the `pair` data type:

``` json
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
         "version": "0.1.0"
      }
   },
   "resources": {
      "bugtracker": {
         "web": "https://github.com/theory/kv-pair/issues/"
      },
      "repository": {
      "url":  "git://github.com/theory/kv-pair.git",
      "web":  "https://github.com/theory/kv-pair/",
      "type": "git"
      }
   },
   "generated_by": "David E. Wheeler",
   "meta-spec": {
      "version": "1.0.0",
      "url": "https://pgxn.org/meta/spec.txt"
   },
   "tags": [
      "variadic function",
      "ordered pair",
      "pair",
      "key value",
      "key value pair",
      "data type"
   ]
}
```

PGXN Manager will verify the `META.json` file and complain if it's not right.
You can also check it before uploading by installing [PGXN::Meta::Validator] and
running:

    validate_pgxn_meta META.json

Or, if you also have the [pgxn client] installed, it's just

    pgxn validate-meta

Thanks to all that metadata, the extension gets a [very nice page][pair] on
PGXN. Note especially the `docfile` key in the `provides` section. This is the
best way to tell PGXN where to find documentation to index. More on that below.

### We Have Assumed Control

A second file you need to provide for PostgreSQL [extensions], is the "control
file". This file enables `CREATE EXTENSION`. Like `META.json` it describes your
extension, but it's much shorter. Really all it needs is a few keys. Here's an
example from the [semver distribution][semver] named `semver.control`:

``` ini
# semver extension
comment = 'A semantic version data type'
default_version = '0.2.1'
module_pathname = '$libdir/semver'
relocatable = true
```

The `default_version` value specifies the version of the extension you're
distributing, the `module_pathname` value may be required for C extensions, and
the `relocatable` value determines whether an extension can be moved from one
schema to another. These are the keys you will most often use, but there are
quite a few [other keys][extensions] you might want to review as you develop
your extension.

### New Order

PGXN doesn't really care how distributions are structured, or if they use
[PGXS]. That said, the [pgxn client] currently supports only `./configure` and
`make`, so PGXS is probably the best choice.

We strongly encourage that the files in distributions be organized into
subdirectories:

*   `src` for any C source code files
*   `sql` for SQL source files
*   `doc` for documentation files
*   `test` for tests

The [pair] and [semver] distributions serve as examples of this. To make it all
work, their `Makefile`s are written like so:

``` makefile
EXTENSION    = $(shell grep -m 1 '"name":' META.json | \
               sed -e 's/[[:space:]]*"name":[[:space:]]*"\([^"]*\)",/\1/')
EXTVERSION   = $(shell grep -m 1 '[[:space:]]\{8\}"version":' META.json | \
               sed -e 's/[[:space:]]*"version":[[:space:]]*"\([^"]*\)",\{0,1\}/\1/')
DISTVERSION  = $(shell grep -m 1 '[[:space:]]\{3\}"version":' META.json | \
               sed -e 's/[[:space:]]*"version":[[:space:]]*"\([^"]*\)",\{0,1\}/\1/')

DATA 		    = $(wildcard sql/*--*.sql)
TESTS        = $(wildcard test/sql/*.sql)
DOCS         = $(wildcard doc/*.md)
REGRESS      = $(patsubst test/sql/%.sql,%,$(TESTS))
REGRESS_OPTS = --inputdir=test
# MODULES    = $(patsubst %.c,%,$(wildcard src/*.c))
PG_CONFIG   ?= pg_config
PG91         = $(shell $(PG_CONFIG) --version | grep -qE " 8\.| 9\.0" && echo no || echo yes)
EXTRA_CLEAN = sql/$(EXTENSION)--$(EXTVERSION).sql

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

all: sql/$(EXTENSION)--$(EXTVERSION).sql

sql/$(EXTENSION)--$(EXTVERSION).sql: sql/$(EXTENSION).sql
	cp $< $@

dist:
	git archive --format zip --prefix=$(EXTENSION)-$(DISTVERSION)/ -o $(EXTENSION)-$(DISTVERSION).zip HEAD
```

The `EXTENSION` variable is read in from `META.json` to identify the extension
you're distributing. `EXTVERSION`, also read from `META.json`, identifies the
extension version (that is, the one from the `provides` section), so you only
have to edit it there (and in the control file). Same for `DISTVERSION`, which
is handy for building a release (more on that shortly).

The `DATA` variable identifies the SQL files containing the extension or
extensions, while `TESTS` loads a list test files, which are in the `test/sql`
directory. The `DOCS` variable finds all the files ending in `.md` in the [`doc`
directory]. For distributions testing with `pg_regress`, it expects that test
files will have corresponding "expected" files to compare against. Thanks to the
`REGRESS_OPTS = --inputdir=test` line, `pg_regress` will find the test files in
[`test/sql`] and the expected output files in [`test/expected`].

The `MODULES` variable finds `.c` files in the `src` directory. The `pair` data
type has no C code, so it's commented-out. You'll want to uncomment it if you
have C code or add C code later.

Next we have the `PG_CONFIG` variable. This points to the [`pg_config`] utility,
which is required to find PGXS and build the extension. If a user has it in
their path, it will just work. Otherwise, they can point to an alternate one
when building:

    make PG_CONFIG=/path/to/pg_config

Thanks to the `?=` operator, it can also be set as an environment variable,
which is useful for executing multiple `make` commands in a one-liner:

    env PG_CONFIG=/path/to/pg_config make && make install && make installcheck

The next two lines of the `Makefile` do the actual building by including the
`PGXS` `Makefile` distributed with PostgreSQL. PGXS knows all about building and
installing extensions, based on the variables we've set, and including it makes
it do just that.

Once the PGXS `Makefile` is loaded, we are free to define other targets. We take
advantage of this to add a `$EXTENSION--$EXTVERSION.sql` target to copy create
the versioned SQL file for `CREATE EXTENSION` to find.

The last three lines define a `dist` target described bellow.

So now, building and installing the extension should be as simple as:

    make
    make install
    make installcheck PGDATABASE=postgres

For more on PostgreSQL extension building support, please consult [the
documentation][PGXS].

### What's up, Doc?

To further raise the visibility and utility of your extension for users, you're
encouraged to include a few other files, as well:

*   A `README` is a great way to introduce the basics of your extension, to give
    folks a chance to determine its purpose. Installation instructions are also
    common here. Plus, it makes a a nice addition to the distribution page on
    PGXN ([example][hostname]). To get the most benefit, mark it up and save it
    with a suffix recognized by [Text::Markup] and get nice HTML formatting on
    the site.
*   A `Changes` file ([example][changes]). This file will make it easier for
    users to determine if they need to upgrade when a new version comes out. 
*   `LICENSE`, `INSTALL`, `COPYING`, and `AUTHORS` files are also linked from
    the distribution page.

The most important files to consider adding to your distribution are
documentation files. Like the `README`, the API server will parse and index any
file recognized by [Text::Markup]. The main PGXN search index contains
documentation files, so it's important to have great documentation. Files may be
anywhere in the distribution, though of course a top-level `doc` or `docs`
directory is recommended (and recognized by the `Makefile` example above).

To give you a feel for how important documentation is to the exposure of your
PGXN distribution, try [searching for "sha"]. As of this writing, there are five
results, none of which include the [sha distribution][sha]. Note also that the
[distribution page][sha] lists "sha" as an extension, but unlike
[other][tinyint] [distribution][semver] [pages][pair], it does not link to
documentation.

Even if you don't map a documentation file to an extension, adding documentation
files can be great for your search mojo. See [pgmp], for example, which as of
this writing does not link the extension to a documentation file, but a whole
series of other documentation files are linked (and indexed).

To sum up, for maximum PGXN coverage, the only rules for documentation files
are:

*   They must be written in UTF-8 or specify their encodings via a [BOM] or
    markup-specific tag (such as the `=encoding` Pod tag).
*   They must be recognized by [Text::Markup].

### Zip Me Up

Once you've got your extension developed and well-tested, and your distribution
just right -- with the `META.json` file all proof-read and solid a nice `README`
and comprehensive docs -- it's time to *wake up,* and release it! Simply zip it
up to create a distribution archive. If you're using Git, you can use the `dist`
target included in the `Makefile` template above, like so:

    make dist

The resulting `.zip` file is ready to release. Simple, eh?

Now, one can upload any kind of archive file to PGXN, including a tarball, or
bzip2…um…ball? Basically, any kind of archive format recognized by
[Archive::Extract]. A zip file is best because PGXN Manager won't have to
rewrite it. It's also preferable that everything be packed into a directory with
the name `$distribution-$version`, as the Git-using `make dist` target does. If
the files are not packed into `$distribution-$version`, PGXN will rewrite it
that way. But it saves the server some effort if all it has to do is move a
`.zip` file that's properly formatted.

### Release It!

Now [request an account] if you don't already have one, hit the "Upload" link in
the side navigation, and the release zip file.

And that's it! Not too bad, eh? Just please do be very careful cutting and
pasting examples. Or better yet, give [pgxn-utils] a try. It will create a
skeleton distribution for you and make it easy to add new stuff as you develop.
It also puts all the files in the recommended places, and can create and upload
a release directly to PGXN Manager. Give it a whirl!

Good hacking!

  [let us know]: https://manager.pgxn.org/contact "Contact PGXN"
  [PostgreSQL]: https://www.postgresql.org/
  [additional supplied modules]: https://www.postgresql.org/docs/current/static/contrib.html
  [pair]: https://pgxn.org/dist/pair/
  [semver]: https://pgxn.org/dist/semver/
  [italian_fts]: https://pgxn.org/dist/italian_fts/
  [PGXS]: https://www.postgresql.org/docs/current/static/extend-pgxs.html
    "PostgreSQL Documentation: “Extension Building Infrastructure”"
  [extensions]: https://www.postgresql.org/docs/current/static/extend-extensions.html
    "PostgreSQL Documentation: “Packaging Related Objects into an Extension”"
  [pg_top]: https://pgxn.org/dist/pg_top/
  [PGXN Meta Spec]: https://pgxn.org/spec/
  [semver]: https://semver.org/spec/v2.0.0.html
  [PL/Perl]: https://www.postgresql.org/docs/current/plperl.html
  [pgTAP]: https://pgxn.org/dist/pgtap/
  [`tags`]: https://pgxn.org/spec/#tags
  [`prereqs`]: https://pgxn.org/spec/#prereqs
  [`release_status`]: https://pgxn.org/spec/#release_status
  [`resources`]: https://pgxn.org/spec/#resources
  [PGXN::Meta::Validator]: https://metacpan.org/release/PGXN-Meta-Validator
  [pgxn client]: https://github.com/dvarrazzo/pgxnclient/
  [`doc` directory]: https://github.com/theory/kv-pair/tree/main/doc/
  [`test/sql`]: https://github.com/theory/kv-pair/tree/main/test/sql/
  [`test/expected`]: https://github.com/theory/kv-pair/tree/main/test/expected/
  [`pg_config`]: https://www.postgresql.org/docs/current/static/app-pgconfig.html
  [hostname]: https://pgxn.org/dist/hostname/
  [Text::Markup]: https://metacpan.org/pod/Text::Markup)
  [changes]: https://api.pgxn.org/src/hostname/hostname-1.0.2/Changes
  [searching for "sha"]: https://pgxn.org/search?q=sha&in=docs
  [sha]: https://pgxn.org/dist/sha/1.1.0/
  [tinyint]: https://pgxn.org/dist/tinyint/
  [pgmp]: https://pgxn.org/dist/pgmp/
  [BOM]: https://en.wikipedia.org/wiki/Byte_order_mark
  [Archive::Extract]: https://metacpan.org/pod/Archive::Extract
  [pgxn-utils]: https://github.com/guedes/pgxn-utils/
  [request an account]: https://manager.pgxn.org/account/register
