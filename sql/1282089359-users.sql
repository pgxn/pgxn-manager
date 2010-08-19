-- sql/1282089359-users.sql SQL Migration

SET client_min_messages TO warning;
SET log_min_messages    TO warning;

CREATE TABLE users (
    nickname   LABEL       PRIMARY KEY,
    password   TEXT        NOT NULL,
    email      EMAIL       NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    visited_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

GRANT SELECT ON users TO pgxn;

CREATE OR REPLACE FUNCTION insert_user(
    nick  LABEL,
    pass  TEXT,
    email EMAIL
) RETURNS BOOLEAN LANGUAGE SQL SECURITY DEFINER AS $$
    INSERT INTO users (nickname, password, email)
    VALUES ($1, crypt($2, gen_salt('des')), $3);
    SELECT TRUE;
$$;

CREATE OR REPLACE FUNCTION change_password(
    nick    LABEL,
    oldpass TEXT,
    newpass TEXT
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    UPDATE users
       SET password = crypt($3, gen_salt('des')),
           updated_at = NOW()
     WHERE nickname = $1
       AND password = crypt($2, password);
    RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION change_email(
    nick    LABEL,
    oldmail EMAIL,
    newmail EMAIL
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
    nick  LABEL
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    UPDATE users
       SET visited_at = NOW()
     WHERE nickname = $1;
    RETURN FOUND;
END;
$$;

