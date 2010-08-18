-- sql/1282089359-users.sql SQL Migration

SET client_min_messages TO warning;
SET log_min_messages    TO warning;

CREATE TABLE users (
    nickname   CITEXT      PRIMARY KEY,
    password   TEXT        NOT NULL,
    email      CITEXT      NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    visited_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

GRANT SELECT ON users TO pgxn;

CREATE OR REPLACE FUNCTION insert_user(
    nick  TEXT,
    pass  TEXT,
    email CITEXT
) RETURNS VOID LANGUAGE SQL SECURITY DEFINER AS $$
    INSERT INTO users (nickname, password, email)
    VALUES ($1, crypt($2, gen_salt('md5')), $3);
$$;

CREATE OR REPLACE FUNCTION change_password(
    nick    TEXT,
    oldpass TEXT,
    newpass TEXT
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    UPDATE users
       SET password = crypt($3, gen_salt('md5')),
           updated_at = NOW()
     WHERE nickname = $1
       AND password = crypt($2, password);
    RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION change_email(
    nick    TEXT,
    oldmail TEXT,
    newmail TEXT
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    UPDATE users
       SET email    = $3,
           updated_at = NOW()
     WHERE nickname = $1
       AND email    = $2;
    RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION log_visit(
    nick    TEXT
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    UPDATE users
       SET visited_at = NOW()
     WHERE nickname = $1;
    RETURN FOUND;
END;
$$;

