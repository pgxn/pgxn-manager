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

CREATE OR REPLACE FUNCTION add_coowner(
    nick    LABEL,
    coowner LABEL,
    exts    TEXT[]
) RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER AS $$
/*

    SELECT insert_cowoner('theory', 'strongrrl', ARRAY['pair', 'pgtap']);

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

CREATE OR REPLACE FUNCTION remove_coowner(
    owner   LABEL,
    coowner LABEL,
    exts    TEXT[]
) RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER AS $$
BEGIN
-- Can be done by admin, owner, or coowner (to self)
END;
$$;

CREATE OR REPLACE FUNCTION transfer_ownership(
    owner   LABEL,
    coowner LABEL,
    exts    TEXT[]
) RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER AS $$
BEGIN
-- Can be done by admin or owner.
END;
$$;

