-- sql/07-roles.sql SQL Migration

SET client_min_messages TO warning;

BEGIN;

CREATE OR REPLACE FUNCTION json_key(
    string TEXT
) RETURNS TEXT LANGUAGE plperl IMMUTABLE AS $$
=begin markdown

    % SELECT json_key('foo');
     json_key 
    ──────────
     "foo"

Like `json_string()`, this function encodes a text value as a JSON string and
returns the string. The difference is that `NULL` is treated as illegal
(because it cannot be used as a JSON key) and will thus throw an exception.

=end markdown

=cut
    elog(ERROR, 'JSON object keys cannot be NULL') unless defined $_[0];
    JSON::XS->new->utf8(0)->allow_nonref->encode(shift);
$$;

CREATE OR REPLACE FUNCTION json_value(
    val TEXT,
    def TEXT DEFAULT 'null'
) RETURNS TEXT LANGUAGE plperl IMMUTABLE AS $$
=begin markdown

    % SELECT json_value('foo'), json_value(NULL), json_value(NULL, 'default'),
             json_value(NULL, NULL);
     json_value │ json_value │ json_value │ json_value 
    ────────────┼────────────┼────────────┼────────────
     "foo"      │ null       │ default    │ 

Encodes a text value as a JSON string. If the string is `NULL`, the second
argument will be used as a fallback. If there is no second argument, it will
fall back to "null".

=end markdown

=cut
    defined $_[0] ? JSON::XS->new->utf8(0)->allow_nonref->encode($_[0]) : $_[1];
$$;

CREATE OR REPLACE FUNCTION json_value(
    val numeric,
    def TEXT DEFAULT 'null'
) RETURNS TEXT LANGUAGE SQL IMMUTABLE AS $$
/*

    % SELECT json_value(1.2), json_value(NULL::int),
             json_value(NULL::int, 'default'), json_value(NULL::int, NULL);
     json_value │ json_value │ json_value │ json_value 
    ────────────┼────────────┼────────────┼────────────
     1.2        │ null       │ default    │ 

Encodes a numeric value as a JSON number. If the number is `NULL`, the second
argument will be used as a fallback. If there is no second argument, it will
fall back to "null".

*/
    SELECT COALESCE($1::text, $2);
$$;

CREATE OR REPLACE FUNCTION json_value(
    val BOOLEAN,
    def TEXT DEFAULT 'null'
) RETURNS TEXT LANGUAGE SQL IMMUTABLE AS $$
/*

    % SELECT json_value(TRUE), json_value(NULL::bool),
             json_value(NULL::bool, 'default'), json_value(NULL::bool, NULL);
     json_value │ json_value │ json_value │ json_value 
    ────────────┼────────────┼────────────┼────────────
     true       │ null       │ default    │ [null]

Encodes a boolean value as a JSON boolean ("true" or "false"). If the boolean
is `NULL`, the second argument will be used as a fallback. If there is no
second argument, it will fall back to "null".

*/
    SELECT COALESCE($1::text, $2);
$$;

COMMIT;
