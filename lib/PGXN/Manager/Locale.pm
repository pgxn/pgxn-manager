package PGXN::Manager::Locale;

use 5.10.0;
use utf8;
use parent 'Locale::Maketext';
use I18N::LangTags::Detect;

our $VERSION = v0.14.0;

# Allow unknown phrases to just pass-through.
our %Lexicon = (
    _AUTO => 1,
    listcomma => ',',
    listand   => 'and',
    openquote => '“',
    shutquote => '”',
    home_page_title => 'Distribute PostgreSQL extensions on our world-wide network',
    Welcome   => 'Welcome',
    'PGXN Manager' => 'PGXN Manager',
    tagline => 'Release it on PGXN!',
    'Resource not found.' => 'Hrm. I can’t find a resource at this address. I looked over here and over there and could find nothing. Sorry about that, I’m fresh out of ideas.',
    'Not Found' => 'Where’d It Go?',
    about_page_title => 'All about PGXN, the PostgreSQL Extension Network',
    contact_page_title => 'How to get in touch with the responsible parties',
    '"[_1]" is missing the required [numerate,_2,key] [qlist,_3]' => '“[_1]” is missing the required [numerate,_2,key] [qlist,_3]',
    '"[_1]" is missing the required [numerate,_2,key] [qlist,_3] under [_4]' => '“[_1]” is missing the required [numerate,_2,key] [qlist,_3] under [_4]',
    '"[_1]" is an invalid distribution name' => '“[_1]” is not a valid distribution name. Distribution names must be at least two characters and may not contain unprintable or whitespace characters or /, \\, or :.',
    howto_page_title => 'How to create PostgreSQL extensions and distribute them on PGXN',
    howto_body => q{
<p>PGXN is the PostgreSQL Extension Network. If you&rsquo;re a PostgreSQL developer, you&rsquo;ve no doubt created customizations to make your life simpler. This is possible because PostgreSQL today is not merely a database, it’s an application development platform. If you&rsquo;d like to distribute such customizations in open-source releases for your fellow PostgreSQL enthusiasts to enjoy, PGXN is the place to do it.</p>

<p>This document explains how. There&rsquo;s some background information, too, but the goal is to provide the information and references you need to get started packaging your extensions and distributing them on PGXN. If anything is unclear, please do <a href="/contact">let us know</a>. It&rsquo;s our aim to make this the one stop for all of your PGXN distribution needs.</p>

<h3>OMG Distribution WTF?</h3>

<p>First of all, what is a &ldquo;distribution&rdquo; in the PGXN sense? Basically, it&rsquo;s a collection of one or more <a href="http://www.postgresql.org/">PostgreSQL</a> extensions. That&rsquo;s it.</p>

<p>Oh, so now you want to know what an &ldquo;extension&rdquo; is? Naturally. Traditionally, a PostgreSQL extension has been any code that can be built by <a href="http://www.postgresql.org/docs/current/static/xfunc-c.html#XFUNC-C-PGXS">PGXS</a> and installed into the database. The PostgreSQL <a href="http://www.postgresql.org/docs/current/static/contrib.html">contributed modules</a> provide excellent examples. On PGXN some examples are:</p>

<ul>
<li><a href="http://pgxn.org/dist/pair/">pair</a>: a pure SQL data type</li>
<li><a href="http://pgxn.org/dist/semver/">semver</a>: a data type implemented in C</li>
<li><a href="http://pgxn.org/dist/italian_fts/">italian_fts</a>: An italian full-text search ditctionary</li>
</ul>


<p>As of PostgreSQL 9.1, however, extensions have been integrated more deeply into the core. With just a bit more work, users who have installed an extension will be able to load it into the database with a simple command:</p>

<pre><code>CREATE EXTENSION pair;
</code></pre>

<p>No more need to run SQL scripts through <code>psql</code> or to maintain separate schemas to properly keep them packaged up. The documentation <a href="http://www.postgresql.org/docs/9.1/static/extend-extensions.html" title="PostgreSQL Documentation: “Packaging Related Objects into an Extension”">has the details</a>. However, the build infrastructure is the same. From your point of view as a PostgreSQL extension developer, you&rsquo;re still going to use <a href="http://www.postgresql.org/docs/current/static/xfunc-c.html#XFUNC-C-PGXS">PGXS</a> to configure and build your extension, and can distribute it via PGXN.</p>

<p>All this is not to say that PGXN extensions must be PostgreSQL extensions, except in the sense that they should add something to PostgreSQL. For example, You might want to distribute a command-line utility like <a href="http://pgxn.org/dist/pg_top/">pg_top</a>. That&rsquo;s cool. Just be creative and make PostgreSQL better and you&rsquo;ll be on the right track.</p>

<h3>That&rsquo;s So Meta</h3>

<p>At its simplest, the only thing PGXN requires of a distribution is a single file, <code>META.json</code>, which describes the package. This is the file that PGXN Manager uses to index a distribution, so it&rsquo;s important to get it right. The <a href="http://pgxn.org/spec/">PGXN Meta Spec</a> has all the details on what&rsquo;s required, but what follows is a pragmatic overview.</p>

<p>If you have only one <code>.sql</code> file for your extension and it&rsquo;s the same name as the distribution, then you can make it pretty simple. For example, the <a href="http://master.pgxn.org/dist/pair/"><code>pair</code></a> distribution has only one SQL file. So the <code>META.json</code> could be:</p>

<pre><code>{
   "name": "pair",
   "abstract": "A key/value pair data type",
   "version": "0.1.0",
   "maintainer": "David E. Wheeler &lt;david@justatheory.com&gt;",
   "license": "postgresql",
   "meta-spec": {
      "version": "1.0.0",
      "url": "http://pgxn.org/meta/spec.txt"
   },
}
</code></pre>

<p>That&rsquo;s it. The only thing that may not be obvious from this example is that all version numbers in a <code>META.json</code> <em>must</em> be <a href="http://semver.org/">semantic versions</a>, including for core dependencies like plperl or PostgreSQL itself. If they&rsquo;re not, PGXN will make them so. So &ldquo;1.2&rdquo; would become &ldquo;1.2.0&rdquo; &mdash; and so would &ldquo;1.02&rdquo;. So do try to use semantic version strings and don&rsquo;t worry about it.</p>

<p>To really take advantage of PGXN, you&rsquo;ll want your extension to show up prominently in search results. Adding other keys to your <code>META.json</code> file will help. Other useful keys to include are:</p>

<ul>
<li><a href="http://pgxn.org/spec/#provides"><code>provides</code></a>: A list of included extensions. Useful if you have more than one in a single distribution. It also will assign ownership of the specified extension names to you &mdash; if they haven&rsquo;t been claimed by any previous distribution. Strongly recommended.</li>
<li><a href="http://pgxn.org/spec/#tags"><code>tags</code></a>: An array of tags to associate with a distribution. Will help with searching.</li>
<li><a href="http://pgxn.org/spec/#prereqs"><code>prereqs</code></a>: A list of prerequisite extensions or PostgreSQL contrib modules (or PostgreSQL itself).</li>
<li><a href="http://pgxn.org/spec/#release_status"><code>release_status</code></a>: To label a distribution as &ldquo;stable,&rdquo; &ldquo;unstable,&rdquo; or &ldquo;testing.&rdquo; The latter two are useful for distributing extensions for testing but that should not be installed by automated clients.</li>
<li><a href="http://pgxn.org/spec/#resources"><code>resources</code></a>: A list of related links, such as to an SCM repository or bug tracker. The search site displays these links on the home page for the distribution.</li>
</ul>


<p>So here&rsquo;s a more extended example from the <code>pair</code> data type:</p>

<pre><code>{
   "name": "pair",
   "abstract": "A key/value pair data type",
   "description": "This library contains a single PostgreSQL extension, a key/value pair data type called “pair”, along with a convenience function for constructing key/value pairs.",
   "version": "0.1.4",
   "maintainer": ~[
      "David E. Wheeler &lt;david@justatheory.com&gt;"
   ~],
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
   "tags": ~[
      "variadic function",
      "ordered pair",
      "pair",
      "key value",
      "key value pair"
   ~]
}
</code></pre>

<p>Thanks to all that metadata, the extension gets a <a href="http://pgxn.org/dist/pair/">very nice page</a> on PGXN.  Note especially the <code>docfile</code> key in the <code>provides</code> section. This is the best way to tell PGXN where to find documentation to index. More on that below.</p>

<h3>We Have Assumed Control</h3>

<p>A second file you should consider including in your distribution is a &ldquo;control file&rdquo;. This file is required by the PostgreSQL 9.1 <a href="http://www.postgresql.org/docs/9.1/static/extend-extensions.html" title="PostgreSQL Documentation: “Packaging Related Objects into an Extension”">extension support</a>. Like <code>META.json</code> it describes your extension, but it&rsquo;s actually much shorter. Really all it needs is a few keys. Here&rsquo;s an example from the <a href="http://pgxn.org/dist/semver/">semver distribution</a> named <code>semver.control</code>:</p>

<pre><code># semver extension
comment = 'A semantic version data type'
default_version = '0.2.1'
module_pathname = '$libdir/semver'
relocatable = true
</code></pre>

<p>The <code>default_version</code> value specifies the version of the extension you&rsquo;re distributing, the <code>module_pathname</code> value may be required for C extensions, and the <code>relocatable</code> value determines whether an extension can be moved from one schema to another. These are the keys you will most often use, but there are quite a few <a href="http://www.postgresql.org/docs/9.1/static/extend-extensions.html">other keys</a> you might want to review as you develop your extension.</p>

<p>For database objects, you are <em>strongly encouraged</em> to include a control file and support for <code>CREATE EXTENSION</code> in your <code>Makefile</code>. This is the way of the future folks, and, frankly, quite easy to do.</p>

<h3>New Order</h3>

<p>PGXN doesn&rsquo;t really care how distributions are structured, or if they use <a href="http://www.postgresql.org/docs/current/static/xfunc-c.html#XFUNC-C-PGXS">PGXS</a>. That said, the <a href="http://github.com/dvarrazzo/pgxnclient/">pgxn client</a> currently supports only <code>./configure</code> and <code>make</code>, so PGXS is probably the best choice.</p>

<p>We strongly encourage that the files in distributions be organized into subdirectories:</p>

<ul>
<li><code>src</code> for any C source code files</li>
<li><code>sql</code> for SQL source files</li>
<li><code>doc</code> for documentation files</li>
<li><code>test</code> for tests</li>
</ul>


<p>The <a href="http://github.com/theory/kv-pair/"><code>pair</code></a> and <a href="http://github.com/theory/pg-semver/"><code>semver</code></a> distributions serve as examples of this. To make it all work, their <code>Makefile</code>s are written like so:</p>

<pre><code>EXTENSION    = pair
EXTVERSION   = $(shell grep default_version $(EXTENSION).control | \
               sed -e "s/default_version~[~[:space:~]~]*=~[~[:space:~]~]*'\(~[^'~]*\)'/\1/")

DATA         = $(filter-out $(wildcard sql/*--*.sql),$(wildcard sql/*.sql))
TESTS        = $(wildcard test/sql/*.sql)
REGRESS      = $(patsubst test/sql/%.sql,%,$(TESTS))
REGRESS_OPTS = --inputdir=test
DOCS         = $(wildcard doc/*.md)
MODULES      = $(patsubst %.c,%,$(wildcard src/*.c))
PG_CONFIG    = pg_config
PG91         = $(shell $(PG_CONFIG) --version | grep -qE " 8\.| 9\.0" &amp;&amp; echo no || echo yes)

ifeq ($(PG91),yes)
all: sql/$(EXTENSION)--$(EXTVERSION).sql

sql/$(EXTENSION)--$(EXTVERSION).sql: sql/$(EXTENSION).sql
    cp $&lt; $@

DATA = $(wildcard sql/*--*.sql) sql/$(EXTENSION)--$(EXTVERSION).sql
EXTRA_CLEAN = sql/$(EXTENSION)--$(EXTVERSION).sql
endif

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
</code></pre>

<p>The <code>EXTENSION</code> variable identifies the extension you&rsquo;re distributing. <code>EXTVERSION</code> identifies its version, which is here read from the control file, so you only have to edit it there (and in the <code>META.json</code> file).</p>

<p>The <code>DATA</code> variable identifies the SQL files containing the extension, while <code>TESTS</code> loads a list test files, which are in the <code>test/sql</code> directory. Note that the <code>pair</code> distribution uses <code>pg_regress</code> for tests, and <code>pg_reqress</code> expects that test files will have corresponding &ldquo;expected&rdquo; files to compare against. With the <code>REGRESS_OPTS = --inputdir=test</code> line, The distribution tells <code>pg_regess</code> to find the test files in <a href="http://github.com/theory/kv-pair/tree/master/test/sql/"><code>test/sql</code></a> and the expected output files in <a href="http://github.com/theory/kv-pair/tree/master/test/expected/"><code>test/expected</code></a>. And finally, the <code>DOCS</code> variable finds all the files ending in <code>.md</code> in the <a href="http://github.com/theory/kv-pair/tree/master/doc/"><code>doc</code> directory</a>.</p>

<p>The <code>MODULES</code> variable finds <code>.c</code> files in the <code>src</code> directory. The <code>pair</code> data type has no C code, but the line is harmless here and will just start to work if C support is added later.</p>

<p>Next we have the <code>PG_CONFIG</code> variable. This points to the <a href="http://www.postgresql.org/docs/9.0/static/app-pgconfig.html"><code>pg_config</code></a> utility, which is required to find <code>PGXS</code> and build the extension. If a user has it in her path, it will just work. Otherwise, she can point to an alternate one when building:</p>

<pre><code>make PG_CONFIG=/path/to/pg_config
</code></pre>

<p>The <code>Makefile</code> next uses <code>pg_config</code> to determine whether the extension is being built against PostgreSQL 9.1 or higher. Based on what it finds, extra steps are taken in the following section. That is, if this line returns true:</p>

<pre><code>ifeq ($(PG91),yes)
</code></pre>

<p>Then we&rsquo;re building against 9.1 or higher. In that case, the extension SQL file gets copied to <code>$EXTENSION--$EXTVERSION.sql</code> and added to <code>EXTRA_CLEAN</code> so that <code>make clean</code> will delete it. The <code>DATA</code> variable, meanwhile, is changed to hold only SQL file names that contain <code>--</code>, because such is the required file naming convention for PostgreSQL 9.1 extensions.</p>

<p>The last two lines of the <code>Mafefile</code> do the actual building by including the <code>PGXS</code> <code>Makefile</code> distributed with PostgreSQL. <code>PGXS</code> knows all about building and installing extensions, based on the variables we&rsquo;ve set, and including it makes it do just that.</p>

<p>So now, building and installing the extension should be as simple as:</p>

<pre><code>make
make install
make installcheck PGDATABASE=postgres
</code></pre>

<p>For more on PostgreSQL extension building support, please consult <a href="http://www.postgresql.org/docs/9/static/xfunc-c.html#XFUNC-C-PGXS">the documentation</a>.</p>

<h3>What&rsquo;s up, Doc?</h3>

<p>To further raise the visibility and utility of your extension for users, you&rsquo;re encouraged to include a few other files, as well:</p>

<ul>
<li>A <code>README</code> is a great way to introduce the basics of your extension, to give folks a chance to determine its purpose. Installation instructions are also common here. Plus, it makes a a nice addition to the distribution page on PGXN (<a href="http://pgxn.org/dist/explanation/">example</a>). To get the most benefit, mark it up and save it with a suffix recognized by <a href="http://search.cpan.org/perldoc?Text::Markup">Text::Markup</a> and get nice HTML formatting on the site.</li>
<li>A <code>Changes</code> file (<a href="http://api.pgxn.org/src/explanation/explanation-0.3.0/Changes">example</a>). This file will make it easier for users to determine if they need to upgrade when a new version comes out.</li>
<li><code>LICENSE</code>, <code>INSTALL</code>, <code>COPYING</code>, and <code>AUTHORS</code> are likewise also linked from the distribution page.</li>
</ul>


<p>But perhaps the most important files to consider adding to your distribution are documentation files. Like the <code>README</code>, the API server will parse and index any file recognized by <a href="http://search.cpan.org/perldoc?Text::Markup">Text::Markup</a>. The main PGXN search index contains documentation files, so it&rsquo;s important to have great documentation. Files may be anywhere in the distribution, though of course a top-level <code>doc</code> or <code>docs</code> directory is recommended (and recognized by the <code>Makefile</code> example above).</p>

<p>To give you a feel for how important documentation is to the exposure of your PGXN distribution, try <a href="http://pgxn.org/search?q=sha&amp;in=docs">searching for &ldquo;sha&rdquo;</a>. As of this writing, there are no results, despite the fact that there is, in fact, a <a href="http://pgxn.org/dist/sha/1.0.0/">sha distribution</a>. Note also that the <a href="http://pgxn.org/dist/sha/1.0.0/">distribution page</a> lists &ldquo;sha&rdquo; as an extension, but unlike <a href="http://pgxn.org/dist/tinyint/">other</a> <a href="http://pgxn.org/dist/semver/">distribution</a> <a href="http://pgxn.org/dist/pair/">pages</a>, it does not link to documentation.</p>

<p>Even if you don&rsquo;t map a documentation file to an extension, adding documentation files can be great for your search mojo. See <a href="http://pgxn.org/dist/pgmp/">pgmp</a>, for example, which as of this writing does not link the extension to a documentation file, but a whole series of other documentation files are linked (and indexed).</p>

<p>To sum up, for maximum PGXN coverage, the only rules for documentation files are:</p>

<ul>
<li>They must be written in UTF-8 or specify their encodings via a <a href="http://en.wikipedia.org/wiki/Byte_order_mark">BOM</a> or markup-specific tag (such as the <code>=encoding</code> Pod tag).</li>
<li>They must be recognized by <a href="http://search.cpan.org/perldoc?Text::Markup">Text::Markup</a>.</li>
</ul>


<h3>Zip Me Up</h3>

<p>Once you&rsquo;ve got your extension developed and well-tested, and your distribution just right &mdash; with the <code>META.json</code> file all proof-read and solid a nice <code>README</code> and comprehensive docs &mdash; it&rsquo;s time to wake up, and release it! What you want to do is to zip it up to create a distribution archive. Here&rsquo;s how the <code>pair</code> distribution &mdash; which is maintained in Git &mdash; was prepared:</p>

<pre><code>git archive --format zip --prefix=pair-0.1.2/ \
--output ~/Desktop/pair-0.1.2.zip master
</code></pre>

<p>Then the <code>pair-0.1.0.zip</code> file was ready to release. Simple, eh?</p>

<p>Now, one can upload any kind of archive file to PGXN, including a tarball, or bzip2…um…ball? Basically, any kind of archive format recognized by <a href="http://search.cpan.org/perldoc?Archive::Extract">Archive::Extract</a>. A zip file is best because then PGXN::Manager won&rsquo;t have to rewrite it. It&rsquo;s also preferable that everything be packed into a directory with the name <code>$distribution-$version</code>, as in the <code>pair-0.1.2</code> example above. If not, PGXN will rewrite it that way. But it saves the server some effort if all it has to do is move a <code>.zip</code> file that&rsquo;s properly formatted, so it would be appreciated if you would upload stuff that&rsquo;s already nicely formatted for distribution in a zip archive.</p>

<h3>Release It!</h3>

<p>And that&rsquo;s it! Not too bad, eh? Just please do be very careful cutting and pasting examples. Or better yet, give <a href="https://github.com/guedes/pgxn-utils/">pgxn-utils</a> a try. It will create a skeleton distribution for you and make it easy to add new stuff as you develop. It also puts all the files in the recommended places.</p>

<p>Good hacking!</p>}

);

sub accept {
    shift->get_handle( I18N::LangTags::Detect->http_accept_langs(shift) );
}

sub list {
    my ($lh, $items) = @_;
    return unless @{ $items };
    return $items->[0] if @{ $items } == 1;
    my $last = pop @{ $items };
    my $comma = $lh->maketext('listcomma');
    my $ret = join  "$comma ", @$items;
    $ret .= $comma if @{ $items } > 1;
    my $and = $lh->maketext('listand');
    return "$ret $and $last";
}

sub qlist {
    my ($lh, $items) = @_;
    return unless @{ $items };
    my $open = $lh->maketext('openquote');
    my $shut = $lh->maketext('shutquote');
    return $open . $items->[0] . $shut if @{ $items } == 1;
    my $last = pop @{ $items };
    my $comma = $lh->maketext('listcomma');
    my $ret = $open . join("$shut$comma $open", @$items) . $shut;
    $ret .= $comma if @{ $items } > 1;
    my $and = $lh->maketext('listand');
    return "$ret $and $open$last$shut";
}

1;

=head1 Name

PGXN::Manager::Locale - Localization for PGXN::Manager

=head1 Synopsis

  use PGXN::Manager::Locale;
  my $mt = PGXN::Manager::Locale->accept($env->{HTTP_ACCEPT_LANGUAGE});

=head1 Description

This class provides localization support for PGXN::Manager. Each locale must
create a subclass named for the locale and put its translations in the
C<%Lexicon> hash. It is further designed to support easy creation of
a handle from an HTTP_ACCEPT_LANGUAGE header.

=head1 Interface

The interface inherits from L<Locale::Maketext> and adds the following
method.

=head2 Constructor Methods

=head3 C<accept>

  my $mt = PGXN::Manager::Locale->accept($env->{HTTP_ACCEPT_LANGUAGE});

Returns a PGXN::Manager::Locale handle appropriate for the specified
argument, which must take the form of the HTTP_ACCEPT_LANGUAGE string
typically created in web server environments and specified in L<RFC
3282|http://tools.ietf.org/html/rfc3282>. The parsing of this header is
handled by L<I18N::LangTags::Detect>.

=head2 Instance Methods

=head3 C<list>

  # "Missing these keys: foo, bar, and baz"
  say $mt->maketext(
      'Missing these keys: [list,_1])'
      [qw(foo bar baz)],
  );

Formats a list of items. The list of items to be formatted should be passed as
an array reference. If there is only one item, it will be returned. If there
are two, they will be joined with " and ". If there are more, there will be a
comma-separated list with the final item joined on ", and ".

Note that locales can control the localization of the comma and "and" via the
C<listcomma> and C<listand> entries in their C<%Lexicon>s.

=head3 C<qlist>

  # "Missing these keys: “foo”, “bar”, and “baz”
  say $mt->maketext(
      'Missing these keys: [qlist,_1]'
      [qw(foo bar baz)],
  );

Like C<list()> but quotes each item in the list. Locales can specify the
quotation characters to be used via the C<openquote> and C<shutquote> entries
in their C<%Lexicon>s.

head1 Author

David E. Wheeler <david.wheeler@pgexperts.com>

=head1 Copyright and License

Copyright (c) 2010-2011 David E. Wheeler.

This module is free software; you can redistribute it and/or modify it under
the L<PostgreSQL License|http://www.opensource.org/licenses/postgresql>.

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

=cut
