package PGXN::Manager::Locale;

use 5.12.0;
use utf8;
use parent 'Locale::Maketext';
use I18N::LangTags::Detect;

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
    howto_page_title => 'How to create PostgreSQL extensions and distribute them on PGXN',
    howto_body => q{<p>PGXN is the PostgreSQL Extension Network. If you&#8217;re a PostgreSQL developer, you&#8217;ve no doubt created customizations to make your life simpler. This is possible because PostgreSQL today is not merely a database, it’s an application development platform. If you&#8217;d like to distribute such customizations in open-source releases for your fellow PostgreSQL enthusiasts to enjoy, PGXN is the place to do it.</p>

<p>This document explains how. There&#8217;s some background information, too, but the goal is to provide the information and references you need to get started packaging your extensions and distributing them on PGXN. If anything is unclear, please do <a href="/contact">let us know</a>. It&#8217;s our aim to make this the one stop for all of your PGXN distribution needs.</p>

<h3>OMG Distribution WTF?</h3>

<p>First of all, what is a &#8220;distribution&#8221; in the PGXN sense? Basically, it&#8217;s a collection of one or more <a href="http://www.postgresql.org/">PostgreSQL</a> extensions. That&#8217;s it.</p>

<p>Oh, so now you want to know what an &#8220;extension&#8221; is? Naturally. Well, as of this writing it&#8217;s somewhat in flux. Traditionally, a PostgreSQL extension has been any code that can be built by <a href="http://www.postgresql.org/docs/current/static/xfunc-c.html#XFUNC-C-PGXS">PGXS</a> and installed into the database. The PostgreSQL <a href="http://www.postgresql.org/docs/current/static/contrib.html">contributed modules</a> provide excellent examples.</p>

<p>There is ongoing work to integrate the idea of extensions more deeply into the PostgreSQL core in 9.1. Dimitri Fontaine has <a href="http://blog.tapoueh.org/blog.dim.html#%20Introducing%20Extensions">the details</a>. However, the build infrastructure is the same. From your point of view as a PostgreSQL extension developer, you&#8217;re still going to use <a href="http://www.postgresql.org/docs/current/static/xfunc-c.html#XFUNC-C-PGXS">PGXS</a> to configure and build your extension, and can distribute it via PGXN.</p>

<h3>That&#8217;s So Meta</h3>

<p>At its simplest, the only thing PGXN requires of a distribution is a single file, <code>META.json</code>, which describes the package. This is (currently) the only file that PGXN Manager uses to index a distribution, so it&#8217;s important to get it right. The <a href="http://github.com/theory/pgxn/wiki/PGXN-Meta-Spec">PGXN Meta Spec</a> has a rather complete example of a hypothetical pgTAP <code>META.json</code>. </p>

<p>If you have only one .sql file for your extension and it&#8217;s the same name as the distribution (which is commonly the case), then you can make it pretty simple. For example, the <a href="http://master.pgxn.org/dist/pair/"><code>pair</code></a> distribution has only one SQL file. So the <code>META.json</code> could be:</p>

<pre><code>{
   "name": "pair",
   "abstract": "A key/value pair data type",
   "version": "0.1.0",
   "maintainer": "David E. Wheeler &lt;david@justatheory.com&gt;",
   "license": "postgresql",
   "meta-spec": {
      "version": "1.0.0",
      "url": "http://github.com/theory/pgxn/wiki/PGXN-Meta-Spec"
   },
}
</code></pre>

<p>That&#8217;s it. The only thing that may not be obvious from this example is that all version numbers in a <code>META.json</code> <em>must</em> be <a href="http://semver.org/">semantic versions</a>, including for core dependencies like plperl or PostgreSQL itself. If they&#8217;re not, PGXN will make them so. So &#8220;1.2&#8221; would become &#8220;1.2.0&#8221; &#8212; and so would &#8220;1.02&#8221;. So do try to use semantic version strings and don&#8217;t worry about it.</p>

<p>In the short run, you won&#8217;t need anything more in your <code>META.json</code> file. But once the proposed <a href="http://wiki.postgresql.org/wiki/PGXN#Search_Site">search site</a> and <a href="http://wiki.postgresql.org/wiki/PGXN#PGXN_Client">command-line client</a> have been implemented, you&#8217;re probably going to want to do more. Other useful keys to include are:</p>

<ul>
<li><a href="http://github.com/theory/pgxn/wiki/PGXN-Meta-Spec#tags"><code>tags</code></a>: An array of tags to associate with a distribution. Will help with searching.</li>
<li><a href="http://github.com/theory/pgxn/wiki/PGXN-Meta-Spec#prereqs"><code>prereqs</code></a>: A list of prerequisite extensions or PostgreSQL contrib modules (or PostgreSQL itself).</li>
<li><a href="http://github.com/theory/pgxn/wiki/PGXN-Meta-Spec#provides"><code>provides</code></a>: A list of included extensions. Useful if you have more than one in a single distribution. It also will assign ownership of the specified extension names to you &#8212; if they haven&#8217;t been claimed by any previous distribution.</li>
<li><a href="http://github.com/theory/pgxn/wiki/PGXN-Meta-Spec#release_status"><code>release_status</code></a>: To label a distribution as &#8220;stable,&#8221; &#8220;unstable,&#8221; or &#8220;testing.&#8221; The latter two are useful for distributing extensions for testing but that should not be installed by automated clients.</li>
<li><a href="http://github.com/theory/pgxn/wiki/PGXN-Meta-Spec#resources"><code>resources</code></a>: A list of related links, such as to an SCM repository or bug tracker. The search site will output these links.</li>
</ul>

<p>Have a look at the <a href="http://github.com/theory/kv-pair/blob/master/META.json"><code>pair</code> <code>META.json</code> file</a> for an extended example.</p>

<h3>New Order</h3>

<p>PGXN doesn&#8217;t really care how distributions are structured, or if they use <a href="http://www.postgresql.org/docs/current/static/xfunc-c.html#XFUNC-C-PGXS">PGXS</a>. That said, the proposed <a href="http://wiki.postgresql.org/wiki/PGXN#PGXN_Client">download and installation client</a> will assume the use of PGXS (unless and until the PostgreSQL core adds some other kind of extension-building support), so it&#8217;s probably the best choice.</p>

<p>Most PGXS-powered distributions have the code files in the main directory, with documentation in a <code>README.extension_name</code> file. What we&#8217;d like to see instead, and will encourage via the forthcoming <a href="http://wiki.postgresql.org/wiki/PGXN#Search_Site">search site</a>, is that things be organized into subdirectories:</p>

<ul>
<li><code>src</code> for any C source code files</li>
<li><code>sql</code> for SQL source files. These usually are responsible for installing an extension into a database</li>
<li><code>doc</code> for documentation files (the search site will likely look there for Markdown, Textile, HTML, and other document formats)</li>
<li><code>test</code> for tests</li>
</ul>

<p>The <code>pair</code> distribution serves as an <a href="http://github.com/theory/kv-pair/blob/">example of this</a>. To make it all work, the <a href="http://github.com/theory/kv-pair/blob/master/Makefile">Makefile</a> is written like so:</p>

<pre><code>DATA = sql/pair.sql sql/uninstall_pair.sql
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
</code></pre>

<p>The <code>DATA</code> variable identifies the SQL files containing the extension, while <code>TESTS</code> loads a list test files, which are in the <code>test/sql</code> directory. Note that the <code>pair</code> distribution uses <code>pg_regress</code> for tests, and <code>pg_reqress</code> expects that test files will have corresponding &#8220;expected&#8221; files to compare against. With the <code>REGRESS_OPTS = --inputdir=test</code> line, The distribution tells <code>pg_regess</code> to find the test files in <a href="http://github.com/theory/kv-pair/tree/master/test/sql/"><code>test/sql</code></a> and the expected output files in <a href="http://github.com/theory/kv-pair/tree/master/test/expected/"><code>test/expected</code></a>. And finally, the <code>DOCS</code> variable points to a single file with the documentation, <a href="http://github.com/theory/kv-pair/blob/master/doc/pair.txt"><code>doc/pair.txt</code></a>. If this extension had required any C code (like <a href="http://pgtap.org/">pgTAP</a> or <a href="http://postgis.org/">PostGIS</a> do), The <code>Makefile</code> would have pointed the <code>MODULES</code> variable at files in a <code>src</code> directory.</p>

<p>The remainder of the <code>Mafefile</code> consists of build instructions. If executed with <code>make NO_PGXS=1</code>, it assumes that the distribution directory has been put in the &#8220;contrib&#8221; directory of the PostgreSQL source tree used to build PostgreSQL. That&#8217;s probably only important if one is installing on PostgreSQL 8.1 or lower. Otherwise, it assumes a plain <code>make</code> and uses the <a href="http://www.postgresql.org/docs/current/static/app-pgconfig.html"><code>pg_config</code></a> in the system path to find <code>pg_config</code> to do the build. And even with that, a sys admin can always point directly to it by executing <code>PG_CONFIG=/path/to/pg_config make</code>.</p>

<p>Either way, building and installing the extension should be as simple as:</p>

<pre><code>make
make install
make installcheck PGDATABASE=postgres
</code></pre>

<p>For more on PostgreSQL extension building support, please consult <a href="http://www.postgresql.org/docs/9/static/xfunc-c.html#XFUNC-C-PGXS">the documentation</a>.</p>

<h3>Zip Me Up</h3>

<p>Once you&#8217;ve got your extension developed and well-tested, and your distribution just right and the <code>META.json</code> file all proof-read and solid, it&#8217;s time to upload the distribution to PGXN. What you want to do is to zip it up to create a distribution archive. Here&#8217;s what how the <code>pair</code> distribution &#8212; which is maintained in Git &#8212; was prepared:</p>

<pre><code>git checkout-index -af --prefix ~/Desktop/pair-0.1.0/
cd ~/Desktop/
rm pair-0.1.0/.gitignore
zip -r pair-0.1.0.zip pair-0.1.0
</code></pre>

<p>Then the <code>pair-0.1.0.zip</code> file was ready to upload. Simple, eh?</p>

<p>Now, one can upload any kind of archive file to PGXN, including a tarball, or bzip2…um…ball? Basically, any kind of archive format recognized by <a href="http://search.cpan.org/perldoc?Archive::Extract">Archive::Extract</a>. You can upload a <code>.pgz</code> if you like, in which case PGXN will assume that it&#8217;s a zip file. A zip file is best because then PGXN::Manager won&#8217;t have to rewrite it. It&#8217;s also preferable that everything be packed into a directory with the name <code>$distribution-$version</code>, as in the example <code>pair-0.1.0</code> example above. If not, PGXN will rewrite it that way. But it saves the server some effort if all it has to do is move a .zip file that&#8217;s properly formatted, so it would be appreciated if you would upload stuff that&#8217;s already nicely formatted for distribution in a zip archive.</p>

<h3>Release It!</h3>

<p>And that&#8217;s it! Not too bad, eh? Just please do be very careful cutting and pasting examples. Hopefully we&#8217;ll be able to build things up to the point where a lot of this stuff can be automated (especially the creation of the <code>META.json</code>), but for now it&#8217;s done by hand. So be careful out there, and good luck!</p>},
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
      'Missing these keys: [qlist,_1])'
      [qw(foo bar baz)],
  );

Like C<list()> but quotes each item in the list. Locales can specify the
quotation characters to be used via the C<openquote> and C<shutquote> entries
in their C<%Lexicon>s.

head1 Author

David E. Wheeler <david.wheeler@pgexperts.com>

=head1 Copyright and License

Copyright (c) 2010 David E. Wheeler.

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
