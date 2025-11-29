-- PostgreSQL 17 added json_value() and made "json" a reserved word. The
-- following scripts were updated to be compatible; we re-run them here to
-- update existing databases.

\i sql/07-json.sql
\i sql/10-json_data.sql
\i sql/11-dist_management.sql
\i sql/15-dist_processing.sql
\i sql/19-tag-stats-json.sql
