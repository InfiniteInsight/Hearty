-- Shared, server-side food-nutrition cache (NOT user-scoped — nutrition data is
-- public and shared across users). Written/read only by the service-key client;
-- RLS is enabled with no policies so it is never reachable via the Data API.
CREATE TABLE food_cache (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lookup_key     TEXT NOT NULL UNIQUE,
  source         TEXT NOT NULL,
  nutrition_data JSONB NOT NULL,
  cached_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  ttl_days       INT NOT NULL
);

-- (lookup_key is UNIQUE, which already creates the index used for cache lookups.)

ALTER TABLE food_cache ENABLE ROW LEVEL SECURITY;
-- No policies: only the service-role key (which bypasses RLS) touches this table.
