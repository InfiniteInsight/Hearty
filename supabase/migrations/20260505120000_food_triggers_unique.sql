-- Add unique constraint on food_triggers(user_id, food_name, symptom_type)
-- Required for upsert in trend_engine.update_food_triggers_table.
ALTER TABLE food_triggers
  ADD CONSTRAINT food_triggers_user_food_symptom_key UNIQUE (user_id, food_name, symptom_type);
