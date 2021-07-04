BEGIN;

-- Utilityt function to create the password salt, so it can be quickly swapped
-- for new algorithms in the future.
CREATE OR REPLACE FUNCTION _salt() RETURNS TEXT LANGUAGE SQL AS $$
    SELECT gen_salt('bf', 9);
$$;

CREATE OR REPLACE FUNCTION insert_user(
    nickname   LABEL,
    password   TEXT,
    full_name  TEXT   DEFAULT '',
    email      EMAIL  DEFAULT NULL,
    uri        URI    DEFAULT NULL,
    twitter    CITEXT DEFAULT NULL,
    why        TEXT   DEFAULT NULL
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
/*

    % SELECT insert_user(
        nickname  := 'theory',
        password  := '***',
        full_name := 'David Wheeler',
        email     := 'theory@pgxn.org',
        uri       := 'https://justatheory.com/',
        twitter   := 'theory',
        why       := 'Because I’m a bitchin’ Pg developer, yo.'
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
  [Email::Valid](https://metacpan.org/pod/Email::Valid).

uri
: Optional URI for the user. Should be a valid URI as verified by
  [Data::Validate::URI](https://metacpan.org/pod/Data::Validate::URI).

twitter
: Optional Twitter username. Case-insensitive. A leading "@" will be removed.

why
: Optional text from the user explaining why she should be allowed access.

Returns true if the user was inserted, and false if not.

*/
BEGIN
    IF char_length(password) < 8 THEN
       RAISE EXCEPTION 'Password must be at least eight characters long';
    END IF;
    INSERT INTO users (
        nickname,
        password,
        full_name,
        email,
        uri,
        twitter,
        why,
        set_by
    )
    VALUES (
        insert_user.nickname,
        crypt(insert_user.password, _salt()),
        COALESCE(insert_user.full_name, ''),
        insert_user.email,
        insert_user.uri,
        COALESCE(trim(leading '@' FROM insert_user.twitter), ''),
        COALESCE(insert_user.why, ''),
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
       SET password       = crypt(newpass, _salt()),
           updated_at     = NOW()
     WHERE users.nickname = change_password.nickname
       AND users.password = crypt(oldpass, password)
       AND users.status   = 'active';
    RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION update_user(
    nickname   LABEL,
    full_name  TEXT   DEFAULT NULL,
    email      EMAIL  DEFAULT NULL,
    uri        URI    DEFAULT NULL,
    twitter    CITEXT DEFAULT NULL
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
/*

    % SELECT update_user(
        nickname  := 'theory',
        full_name := 'David E. Wheeler',
        email     := 'justatheory@pgxn.org',
        uri       := 'https://www.justatheory.com/',
        twitter   :- 'theory'
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
  [Email::Valid](https://metacpan.org/pod/Email::Valid).

uri
: Optional URI for the user. Should be a valid URI as verified by
  [Data::Validate::URI](https://metacpan.org/pod/Data::Validate::URI).

twitter
: Optional Twitter username. A leading "@" wil be removed.

Returns true if the user was updated, and false if not.

*/
BEGIN
    UPDATE users
       SET full_name      = COALESCE(update_user.full_name, users.full_name),
           email          = COALESCE(update_user.email,     users.email),
           uri            = COALESCE(update_user.uri,       users.uri),
           twitter        = COALESCE(trim(leading '@' FROM update_user.twitter), users.twitter),
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
) RETURNS BOOLEAN LANGUAGE plpgsql VOLATILE SECURITY DEFINER AS $$
/*

    % select authenticate_user('admin', '*****');
     authenticate_user
    ────────────────
     t

Returns true if the user with the specified nickname exists, is active, and
the password matches. Also updates the value of the `visited_at` column for
the user to the current timestamp. Returns false if the nickname and password
don't match or the user is not active.

*/
BEGIN
    UPDATE users
       SET visited_at     = NOW()
     WHERE users.nickname = authenticate_user.nickname
       AND status         = 'active'
       AND users.password = crypt(authenticate_user.password, users.password);
    RETURN FOUND;
END;
$$;

COMMIT;