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
    email      EMAIL       NOT NULL UNIQUE,
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
    nickname   LABEL,
    password   TEXT,
    full_name  TEXT  DEFAULT '',
    email      EMAIL DEFAULT NULL,
    uri        URI   DEFAULT NULL
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
/*

    % SELECT insert_user(
        nickname  := 'theory',
        password  := '***',
        full_name := 'David Wheeler',
        email     := 'theory@pgxn.org',
        uri       := 'http://justatheory.com/'
    );
     insert_user 
    ─────────────
     t

Inserts a new user into the database. The nickname must not already exist or
an exception will be thrown. The password must be at least four characters
long or an exception will be thrown. The status will be set to "new" and the
`set_by` set to the new user's nickname. The other parameters are:

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
    IF char_length(password) < 4 THEN
       RAISE EXCEPTION 'Password must be at least four characters long';
    END IF;
    INSERT INTO users (
        nickname,
        password,
        full_name,
        email,
        uri,
        set_by
    )
    VALUES (
        insert_user.nickname,
        crypt(insert_user.password, gen_salt('des')),
        COALESCE(insert_user.full_name, ''),
        insert_user.email,
        insert_user.uri,
        insert_user.nickname
    );
    RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION change_password(
    nickname LABEL,
    oldpass  TEXT,
    newpass  TEXT
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
/*

    % SELECT change_password('strongrrl', '****', 'whatever');
     change_password 
    ─────────────────
     t

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
       SET password       = crypt(newpass, gen_salt('des')),
           updated_at     = NOW()
     WHERE users.nickname = change_password.nickname
       AND users.password = crypt(oldpass, password)
       AND users.status   = 'active';
    RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION update_user(
    nickname   LABEL,
    full_name  TEXT  DEFAULT NULL,
    email      EMAIL DEFAULT NULL,
    uri        URI   DEFAULT NULL
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
/*

    % SELECT update_user(
        nickname  := 'theory',
        full_name := 'David E. Wheeler',
        email     := 'justatheory@pgxn.org',
        uri       := 'http://www.justatheory.com/'
    );
     update_user 
    ─────────────
     t

Update the specified user. The user must be active. The nickname cannot be
changed. The password can only be changed via `change_password()` or
`reset_password()`. Pass other attributes as:

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
       SET full_name      = COALESCE(update_user.full_name, users.full_name),
           email          = COALESCE(update_user.email,     users.email),
           uri            = COALESCE(update_user.uri,       users.uri),
           updated_at     = NOW()
     WHERE users.nickname = update_user.nickname
       AND users.status   = 'active';
    RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION log_visit(
    nickname  LABEL
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
/*

    % SELECT log_visit('theory');
     log_visit 
    ───────────
     t

Log the visit for the specified user. At this point, that just means that
`users.visited_at` gets set to the current time.

*/
BEGIN
    UPDATE users
       SET visited_at     = NOW()
     WHERE users.nickname = $1;
    RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION set_user_status(
    setter    LABEL,
    nickname  LABEL,
    status    STATUS
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
/*

    % SELECT set_user_status('admin', 'strongrrl', 'active');
     set_user_status 
    ─────────────────
     t

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
    PERFORM TRUE FROM users WHERE users.nickname = setter AND is_admin;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Permission denied: User “%” is not an administrator', setter;
    END IF;

    -- Prevent user from changing own status.
    IF setter = nickname THEN
        RAISE EXCEPTION 'Permission denied: User cannot modify own status';
    END IF;

    -- Go ahead and do it.
    UPDATE users
       SET status         = set_user_status.status,
           set_by         = setter,
           updated_at     = NOW()
     WHERE users.nickname = set_user_status.nickname
       AND users.status  <> set_user_status.status;
    RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION set_user_admin(
    setter   LABEL,
    nickname LABEL,
    set_to   BOOLEAN
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
/*

    % select set_user_admin('admin', 'strongrrl', true);
     set_user_admin 
    ────────────────
     t

Sets a user's administrator flag. The nickname of the user who does so must be
passed as the first argument, and that user must be an administrator.
Administrators may set their own administrator flags to `false`. If the
administrator flag is already set to the specified value, the record will not
be updated and `false` will be returned.

*/
BEGIN
    -- Make sure we have an admin.
    PERFORM TRUE FROM users WHERE users.nickname = setter AND is_admin;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Permission denied: User “%” is not an administrator', setter;
    END IF;

    -- Go ahead and do it.
    UPDATE users
       SET is_admin       = set_to,
           updated_at     = NOW()
     WHERE users.nickname = set_user_admin.nickname
       AND is_admin      <> set_to;
    RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION authenticate_user(
   nickname CITEXT,
   password TEXT
) RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER AS $$
/*

    % select authenticate_user('admin', '*****');
     authenticate_user
    ────────────────
     t

Returns true if the user with the specified nickname exists, is active, and
the password matches. Otherwise returns false.

*/
    SELECT EXISTS(
        SELECT TRUE
          FROM users
         WHERE nickname = $1
           AND status = 'active'
           AND password = crypt($2, password)
    );
$$;

COMMIT;
