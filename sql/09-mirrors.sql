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
    admin        LABEL,
    uri          URI,
    frequency    TEXT,
    location     TEXT,
    organization TEXT,
    timezone     TIMEZONE,
    contact      EMAIL,
    bandwidth    TEXT,
    src          URI,
    rsync        URI       DEFAULT NULL,
    notes        TEXT      DEFAULT NULL
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
/*

    % SELECT insert_mirror(
        admin        := 'theory',
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
    IF NOT is_admin(admin) THEN
        RAISE EXCEPTION 'Permission denied: User “%” is not an administrator', admin;
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
        admin
    );
      
    RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION update_mirror(
    admin      LABEL,
    old_uri      URI,
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

    % SELECT udpate_mirror(
        admin        := 'theory',
        old_uri      := 'http://kineticode.com/pgxn/',
        uri          := 'http://pgxn.kineticode.com/',
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
     update_mirror 
    ───────────────
     t
    (1 row)

Updates a mirror. The user specified as the first parameter must be an
administrator or else an exception will be thrown. The `old_uri` parameter
must contain the existing URI of the mirror and is required. All other
paramters are optional. Returns true on succesful update and false on failure,
which will happen if the existing URI cannot be found in the database.

*/
BEGIN
    IF NOT is_admin(admin) THEN
        RAISE EXCEPTION 'Permission denied: User “%” is not an administrator', admin;
    END IF;

    UPDATE mirrors SET (
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
        updated_at
    ) = (
        COALESCE(update_mirror.uri,          mirrors.uri),
        COALESCE(update_mirror.frequency,    mirrors.frequency),
        COALESCE(update_mirror.location,     mirrors.location),
        COALESCE(update_mirror.organization, mirrors.organization),
        COALESCE(update_mirror.timezone,     mirrors.timezone),
        COALESCE(update_mirror.contact,      mirrors.contact),
        COALESCE(update_mirror.bandwidth,    mirrors.bandwidth),
        COALESCE(update_mirror.src,          mirrors.src),
        COALESCE(update_mirror.rsync,        mirrors.rsync),
        COALESCE(update_mirror.notes,        mirrors.notes),
        NOW()
    ) WHERE mirrors.uri = update_mirror.old_uri;

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
