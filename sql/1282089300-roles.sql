-- sql/1282089300-roles.sql SQL Migration

BEGIN;

CREATE FUNCTION add_role() RETURNS VOID LANGUAGE SQL AS $$
    CREATE ROLE pgxn WITH LOGIN;
$$;

SELECT add_role() WHERE NOT EXISTS (
    SELECT true FROM pg_roles WHERE rolname = 'pgxn'
);

DROP FUNCTION add_role();

GRANT USAGE ON SCHEMA contrib TO pgxn;

COMMIT;

