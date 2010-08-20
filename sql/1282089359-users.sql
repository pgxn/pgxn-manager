-- sql/1282089359-users.sql SQL Migration

SET client_min_messages TO warning;
SET log_min_messages    TO warning;

BEGIN;

CREATE TABLE users (
    nickname   LABEL       PRIMARY KEY,
    password   TEXT        NOT NULL,
    full_name  TEXT        NOT NULL,
    email      EMAIL       NOT NULL,
    uri        URI         NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    visited_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

GRANT SELECT ON users TO pgxn;

CREATE OR REPLACE FUNCTION insert_user(
    nick LABEL,
    pass TEXT,
    p    HSTORE
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    IF char_length(pass) < 4 THEN
       RAISE EXCEPTION 'Password must be at least four characters long';
    END IF;
    INSERT INTO users (nickname, password, full_name, email, uri)
    VALUES (nick, crypt(pass, gen_salt('des')), COALESCE(p->'full_name', ''), p->'email', p->'uri');
    RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION change_password(
    nick    LABEL,
    oldpass TEXT,
    newpass TEXT
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    IF char_length(newpass) < 4 THEN
       RAISE EXCEPTION 'Password must be at least four characters long';
    END IF;
    UPDATE users
       SET password = crypt($3, gen_salt('des')),
           updated_at = NOW()
     WHERE nickname = $1
       AND password = crypt($2, password);
    RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION update_user(
    nick LABEL,
    p    HSTORE
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    UPDATE users
       SET full_name  = COALESCE(p->'full_name', full_name),
           email      = COALESCE(p->'email',     email),
           uri        = COALESCE(p->'uri',       uri),
           updated_at = NOW()
     WHERE nickname = nick;
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

COMMIT;
