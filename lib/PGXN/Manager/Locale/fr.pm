package PGXN::Manager::Locale::fr;

use 5.12.0;
use utf8;
use parent 'PGXN::Manager::Locale';

our %Lexicon = (
    listcomma => ',',
    listand   => 'et',
    openquote => '«',
    shutquote => '»',
    Welcome => 'Bienvenue',
);

1;

=head1 Name

PGXN::Manager::Locale::fr - French localization for PGXN::Manager

=head1 Synopsis

  use PGXN::Manager::Locale;
  my $mt = PGXN::Manager::Locale->accept('fr');

=head1 Description

Subclass of L<PGXN::Manager::Locale> providing French localization.

=head1 Author

David E. Wheeler <david.wheeler@pgexperts.com>

=head1 Copyright and License

Copyright (c) 2010 David E. Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.
