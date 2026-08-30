-- sql/22-distview.sql SQL Migration

SET client_min_messages TO warning;

BEGIN;

CREATE OR REPLACE VIEW distribution_details AS
SELECT d.name, d.version, d.abstract, d.description, d.relstatus, d.creator,
       d.sha1, d.meta,
       array_agg(
       DISTINCT ARRAY[de.extension, de.ext_version]::citext[]
          ORDER BY ARRAY[de.extension, de.ext_version]::citext[]
       )::text[] AS extensions,
       -- I sure wish you could make array_agg() exclude NULLs.
       ARRAY(
           SELECT x
             FROM unnest(array_agg(DISTINCT dt.tag::citext ORDER BY dt.tag::citext)) g(x)
            WHERE x IS NOT NULL
       ) AS tags
  FROM distributions d
  JOIN distribution_extensions de
    ON d.name    = de.distribution
   AND d.version = de.dist_version
  LEFT JOIN distribution_tags dt
    ON d.name    = dt.distribution
   AND d.version = dt.version
 GROUP BY d.name, d.version, d.abstract, d.description, d.relstatus, d.creator,
       d.sha1, d.meta;

GRANT SELECT ON distribution_details TO pgxn;
DROP AGGREGATE multi_array_agg ( text[] );

COMMIT;
