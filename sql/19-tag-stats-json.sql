-- sql/19-tag-stats-json.sql SQL Migration

SET client_min_messages TO warning;

BEGIN;

CREATE OR REPLACE FUNCTION tag_stats_json(
    num_popular INT DEFAULT 56
) RETURNS TEXT LANGUAGE sql STABLE STRICT AS $$
/*

    % select tag_stats_json(4);
                    tag_stats_json
    ──────────────────────────────────────────────
     {                                           ↵
        "count": 212,                            ↵
        "popular": [                             ↵
           {"tag": "data types", "dists": 4},    ↵
           {"tag": "key value", "dists": 2},     ↵
           {"tag": "france", "dists": 1},        ↵
           {"tag": "key value pair", "dists": 1} ↵
        ]                                        ↵
     }                                           ↵

Returns a JSON representation of tag statistics. These include:

* `count`: A count of all tags in the database.
* `popular`: A list of the most used tags in the system, listed in descending
  order by the number of uses.

Since tags are case-insensitive, `tag_stats_json()` returns lowercases tag
names.

Pass in the optional `num_popular` parameter to limit the number of tags that
appear in the popular list. The default limit is 56.

*/
    SELECT E'{\n   "count": ' || COUNT(DISTINCT tag) || E',\n   "popular": [\n'
        || array_to_string(ARRAY(
        SELECT '      {"tag": ' || json_value(LOWER(tag))
            || ', "dists": ' || COUNT(DISTINCT distribution) || E'}'
          FROM distribution_tags
         GROUP BY tag
         ORDER BY COUNT(DISTINCT distribution) DESC, tag
         LIMIT $1
        ), E',\n') || E'\n   ]\n}\n'
      FROM distribution_tags
$$;

COMMIT;
