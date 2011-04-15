-- sql/12-fixtures.sql SQL Migration

SET client_min_messages TO warning;
SET log_min_messages    TO warning;

BEGIN;

DO $$
BEGIN
    IF current_database() = 'pgxn_manager_test' THEN
        -- Create a function purely for tests to use to grant a user admin
        -- permission without being an admin. Only created in the test db.
        CREATE FUNCTION _test_set_admin(
            CITEXT
        ) RETURNS VOID LANGUAGE SQL SECURITY DEFINER AS $_$
            UPDATE users SET is_admin = true WHERE nickname = $1;
        $_$;
    END IF;
END;
$$;

COMMIT;


