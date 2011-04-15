-- sql/01-roles.sql SQL Migration

SET client_min_messages TO warning;
SET log_min_messages    TO warning;

BEGIN;

DO $$
BEGIN
    PERFORM true FROM pg_roles WHERE rolname = 'pgxn';
    IF NOT FOUND THEN
        CREATE ROLE pgxn WITH LOGIN;
    END IF;
END;
$$;

GRANT USAGE ON SCHEMA contrib TO pgxn;

COMMIT;
