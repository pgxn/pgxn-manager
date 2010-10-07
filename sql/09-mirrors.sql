-- sql/1283200230-mirrors.sql SQL Migration

SET client_min_messages TO warning;
SET log_min_messages    TO warning;

BEGIN;

CREATE TABLE mirrors (
    uri          URI         PRIMARY KEY,
    frequency    TEXT        NOT NULL,
    location     TEXT        NOT NULL,
    organization TEXT        NOT NULL,
    timezone     TIMEZONE    NOT NULL,
    contact      EMAIL       NOT NULL,
    bandwidth    TEXT        NOT NULL,
    src          URI         NOT NULL,
    rsync        URI             NULL,
    notes        TEXT            NULL,
    created_by   LABEL       NOT NULL REFERENCES users(nickname),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_mirrors_created_at ON mirrors(created_at);
GRANT SELECT ON mirrors TO pgxn;

CREATE OR REPLACE FUNCTION is_admin(
    nick LABEL
) RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
/*

    SELECT is_admin('username');

Returns true if the named user is an admin, and false if not.

*/
    SELECT EXISTS(
        SELECT TRUE FROM users WHERE nickname = $1 AND is_admin
    );
$$;

CREATE OR REPLACE FUNCTION insert_mirror(
    creator      LABEL,
    uri          URI       DEFAULT NULL,
    frequency    TEXT      DEFAULT NULL,
    location     TEXT      DEFAULT NULL,
    organization TEXT      DEFAULT NULL,
    timezone     TIMEZONE  DEFAULT NULL,
    contact      EMAIL     DEFAULT NULL,
    bandwidth    TEXT      DEFAULT NULL,
    src          URI       DEFAULT NULL,
    rsync        URI       DEFAULT NULL,
    notes        TEXT      DEFAULT NULL
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
/*

    % SELECT insert_mirror(
        creator      := 'theory',
        uri          := 'http://kineticode.com/pgxn/',
        frequency    := 'hourly',
        location     := 'Portland, OR, USA',
        bandwidth    := '10MBps',
        organization := 'Kineticode, Inc.',
        timezone     := 'America/Los_Angeles',
        contact      := 'pgxn@kineticode.com',
        src          := 'rsync://master.pgxn.org/pgxn/',
        rsync        := 'rsync://pgxn.kineticode.com/pgxn/',
        notes        := 'This is a note'
    );
     insert_mirror 
    ───────────────
     t
    (1 row)

Inserts a mirror. The user specified as the first parameter must be an
administrator or else an exception will be thrown. All arguments are required
except `rsync` and `notes`. Returns true on succesful insert and false on
failure (probably impossible, normally an exception will be thrown on
failure).

*/
BEGIN
    IF NOT is_admin(creator) THEN
        RAISE EXCEPTION 'Permission denied: User “%” is not an administrator', creator;
    END IF;

    INSERT INTO mirrors (
        uri,
        frequency,
        location,
        organization,
        timezone,
        contact,
        bandwidth,
        src,
        rsync,
        notes,
        created_by
    ) VALUES (
        insert_mirror.uri,
        insert_mirror.frequency,
        insert_mirror.location,
        insert_mirror.organization,
        insert_mirror.timezone,
        insert_mirror.contact,
        insert_mirror.bandwidth,
        insert_mirror.src,
        insert_mirror.rsync,
        insert_mirror.notes,
        creator
    );
      
    RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION delete_mirror(
    deleter LABEL,
    uri     URI
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
/*

    % SELECT delete_mirror('theory', 'http://kineticode.com/pgxn/');
     delete_mirror 
    ───────────────
     t

Deletes a mirror. The user specified as the first parameter must be an
administrator or else an exception will be thrown. Returns true if the
specified mirror was deleted and false if not.

*/
BEGIN
    IF NOT is_admin(deleter) THEN
        RAISE EXCEPTION 'Permission denied: User “%” is not an administrator', deleter;
    END IF;

    DELETE FROM mirrors WHERE mirrors.uri = delete_mirror.uri;
    RETURN FOUND;
END;
$$;

COMMIT;
