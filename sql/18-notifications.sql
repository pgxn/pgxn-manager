BEGIN;

CREATE OR REPLACE FUNCTION notify_release(
) RETURNS trigger AS $$
BEGIN
    PERFORM pgxn_notify('release', NEW.meta);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER notify_release
  AFTER INSERT ON distributions
  FOR EACH ROW
  EXECUTE PROCEDURE notify_release();

CREATE OR REPLACE FUNCTION notify_new_user(
) RETURNS trigger AS $$
BEGIN
    PERFORM pgxn_notify('new_user', json_build_object(
      'nickname',  NEW.nickname,
      'full_name', NEW.full_name,
      'email',     NEW.email,
      'uri',       NEW.uri,
      'why',       NEW.why,
      'social',    json_build_object('twitter', NEW.twitter)
    )::text);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER notify_new_user
  AFTER UPDATE ON users
  FOR EACH ROW
  WHEN (OLD.status = 'new' AND NEW.status = 'active')
  EXECUTE PROCEDURE notify_new_user();

CREATE OR REPLACE FUNCTION notify_new_mirror(
) RETURNS trigger AS $$
BEGIN
    PERFORM pgxn_notify('new_mirror', json_build_object(
      'uri',          NEW.uri,
      'frequency',    NEW.frequency,
      'location',     NEW.location,
      'organization', NEW.organization,
      'timezone',     NEW.timezone,
      'contact',      NEW.email,
      'bandwidth',    NEW.bandwidth,
      'src',          NEW.src,
      'rsync',        NEW.rsync,
      'notes',        NEW.notes
    )::text);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER notify_new_mirror
  AFTER INSERT ON mirrors
  FOR EACH ROW
  EXECUTE PROCEDURE notify_new_mirror();

COMMIT;
