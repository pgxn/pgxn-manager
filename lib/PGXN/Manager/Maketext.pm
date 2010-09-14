package PGXN::Manager::Maketext;

use 5.12.0;
use utf8;
use parent 'Locale::Maketext';
use I18N::LangTags::Detect;

# Allow unknown phrases to just pass-through.
our %Lexicon = ( _AUTO => 1 );

sub accept {
    shift->get_handle( I18N::LangTags::Detect->http_accept_langs(shift) );
}

1;
