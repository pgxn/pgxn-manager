package PGXN::Manager::Locale::en;

use 5.12.0;
use utf8;
use parent 'PGXN::Manager::Locale';

our %Lexicon = (
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
);

1;

=head1 Name

PGXN::Manager::Locale::en - English localization for PGXN::Manager

=head1 Synopsis

  use PGXN::Manager::Locale;
  my $mt = PGXN::Manager::Locale->accept('en');

=head1 Description

Subclass of L<PGXN::Manager::Locale> providing English localization.

=head1 Author

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
