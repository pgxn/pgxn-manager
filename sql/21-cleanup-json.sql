BEGIN;

SET client_min_messages TO warning;

-- Drop replaced functions.
DO LANGUAGE PLpgSQL $$
BEGIN
    IF current_setting('server_version_num')::int < 170000 THEN
        EXECUTE $_$
            DROP FUNCTION IF EXISTS json_value(TEXT, TEXT);
            DROP FUNCTION IF EXISTS json_value(NUMERIC, TEXT);
            DROP FUNCTION IF EXISTS json_value(BOOLEAN, TEXT);
        $_$;
    END IF;
END;
$$;

COMMIT;
