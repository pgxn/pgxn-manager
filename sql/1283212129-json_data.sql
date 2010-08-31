-- sql/1283212129-json_data.sql SQL Migration

SET client_min_messages TO warning;
SET log_min_messages    TO warning;

BEGIN;

CREATE OR REPLACE FUNCTION munge_email(
    email EMAIL
) RETURNS TEXT LANGUAGE plpgsql IMMUTABLE STRICT AS $$
/*

    SELECT munge_email('foo@bar.com');

Munges an email address. This is for use in `mirrors.json`, just to have a bit
of obfuscation. All it does is move the username to the end, separated from
the domain name by a pipe. So "foo@bar.com" becomes "bar.com|foo".

*/
BEGIN
    RETURN split_part(email, '@', 2) || '|' || split_part(email, '@', 1);
END;
$$;

CREATE OR REPLACE FUNCTION get_mirrors_json(
) RETURNS TEXT LANGUAGE sql STABLE AS $$
/*

    SELECT get_mirrors_json();

Returns the JSON for the `mirrors.json` file.

*/
    SELECT E'[\n  ' || array_to_string(ARRAY(
        SELECT E'{\n    ' || array_to_string(ARRAY[
            json_key('uri')          || ': ' || json_value(uri),
            json_key('frequency')    || ': ' || json_value(frequency),
            json_key('location')     || ': ' || json_value(location),
            json_key('organization') || ': ' || json_value(organization),
            json_key('timezone')     || ': ' || json_value(timezone),
            json_key('contact')      || ': ' || json_value(munge_email(contact)),
            json_key('bandwidth')    || ': ' || json_value(bandwidth),
            json_key('src')          || ': ' || json_value(src),
            json_key('rsync')        || ': ' || json_value(rsync, NULL),
            json_key('notes')        || ': ' || json_value(notes, NULL)
        ], E',\n    '
        ) || E'\n  }'FROM mirrors
         ORDER BY created_at
    ), E',\n  ') || E'\n]\n';
$$;

COMMIT;
