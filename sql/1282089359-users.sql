-- sql/1282089359-users.sql SQL Migration

SET client_min_messages TO warning;
SET log_min_messages    TO warning;

BEGIN;

CREATE TYPE status AS ENUM(
    'new',
    'active',
    'inactive',
    'deleted'
);

CREATE TABLE users (
    nickname   LABEL       PRIMARY KEY,
    password   TEXT        NOT NULL,
    full_name  TEXT        NOT NULL,
    email      EMAIL       NOT NULL,
    uri        URI         NULL,
    status     STATUS      NOT NULL DEFAULT 'new',
    set_by     LABEL       NOT NULL REFERENCES users(nickname),
    is_admin   BOOLEAN     NOT NULL DEFAULT FALSE,
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
long or an exception will be thrown. The status will be set to "new" and the
`set_by` set to the user's nickname. Pass other attributes via the `hstore`
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
    INSERT INTO users (nickname, password, full_name, email, uri, set_by)
    VALUES (nick, crypt(pass, gen_salt('des')), COALESCE(p->'full_name', ''), p->'email', p->'uri', nick);
    RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION change_password(
    nick    LABEL,
    oldpass TEXT,
    newpass TEXT
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
/*

Changes a user's password. The user must be active, and the old password must
match the existing password for the nickname or the password will not be set.
The password must be at least four charcters long or an exception will be
thrown. Returns true if the password was changed and false if it was not.

*/
BEGIN
    IF char_length(newpass) < 4 THEN
       RAISE EXCEPTION 'Password must be at least four characters long';
    END IF;
    UPDATE users
       SET password = crypt($3, gen_salt('des')),
           updated_at = NOW()
     WHERE nickname = $1
       AND password = crypt($2, password)
       AND status   = 'active';
    RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION update_user(
    nick LABEL,
    p    HSTORE
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
/*

Update the specivied user. The user must be active. The nickname cannot be
changed. The password can only be changed via `change_password()` or
`reset_password()`. Pass other attributes via the `hstore` parameters:

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
     WHERE nickname   = nick
       AND status     = 'active';
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

CREATE OR REPLACE FUNCTION set_user_status(
    setter LABEL,
    nick   LABEL,
    stat   STATUS
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
/*

Sets a user's status. The status may be one of "active", "inactive", or
"deleted". The nickname of the user who sets the status must be passed as the
first argument, and that user must be an administrator or an exception will be
thrown. That nickname will be stored in the `set_by` column. Users cannot
change their own status; if `setter` and `nick` are the same, an exception
will be thrown. Returns true if the status was set, and false if not. If the
status is already set to the specified value, the record will not be updated
and `false` will be returned.

*/
BEGIN
    -- Make sure we have an admin.
    PERFORM TRUE FROM users WHERE nickname = setter AND is_admin;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Permission denied: User “%” is not an administrator', setter;
    END IF;

    -- Prevent user from changing own status.
    IF setter = nick THEN
        RAISE EXCEPTION 'Permission denied: User cannot modify own status';
    END IF;

    -- Go ahead and do it.
    UPDATE users
       SET status     = stat,
           set_by     = setter,
           updated_at = NOW()
     WHERE nickname   = nick
       AND status    <> stat;
    RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION set_user_admin(
    setter LABEL,
    nick   LABEL,
    setto  BOOLEAN
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
/*

Sets a user's administrator flag. The nickname of the user who does so must be
passed as the first argument, and that user must be an administrator.
Administrators may set their own administrator flags to `false`. If the
administrator flag is already set to the specified value, the record will not
be updated and `false` will be returned.

*/
BEGIN
    -- Make sure we have an admin.
    PERFORM TRUE FROM users WHERE nickname = setter AND is_admin;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Permission denied: User “%” is not an administrator', setter;
    END IF;

    -- Go ahead and do it.
    UPDATE users
       SET is_admin   = setto,
           updated_at = NOW()
     WHERE nickname   = nick
       AND is_admin  <> setto;
    RETURN FOUND;
END;
$$;

COMMIT;
