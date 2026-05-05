-- Add flat per-symptom columns to match MCP server spec (Spec 02)
-- The initial schema stored symptoms as JSONB structured_data + severity_overall.
-- The MCP server spec defines flat columns per symptom row for easier querying.

ALTER TABLE symptoms
  ALTER COLUMN raw_description DROP NOT NULL,
  ADD COLUMN IF NOT EXISTS symptom_type       TEXT,
  ADD COLUMN IF NOT EXISTS severity           INT CHECK (severity BETWEEN 1 AND 10),
  ADD COLUMN IF NOT EXISTS duration_minutes   INT,
  ADD COLUMN IF NOT EXISTS bathroom_urgency   INT CHECK (bathroom_urgency BETWEEN 0 AND 5),
  ADD COLUMN IF NOT EXISTS bathroom_visits    INT,
  ADD COLUMN IF NOT EXISTS stool_consistency  INT CHECK (stool_consistency BETWEEN 1 AND 7);

CREATE INDEX IF NOT EXISTS idx_symptoms_user_type ON symptoms (user_id, symptom_type);
