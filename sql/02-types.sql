-- sql/02-types.sql SQL Migration

SET client_min_messages TO warning;
SET log_min_messages    TO warning;

BEGIN;

------------------------------------------------------------------------------
-- Create a timezone data type. This is really fast. See
-- http://justatheory.com/computers/databases/postgresql/timezone_validation.html.

CREATE OR REPLACE FUNCTION is_timezone(
    tz CITEXT
) RETURNS BOOLEAN LANGUAGE plpgsql STABLE AS $$
BEGIN
    PERFORM NOW() AT TIME ZONE tz;
    RETURN TRUE;
EXCEPTION WHEN invalid_parameter_value THEN
    RETURN FALSE;
END;
$$;

CREATE DOMAIN timezone AS CITEXT CHECK ( is_timezone( VALUE ) );

------------------------------------------------------------------------------
-- Create a label data type, following the rules in RFC 1034. Labels can then
-- be used as host names in domains.
--
-- http://tools.ietf.org/html/rfc1034
--
-- "The labels must follow the rules for ARPANET host names. They must
-- start with a letter, end with a letter or digit, and have as interior
-- characters only letters, digits, and hyphen.  There are also some
-- restrictions on the length. Labels must be 63 characters or less."

CREATE DOMAIN label AS CITEXT
 CHECK ( VALUE ~ '^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$' );

------------------------------------------------------------------------------
-- Create an email data type.
--
-- Check constraint is_email for email base type
-- Using Email::Valid, as suggested by Greg Sabino Mullane.
-- http://people.planetpostgresql.org/greg/index.php?/archives/49-Avoiding-the-reinvention-of-two-email-wheels.html
--
CREATE OR REPLACE FUNCTION is_email(
    email CITEXT
) RETURNS BOOLEAN LANGUAGE 'plperl' IMMUTABLE AS $$
    return 'true' if Email::Valid->address( $_[0] );
    return 'false';
$$;

CREATE DOMAIN email AS CITEXT CHECK ( VALUE IS NULL OR is_email( VALUE ) );

------------------------------------------------------------------------------
-- Create a URI data type.
--
-- Using Data::Validate::URI.

CREATE OR REPLACE FUNCTION is_uri(
    uri CITEXT
)RETURNS BOOLEAN LANGUAGE 'plperl' IMMUTABLE AS $$
    return 'true' if Data::Validate::URI::is_uri( $_[0] ) || $_[0] eq '';
    return 'false';
$$;

CREATE DOMAIN uri AS CITEXT CHECK ( VALUE IS NULL OR is_uri( VALUE ) );

COMMIT;
