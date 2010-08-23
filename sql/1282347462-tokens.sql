-- sql/1282347462-tokens.sql SQL Migration

SET client_min_messages TO warning;
SET log_min_messages    TO warning;

BEGIN;

CREATE TABLE tokens (
    token      TEXT        PRIMARY KEY,
    nickname   LABEL       NOT NULL REFERENCES users(nickname),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW() + '1 day'::interval
);

CREATE OR REPLACE FUNCTION rand_str_of_len(
    string_length INTEGER
) RETURNS TEXT LANGUAGE 'plpgsql' STRICT AS $$
/*

Returns a random string of ASCII alphanumeric characters of the specified
length. Borrowed [from
Depesz](http://www.depesz.com/index.php/2007/06/25/random-text-record-identifiers/).

*/
DECLARE
    chars TEXT = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
    ret   TEXT = '';
    pos   INTEGER;
BEGIN
    FOR i IN 1..string_length LOOP
        pos := 1 + ( random() * ( length(chars) - 1) )::INTEGER;
        ret := ret || substr(chars, pos, 1);
    END LOOP;
    RETURN ret;
END;
$$;

CREATE OR REPLACE FUNCTION forgot_password(
    nick LABEL
) RETURNS TEXT[] LANGUAGE plpgsql SECURITY DEFINER AS $$
/*

Creates a password reset token for the specified nickname. The user must be
active. The return value is a two-element array. The first value is the token,
and the second the email address of the user. The token will be set to expire
1 day from creation. Returns `NULL` if the token cannot be created (because no
user exists for the specified nickname or the user is not ative).

*/
DECLARE
    len  INTEGER := 5;
    tok  TEXT;
    nick LABEL;
    mail EMAIL;
BEGIN
    SELECT nickname, email
      INTO nick,     mail
      FROM users
     WHERE nickname = $1
       AND status   = 'active';

    IF nick IS NULL THEN RETURN NULL; END IF;

    LOOP BEGIN
        tok := rand_str_of_len(len);
        INSERT INTO tokens (token, nickname)
        SELECT tok, nick;
        IF FOUND THEN RETURN ARRAY[tok, mail]; END IF;
    EXCEPTION WHEN unique_violation THEN
        len := len + 1;
        IF len >= 30 THEN
            RAISE EXCEPTION '30-character id requested; something is wrong';
        END IF;
    END; END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION reset_password(
    tok   TEXT,
    pass  TEXT
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
/*

Pass in a token and a new password to reset a user password. The token must
exist and must not have expired and the associated user must be active. The
password must be at least four characters long or an exception will be thrown.
Returns `true` on success and `false` on failure.

*/
DECLARE
    nick LABEL;
BEGIN
    IF char_length(pass) < 4 THEN
       RAISE EXCEPTION 'Password must be at least four characters long';
    END IF;

    DELETE FROM tokens
     USING users
     WHERE token          = tok
       AND expires_at    >= NOW()
       AND users.nickname = tokens.nickname
       AND users.status   = 'active'
    RETURNING tokens.nickname INTO nick;

    IF nick IS NULL THEN RETURN FALSE; END IF;

    UPDATE users
       SET password   = crypt(pass, gen_salt('des')),
           updated_at = NOW()
     WHERE nickname   = nick
       AND status     = 'active';

    RETURN TRUE;
END;
$$;

COMMIT;
