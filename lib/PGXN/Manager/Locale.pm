package PGXN::Manager::Locale;

use 5.10.0;
use utf8;
use parent 'Locale::Maketext';
use I18N::LangTags::Detect;

our $VERSION = v0.32.2;

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

sub from_file {
    my ($self, $path) = (shift, shift);
    my $class = ref $self;
    my $file = $PATHS_FOR{$class}{$path} ||= _find_file($class, $path);
    open my $fh, '<:utf8', $file or die "Cannot open $file: $!\n";
    local $/; <$fh>;
}

sub _find_file {
    my $class = shift;
    my @path = split m{/}, shift;
    (my $dir = __FILE__) =~ s{[.]pm$}{};
    no strict 'refs';
    foreach my $super ($class, @{$class . '::ISA'}, __PACKAGE__ . '::en') {
        my $file = File::Spec->catfile($dir, $super->language_tag, @path);
        return $file if -e $file;
    }
    die "No file found for path " . join('/', @path);
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

=head3 C<from_file>

  my $text = $mt->from_file('foo/bar.html');
  my $msg  = $mt->from_file('feedback.html', 'pgxn@example.com');

Returns the contents of a localized file. The file argument should be
specified with Unix semantics, regardless of operating system. Whereas
subclasses contain short strings that need translating, the files can contain
complete documents.

If a file doesn't exist for the current language, C<from_file()> will fall
back on the same file path for any of its parent classes. If none has the
file, it will fall back on the English file.

Localized files are maintained in
L<multimarkdown|https://fletcherpenney.net/multimarkdown/> format by translators
and converted to HTML. They live in a subdirectory named for the last part of a
subclass's package name. For example, the L<PGXN::Site::Locale::fr> class lives
in F<PGXN/Site/Locale/fr.pm>. Localized files will live in F<PGXN/Site/Locale/fr/>.
So for the argument C<feedback.html>, the localized file will be
F<PGXN/Site/Locale/fr/howto.html>

=head1 Author

David E. Wheeler <david@justatheory.com>

=head1 Copyright and License

Copyright (c) 2010-2024 David E. Wheeler.

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
