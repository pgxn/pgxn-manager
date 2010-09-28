package PGXN::Manager::Locale::en;

use 5.12.0;
use utf8;
use parent 'PGXN::Manager::Locale';

our %Lexicon = (
    listcomma => ',',
    listand   => 'and',
    openquote => '“',
    shutquote => '”',
    main_title => 'PGXN Manager: Distribute your PostgreSQL Extensions on PGXN',
    Welcome   => 'Welcome',
    'PGXN Manager' => 'PGXN Manager',
    tagline => 'Release it on PGXN!',
    'Resource not found.' => 'Hrm. I can’t find a resource at this address. I looked over here and over there and could find nothing. Sorry about that, I’m fresh out of ideas.',
    'Not Found' => 'Where’d It Go?',
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

Copyright (c) 2010 David E. Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.
