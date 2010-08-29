-- sql/1283039854-ownership.sql SQL Migration

CREATE OR REPLACE FUNCTION is_admin_or_owns(
    nick          LABEL,
    VARIADIC exts TEXT[]
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

CREATE OR REPLACE FUNCTION insert_coowner(
    owner         LABEL,
    coowner       LABEL,
    VARIADIC exts TEXT[]
) RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER AS $$
BEGIN
-- Can be done by admin or owner.
END;
$$;

CREATE OR REPLACE FUNCTION delete_coowner(
    owner         LABEL,
    coowner       LABEL,
    VARIADIC exts TEXT[]
) RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER AS $$
BEGIN
-- Can be done by admin, owner, or coowner (to self)
END;
$$;

CREATE OR REPLACE FUNCTION transfer_ownership(
    owner         LABEL,
    coowner       LABEL,
    VARIADIC exts TEXT[]
) RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER AS $$
BEGIN
-- Can be done by admin or owner.
END;
$$;

