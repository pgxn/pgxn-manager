CREATE OR REPLACE FUNCTION pgxn_notify(
  channel text,
  payload text
) RETURNS void LANGUAGE sql AS $$ SELECT pg_notify('pgxn_' || $1, $2) $$
