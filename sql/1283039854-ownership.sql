-- sql/1283039854-ownership.sql SQL Migration

CREATE OR REPLACE FUNCTION is_admin_or_owns(
    nick LABEL,
    exts TEXT[]
) RETURNS BOOLEAN LANGUAGE plpgsql STABLE AS $$
DECLARE
    ret BOOLEAN;
BEGIN
    -- Admins can just do it.
    PERFORM true FROM users WHERE nickname = nick AND is_admin;
    IF FOUND THEN RETURN TRUE; END IF;

    -- Permission granted only if the user owns all extensions.
    SELECT bool_and(COALESCE(owner = nick, FALSE))
      INTO ret
      FROM unnest(exts) AS ext
      LEFT JOIN extensions e ON ext = e.name;
    RETURN COALESCE(ret, false);
END;
$$;

-- Disallow end-user from using this function.
REVOKE ALL ON FUNCTION is_admin_or_owns(LABEL, TEXT[]) FROM PUBLIC;

CREATE OR REPLACE FUNCTION grant_coownership(
    nick    LABEL,
    coowner LABEL,
    exts    TEXT[]
) RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER AS $$
/*

    SELECT grant_coownership('theory', 'strongrrl', ARRAY['pair', 'pgtap']);

Grants co-ownership to one or more extensions. The first argument is the
nickname of the uesr inserting the co-owner. Said user must either be and
admin or own *all* of the specified extensions. The second argument is the
nickname of the user being granted co-ownership. This name must not be the
same name as the owner. The third argument is an array of the names of the
extensions to which co-ownership is to be granted.

*/
BEGIN
    IF NOT is_admin_or_owns(nick, exts) THEN
        RAISE EXCEPTION 'User “%” does not have permission to grant co-ownership to “%”',
            nick, array_to_string(exts, '”, “');
    END IF;

    -- Grant only if the target is not already owner or co-owner.
    INSERT INTO coowners (extension, nickname)
    SELECT e.name, coowner
      FROM extensions e
      LEFT JOIN coowners c ON e.name = c.extension AND c.nickname = coowner
     WHERE e.name     = ANY(exts)
       AND e.owner    <> coowner
       AND c.nickname IS NULL;

    RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION revoke_coownership(
    nick    LABEL,
    coowner LABEL,
    exts    TEXT[]
) RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER AS $$
/*

    SELECT revoke_coownership('theory', 'strongrrl', ARRAY['pair', 'pgtap']);

Remove co-ownership permission to the specified extensions. The first argument
is the nickname of the user removing co-ownership. Said user must either be
and admin, own *all* of the specified extensions, or be removing co-ownership
from itself. The second argument is the nickname of the user being for whom
co-ownership is being removed. The third argument is an array of the names of
the extensions from which co-ownership is to be removed.

*/
BEGIN
    IF NOT is_admin_or_owns(nick, exts) AND nick <> coowner THEN
        RAISE EXCEPTION 'User “%” does not have permission to revoke co-ownership from “%”',
            nick, array_to_string(exts, '”, “');
    END IF;

    DELETE FROM coowners
     WHERE nickname = coowner
       AND extension = ANY(exts);

    RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION transfer_ownership(
    nick     LABEL,
    newowner LABEL,
    exts     TEXT[]
) RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER AS $$
/*

    SELECT transfer_ownership('theory', 'strongrrl', ARRAY['pair', 'pgtap']);

Transfer ownership of the specified extensions to a new owner. The first
argument is the nickname of the uesr performing the transfer. Said user must
either be and admin or own *all* of the specified extensions. The second
argument is the nickname of the user being given ownership. This name must not
be the same name as the owner. The third argument is an array of the names of
the extensions to which ownership is to be transfered.

*/
BEGIN
    IF NOT is_admin_or_owns(nick, exts) THEN
        RAISE EXCEPTION 'User “%” does not have permission to transfer ownership of “%”',
            nick, array_to_string(exts, '”, “');
    END IF;

    -- Remove any co-ownerships.
    DELETE FROM coowners
     WHERE nickname  = newowner
       AND extension = ANY(exts);

    -- Make the new guy the boss.
    UPDATE extensions
       SET owner      = newowner,
           updated_at = NOW()
     WHERE name       = ANY(exts)
       AND owner     <> newowner;

    RETURN FOUND;
END;
$$;
