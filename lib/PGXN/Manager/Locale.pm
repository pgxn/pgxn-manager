package PGXN::Manager::Locale;

use 5.10.0;
use utf8;
use parent 'Locale::Maketext';
use I18N::LangTags::Detect;

our $VERSION = v0.31.2;

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
    'Approve account for "[_1]"' => 'Approve account for “[_1]“',
    'Reject account for "[_1]"' => 'Approve account for “[_1]“',
    # multimarkdown doc/howto.md | perl -pe 's/([\[\]])/~$1/g'
    howto_body => q`<p>PGXN is the PostgreSQL Extension Network. If you&#8217;re a PostgreSQL developer,
you&#8217;ve no doubt created customizations to make your life simpler. This is
possible because PostgreSQL today is not merely a database, it’s an application
development platform. If you&#8217;d like to distribute such customizations in
open-source releases for your fellow PostgreSQL enthusiasts to enjoy, PGXN is
the place to do it.</p>

<p>This document explains how. There&#8217;s some background information, too, but the
goal is to provide the information and references you need to get started
packaging your extensions and distributing them on PGXN. If anything is unclear,
please do <a href="https://manager.pgxn.org/contact" title="Contact PGXN">let us know</a>. It&#8217;s our aim to make this the one stop for all of your
PGXN distribution needs.</p>

<h3>Contents</h3>

<div class="TOC">

<ul>
<li><a href="#omgdistributionwtf">OMG Distribution WTF?</a></li>
<li><a href="#thatssometa">That&#8217;s So Meta</a></li>
<li><a href="#wehaveassumedcontrol">We Have Assumed Control</a></li>
<li><a href="#neworder">New Order</a></li>
<li><a href="#whatsupdoc">What&#8217;s up, Doc?</a></li>
<li><a href="#zipmeup">Zip Me Up</a></li>
<li><a href="#releaseit">Release It!</a></li>
</ul>
</div>

<h3 id="omgdistributionwtf">OMG Distribution WTF?</h3>

<p>First of all, what is a &#8220;distribution&#8221; in the PGXN sense? Basically, it&#8217;s a
collection of one or more <a href="https://www.postgresql.org/">PostgreSQL</a> extensions. That&#8217;s it. The PostgreSQL
<a href="https://www.postgresql.org/docs/current/static/contrib.html">additional supplied modules</a> provide excellent examples. On PGXN some examples
are:</p>

<ul>
<li><a href="https://pgxn.org/dist/pair/">pair</a>: a pure SQL data type</li>
<li><a href="https://pgxn.org/dist/semver/">semver</a>: a data type implemented in C</li>
<li><a href="https://pgxn.org/dist/italian_fts/">italian_fts</a>: An italian full-text search dictionary</li>
</ul>

<p>Traditionally, a PostgreSQL extension was any code that could be built by <a href="https://www.postgresql.org/docs/current/static/extend-pgxs.html" title="PostgreSQL Documentation: “Extension Building Infrastructure”">PGXS</a>
and installed into the database. PostgreSQL 9.1 integrated extensions more
deeply into the core. With just a bit more work, users who have installed an
extension will be able to load it into the database with a simple command:</p>

<pre><code>CREATE EXTENSION pair;
</code></pre>

<p>The documentation <a href="https://www.postgresql.org/docs/current/static/extend-extensions.html" title="PostgreSQL Documentation: “Packaging Related Objects into an Extension”">has the details</a>. As a PostgreSQL extension
developer, use <a href="https://www.postgresql.org/docs/current/static/extend-pgxs.html" title="PostgreSQL Documentation: “Extension Building Infrastructure”">PGXS</a> to configure and build your extension.</p>

<p>All this is not to say that PGXN extensions must be PostgreSQL extensions,
except in the sense that they should add something to PostgreSQL. For example,
you might want to distribute a command-line utility like <a href="https://pgxn.org/dist/pg_top/">pg_top</a>. That&#8217;s cool.
Just be creative and make PostgreSQL better and you&#8217;ll be on the right track.</p>

<h3 id="thatssometa">That&#8217;s So Meta</h3>

<p>At its simplest, the only thing PGXN requires of a distribution is a single
file, <code>META.json</code>, which describes the package. PGXN Manager uses this file to
index a distribution, so it&#8217;s important to get it right. The <a href="https://pgxn.org/spec/">PGXN Meta Spec</a>
has all the details on what&#8217;s required, but what follows is a pragmatic
overview.</p>

<p>If you have only one <code>.sql</code> file for your extension and it&#8217;s the same name as
the distribution, then you can make it pretty simple. For example, the <a href="https://pgxn.org/dist/pair/">pair</a>
distribution has only one SQL file. So the <code>META.json</code> could be:</p>

<pre><code class="json">{
   &quot;name&quot;: &quot;pair&quot;,
   &quot;abstract&quot;: &quot;A key/value pair data type&quot;,
   &quot;version&quot;: &quot;0.1.0&quot;,
   &quot;maintainer&quot;: &quot;David E. Wheeler &lt;david@justatheory.com&gt;&quot;,
   &quot;license&quot;: &quot;postgresql&quot;,
   &quot;provides&quot;: {
      &quot;pair&quot;: {
         &quot;abstract&quot;: &quot;A key/value pair data type&quot;,
         &quot;file&quot;: &quot;sql/pair.sql&quot;,
         &quot;docfile&quot;: &quot;doc/pair.md&quot;,
         &quot;version&quot;: &quot;0.1.0&quot;
      }
   },
   &quot;meta-spec&quot;: {
      &quot;version&quot;: &quot;1.0.0&quot;,
      &quot;url&quot;: &quot;https://pgxn.org/meta/spec.txt&quot;
   }
}
</code></pre>

<p>That&#8217;s it. Note that all version numbers in a <code>META.json</code> <em>must</em> be <a href="https://pgxn.org/dist/semver/">semantic
versions</a>, including for core dependencies like <a href="https://www.postgresql.org/docs/current/plperl.html">PL/Perl</a> or PostgreSQL
itself. If they&#8217;re not, PGXN cannot index your distribution. If you don&#8217;t want
to read through the <a href="https://pgxn.org/dist/semver/">Semantic Versioning 2.0.0 spec</a>, just use thee-part
dotted integers (such as &#8220;1.2.0&#8221;) and don&#8217;t worry about it.</p>

<p>One thing that might be confusing here is the redundant information in the
<code>provides</code> section. While the <code>name</code>, <code>abstract</code>, and <code>version</code> keys at the top
level of the JSON describe the distribution itself, the <code>provides</code> section
contains a list of all the extensions provided by the distribution. There is
only one extension in this distribution, hence the duplication. But in some
cases, such as <a href="https://pgxn.org/dist/pgtap/">pgTAP</a>, there will be multiple extensions, each with its own
information. PGXN also uses this information to assign ownership of the
specified extension names to you &#8211; if they haven&#8217;t been claimed by any previous
distribution.</p>

<p>To really take advantage of PGXN, you&#8217;ll want your extension to show up
prominently in search results. Adding other keys to your <code>META.json</code> file will
help. Other useful keys to include are:</p>

<ul>
<li><a href="https://pgxn.org/spec/#tags"><code>tags</code></a>: An array of tags to associate with a distribution. Will help with
searching.</li>
<li><a href="https://pgxn.org/spec/#prereqs"><code>prereqs</code></a>: A list of prerequisite extensions or PostgreSQL contrib modules
(or PostgreSQL itself).</li>
<li><a href="https://pgxn.org/spec/#release_status"><code>release_status</code></a>: To label a distribution as &#8220;stable,&#8221; &#8220;unstable,&#8221; or
&#8220;testing.&#8221; The latter two are useful for distributing extensions for testing
but that should not typically be installed by automated clients or visible
in the full-text search provided by the API server.</li>
<li><a href="https://pgxn.org/spec/#resources"><code>resources</code></a>: A list of related links, such as to an SCM repository or bug
tracker. The search site displays these links on the home page for the
distribution.</li>
</ul>

<p>So here&#8217;s a more extended example from the <code>pair</code> data type:</p>

<pre><code class="json">{
   &quot;name&quot;: &quot;pair&quot;,
   &quot;abstract&quot;: &quot;A key/value pair data type&quot;,
   &quot;description&quot;: &quot;This library contains a single PostgreSQL extension, a key/value pair data type called “pair”, along with a convenience function for constructing key/value pairs.&quot;,
   &quot;version&quot;: &quot;0.1.4&quot;,
   &quot;maintainer&quot;: ~[
      &quot;David E. Wheeler &lt;david@justatheory.com&gt;&quot;
   ~],
   &quot;license&quot;: &quot;postgresql&quot;,
   &quot;provides&quot;: {
      &quot;pair&quot;: {
         &quot;abstract&quot;: &quot;A key/value pair data type&quot;,
         &quot;file&quot;: &quot;sql/pair.sql&quot;,
         &quot;docfile&quot;: &quot;doc/pair.md&quot;,
         &quot;version&quot;: &quot;0.1.0&quot;
      }
   },
   &quot;resources&quot;: {
      &quot;bugtracker&quot;: {
         &quot;web&quot;: &quot;https://github.com/theory/kv-pair/issues/&quot;
      },
      &quot;repository&quot;: {
      &quot;url&quot;:  &quot;git://github.com/theory/kv-pair.git&quot;,
      &quot;web&quot;:  &quot;https://github.com/theory/kv-pair/&quot;,
      &quot;type&quot;: &quot;git&quot;
      }
   },
   &quot;generated_by&quot;: &quot;David E. Wheeler&quot;,
   &quot;meta-spec&quot;: {
      &quot;version&quot;: &quot;1.0.0&quot;,
      &quot;url&quot;: &quot;https://pgxn.org/meta/spec.txt&quot;
   },
   &quot;tags&quot;: ~[
      &quot;variadic function&quot;,
      &quot;ordered pair&quot;,
      &quot;pair&quot;,
      &quot;key value&quot;,
      &quot;key value pair&quot;,
      &quot;data type&quot;
   ~]
}
</code></pre>

<p>PGXN Manager will verify the <code>META.json</code> file and complain if it&#8217;s not right.
You can also check it before uploading by installing <a href="https://metacpan.org/release/PGXN-Meta-Validator">PGXN::Meta::Validator</a> and
running:</p>

<pre><code>validate_pgxn_meta META.json
</code></pre>

<p>Or, if you also have the <a href="https://github.com/dvarrazzo/pgxnclient/">pgxn client</a> installed, it&#8217;s just</p>

<pre><code>pgxn validate-meta
</code></pre>

<p>Thanks to all that metadata, the extension gets a <a href="https://pgxn.org/dist/pair/">very nice page</a> on
PGXN. Note especially the <code>docfile</code> key in the <code>provides</code> section. This is the
best way to tell PGXN where to find documentation to index. More on that below.</p>

<h3 id="wehaveassumedcontrol">We Have Assumed Control</h3>

<p>A second file you need to provide for PostgreSQL <a href="https://www.postgresql.org/docs/current/static/extend-extensions.html" title="PostgreSQL Documentation: “Packaging Related Objects into an Extension”">extensions</a>, is the &#8220;control
file&#8221;. This file enables <code>CREATE EXTENSION</code>. Like <code>META.json</code> it describes your
extension, but it&#8217;s much shorter. Really all it needs is a few keys. Here&#8217;s an
example from the <a href="https://pgxn.org/dist/semver/">semver distribution</a> named <code>semver.control</code>:</p>

<pre><code class="ini"># semver extension
comment = 'A semantic version data type'
default_version = '0.2.1'
module_pathname = '$libdir/semver'
relocatable = true
</code></pre>

<p>The <code>default_version</code> value specifies the version of the extension you&#8217;re
distributing, the <code>module_pathname</code> value may be required for C extensions, and
the <code>relocatable</code> value determines whether an extension can be moved from one
schema to another. These are the keys you will most often use, but there are
quite a few <a href="https://www.postgresql.org/docs/current/static/extend-extensions.html" title="PostgreSQL Documentation: “Packaging Related Objects into an Extension”">other keys</a> you might want to review as you develop
your extension.</p>

<h3 id="neworder">New Order</h3>

<p>PGXN doesn&#8217;t really care how distributions are structured, or if they use
<a href="https://www.postgresql.org/docs/current/static/extend-pgxs.html" title="PostgreSQL Documentation: “Extension Building Infrastructure”">PGXS</a>. That said, the <a href="https://github.com/dvarrazzo/pgxnclient/">pgxn client</a> currently supports only <code>./configure</code> and
<code>make</code>, so PGXS is probably the best choice.</p>

<p>We strongly encourage that the files in distributions be organized into
subdirectories:</p>

<ul>
<li><code>src</code> for any C source code files</li>
<li><code>sql</code> for SQL source files</li>
<li><code>doc</code> for documentation files</li>
<li><code>test</code> for tests</li>
</ul>

<p>The <a href="https://pgxn.org/dist/pair/">pair</a> and <a href="https://pgxn.org/dist/semver/">semver</a> distributions serve as examples of this. To make it all
work, their <code>Makefile</code>s are written like so:</p>

<pre><code class="makefile">EXTENSION    = $(shell grep -m 1 '&quot;name&quot;:' META.json | \
               sed -e 's/~[~[:space:~]~]*&quot;name&quot;:~[~[:space:~]~]*&quot;\(~[^&quot;~]*\)&quot;,/\1/')
EXTVERSION   = $(shell grep -m 1 '~[~[:space:~]~]\{8\}&quot;version&quot;:' META.json | \
               sed -e 's/~[~[:space:~]~]*&quot;version&quot;:~[~[:space:~]~]*&quot;\(~[^&quot;~]*\)&quot;,\{0,1\}/\1/')
DISTVERSION  = $(shell grep -m 1 '~[~[:space:~]~]\{3\}&quot;version&quot;:' META.json | \
               sed -e 's/~[~[:space:~]~]*&quot;version&quot;:~[~[:space:~]~]*&quot;\(~[^&quot;~]*\)&quot;,\{0,1\}/\1/')

DATA 		    = $(wildcard sql/*--*.sql)
TESTS        = $(wildcard test/sql/*.sql)
DOCS         = $(wildcard doc/*.md)
REGRESS      = $(patsubst test/sql/%.sql,%,$(TESTS))
REGRESS_OPTS = --inputdir=test
# MODULES    = $(patsubst %.c,%,$(wildcard src/*.c))
PG_CONFIG   ?= pg_config
PG91         = $(shell $(PG_CONFIG) --version | grep -qE &quot; 8\.| 9\.0&quot; &amp;&amp; echo no || echo yes)
EXTRA_CLEAN = sql/$(EXTENSION)--$(EXTVERSION).sql

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

all: sql/$(EXTENSION)--$(EXTVERSION).sql

sql/$(EXTENSION)--$(EXTVERSION).sql: sql/$(EXTENSION).sql
	cp $&lt; $@

dist:
	git archive --format zip --prefix=$(EXTENSION)-$(DISTVERSION)/ -o $(EXTENSION)-$(DISTVERSION).zip HEAD
</code></pre>

<p>The <code>EXTENSION</code> variable is read in from <code>META.json</code> to identify the extension
you&#8217;re distributing. <code>EXTVERSION</code>, also read from <code>META.json</code>, identifies the
extension version (that is, the one from the <code>provides</code> section), so you only
have to edit it there (and in the control file). Same for <code>DISTVERSION</code>, which
is handy for building a release (more on that shortly).</p>

<p>The <code>DATA</code> variable identifies the SQL files containing the extension or
extensions, while <code>TESTS</code> loads a list test files, which are in the <code>test/sql</code>
directory. The <code>DOCS</code> variable finds all the files ending in <code>.md</code> in the <a href="https://github.com/theory/kv-pair/tree/main/doc/"><code>doc</code>
directory</a>. For distributions testing with <code>pg_regress</code>, it expects that test
files will have corresponding &#8220;expected&#8221; files to compare against. Thanks to the
<code>REGRESS_OPTS = --inputdir=test</code> line, <code>pg_regress</code> will find the test files in
<a href="https://github.com/theory/kv-pair/tree/main/test/sql/"><code>test/sql</code></a> and the expected output files in <a href="https://github.com/theory/kv-pair/tree/main/test/expected/"><code>test/expected</code></a>.</p>

<p>The <code>MODULES</code> variable finds <code>.c</code> files in the <code>src</code> directory. The <code>pair</code> data
type has no C code, so it&#8217;s commented-out. You&#8217;ll want to uncomment it if you
have C code or add C code later.</p>

<p>Next we have the <code>PG_CONFIG</code> variable. This points to the <a href="https://www.postgresql.org/docs/current/static/app-pgconfig.html"><code>pg_config</code></a> utility,
which is required to find PGXS and build the extension. If a user has it in
their path, it will just work. Otherwise, they can point to an alternate one
when building:</p>

<pre><code>make PG_CONFIG=/path/to/pg_config
</code></pre>

<p>Thanks to the <code>?=</code> operator, it can also be set as an environment variable,
which is useful for executing multiple <code>make</code> commands in a one-liner:</p>

<pre><code>env PG_CONFIG=/path/to/pg_config make &amp;&amp; make install &amp;&amp; make installcheck
</code></pre>

<p>The next two lines of the <code>Makefile</code> do the actual building by including the
<code>PGXS</code> <code>Makefile</code> distributed with PostgreSQL. PGXS knows all about building and
installing extensions, based on the variables we&#8217;ve set, and including it makes
it do just that.</p>

<p>Once the PGXS <code>Makefile</code> is loaded, we are free to define other targets. We take
advantage of this to add a <code>$EXTENSION--$EXTVERSION.sql</code> target to copy create
the versioned SQL file for <code>CREATE EXTENSION</code> to find.</p>

<p>The last three lines define a <code>dist</code> target described bellow.</p>

<p>So now, building and installing the extension should be as simple as:</p>

<pre><code>make
make install
make installcheck PGDATABASE=postgres
</code></pre>

<p>For more on PostgreSQL extension building support, please consult <a href="https://www.postgresql.org/docs/current/static/extend-pgxs.html" title="PostgreSQL Documentation: “Extension Building Infrastructure”">the
documentation</a>.</p>

<h3 id="whatsupdoc">What&#8217;s up, Doc?</h3>

<p>To further raise the visibility and utility of your extension for users, you&#8217;re
encouraged to include a few other files, as well:</p>

<ul>
<li>A <code>README</code> is a great way to introduce the basics of your extension, to give
folks a chance to determine its purpose. Installation instructions are also
common here. Plus, it makes a a nice addition to the distribution page on
PGXN (<a href="https://pgxn.org/dist/hostname/">example</a>). To get the most benefit, mark it up and save it
with a suffix recognized by <a href="https://metacpan.org/pod/Text::Markup)">Text::Markup</a> and get nice HTML formatting on
the site.</li>
<li>A <code>Changes</code> file (<a href="https://api.pgxn.org/src/hostname/hostname-1.0.2/Changes">example</a>). This file will make it easier for
users to determine if they need to upgrade when a new version comes out.</li>
<li><code>LICENSE</code>, <code>INSTALL</code>, <code>COPYING</code>, and <code>AUTHORS</code> files are also linked from
the distribution page.</li>
</ul>

<p>The most important files to consider adding to your distribution are
documentation files. Like the <code>README</code>, the API server will parse and index any
file recognized by <a href="https://metacpan.org/pod/Text::Markup)">Text::Markup</a>. The main PGXN search index contains
documentation files, so it&#8217;s important to have great documentation. Files may be
anywhere in the distribution, though of course a top-level <code>doc</code> or <code>docs</code>
directory is recommended (and recognized by the <code>Makefile</code> example above).</p>

<p>To give you a feel for how important documentation is to the exposure of your
PGXN distribution, try <a href="https://pgxn.org/search?q=sha&amp;in=docs">searching for &#8220;sha&#8221;</a>. As of this writing, there are five
results, none of which include the <a href="https://pgxn.org/dist/sha/1.1.0/">sha distribution</a>. Note also that the
<a href="https://pgxn.org/dist/sha/1.1.0/">distribution page</a> lists &#8220;sha&#8221; as an extension, but unlike
<a href="https://pgxn.org/dist/tinyint/">other</a> <a href="https://pgxn.org/dist/semver/">distribution</a> <a href="https://pgxn.org/dist/pair/">pages</a>, it does not link to
documentation.</p>

<p>Even if you don&#8217;t map a documentation file to an extension, adding documentation
files can be great for your search mojo. See <a href="https://pgxn.org/dist/pgmp/">pgmp</a>, for example, which as of
this writing does not link the extension to a documentation file, but a whole
series of other documentation files are linked (and indexed).</p>

<p>To sum up, for maximum PGXN coverage, the only rules for documentation files
are:</p>

<ul>
<li>They must be written in UTF-8 or specify their encodings via a <a href="https://en.wikipedia.org/wiki/Byte_order_mark">BOM</a> or
markup-specific tag (such as the <code>=encoding</code> Pod tag).</li>
<li>They must be recognized by <a href="https://metacpan.org/pod/Text::Markup)">Text::Markup</a>.</li>
</ul>

<h3 id="zipmeup">Zip Me Up</h3>

<p>Once you&#8217;ve got your extension developed and well-tested, and your distribution
just right &#8211; with the <code>META.json</code> file all proof-read and solid a nice <code>README</code>
and comprehensive docs &#8211; it&#8217;s time to <em>wake up,</em> and release it! Simply zip it
up to create a distribution archive. If you&#8217;re using Git, you can use the <code>dist</code>
target included in the <code>Makefile</code> template above, like so:</p>

<pre><code>make dist
</code></pre>

<p>The resulting <code>.zip</code> file is ready to release. Simple, eh?</p>

<p>Now, one can upload any kind of archive file to PGXN, including a tarball, or
bzip2…um…ball? Basically, any kind of archive format recognized by
<a href="https://metacpan.org/pod/Archive::Extract">Archive::Extract</a>. A zip file is best because PGXN Manager won&#8217;t have to
rewrite it. It&#8217;s also preferable that everything be packed into a directory with
the name <code>$distribution-$version</code>, as the Git-using <code>make dist</code> target does. If
the files are not packed into <code>$distribution-$version</code>, PGXN will rewrite it
that way. But it saves the server some effort if all it has to do is move a
<code>.zip</code> file that&#8217;s properly formatted.</p>

<h3 id="releaseit">Release It!</h3>

<p>Now <a href="https://manager.pgxn.org/account/register">request an account</a> if you don&#8217;t already have one, hit the &#8220;Upload&#8221; link in
the side navigation, and the release zip file.</p>

<p>And that&#8217;s it! Not too bad, eh? Just please do be very careful cutting and
pasting examples. Or better yet, give <a href="https://github.com/guedes/pgxn-utils/">pgxn-utils</a> a try. It will create a
skeleton distribution for you and make it easy to add new stuff as you develop.
It also puts all the files in the recommended places, and can create and upload
a release directly to PGXN Manager. Give it a whirl!</p>

<p>Good hacking!</p>`,

    'Sorry, but this URL is invalid. I think you either want <a href="$url">/</a> or to run PGXN Manager behind a reverse proxy server. See <a href="https://github.com/pgxn/pgxn-manager/blob/main/README.md">the README</a> for details.' => 'Sorry, but this URL is invalid. I think you either want <a href="$url">/</a> or to run PGXN Manager behind a reverse proxy server. See <a href="https://github.com/pgxn/pgxn-manager/blob/main/README.md">the README</a> for details.',

    '“[_1] [_2]” is not a known release' => '“[_1] [_2]” is not a known release',
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

=encoding utf8

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
3282|https://tools.ietf.org/html/rfc3282>. The parsing of this header is
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

=head1 Author

David E. Wheeler <david@justatheory.com>

=head1 Copyright and License

Copyright (c) 2010-2023 David E. Wheeler.

This module is free software; you can redistribute it and/or modify it under
the L<PostgreSQL License|https://www.opensource.org/licenses/postgresql>.

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
