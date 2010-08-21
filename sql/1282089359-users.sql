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
/*

Inserts a new user into the database. The nickname must not already exist or
an exception will be thrown. The password must be at least four characters
long or an exception will be thrown. Pass other attributes via the `hstore`
parameters:

full_name
: The full name of the user.

email
: The email address of the user. Must be a valid email address as verified by
  [Email::Valid](http://search.cpan.org/perldoc?Email::Valid).

uri
: Optional URI for the user. Should be a valid URI as verified by
  [Data::Validate::URI](http://search.cpan.org/perldoc?Data::Validate::URI).

Returns true if the user was inserted, and false if not.

*/
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
/*

Changes a user's password. The old password must match the existing password
for the nickname or the password will not be set. The password must be at
least four charcters long or an exception will be thrown. Returns true if the
password was changed and false if it was not.

*/
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
/*

Update the specivied user. The nickname cannot be changed. The password can
only be changed via `change_password()` or `reset_password()`. Pass other
attributes via the `hstore` parameters:

full_name
: The full name of the user.

email
: The email address of the user. Must be a valid email address as verified by
  [Email::Valid](http://search.cpan.org/perldoc?Email::Valid).

uri
: Optional URI for the user. Should be a valid URI as verified by
  [Data::Validate::URI](http://search.cpan.org/perldoc?Data::Validate::URI).

Returns true if the user was updated, and false if not.

*/
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

CREATE OR REPLACE FUNCTION log_visit(
    nick  LABEL
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
/*

Log the visit for the specified user. At this point, that just means that
`users.visited_at` gets set to the current time.

*/
BEGIN
    UPDATE users
       SET visited_at = NOW()
     WHERE nickname = $1;
    RETURN FOUND;
END;
$$;

COMMIT;
