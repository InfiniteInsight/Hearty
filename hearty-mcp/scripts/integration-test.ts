/**
 * Hearty MCP Server — Integration Test Script
 *
 * Tests all 6 tool handler database operations against a real Supabase instance.
 * Run with: node --env-file=.env --import tsx/esm scripts/integration-test.ts
 */

import { supabase, getUserId } from '../src/supabase.js';

const userId = getUserId();

console.log('Running Hearty MCP integration tests...\n');

// ─── Test 1: log_meal ──────────────────────────────────────────────────────
const { data: mealData, error: mealError } = await supabase
  .from('meals')
  .insert({
    user_id: userId,
    description: 'integration test meal — grilled salmon with rice',
    meal_type: 'dinner',
    foods: [{ name: 'grilled salmon' }, { name: 'rice' }],
    logged_at: new Date().toISOString(),
    input_method: 'text',
  })
  .select('id')
  .single();

if (mealError) throw new Error(`Test 1 FAIL: ${mealError.message}`);
const mealId = mealData.id;
console.log(`Test 1 PASS: meal_id=${mealId}`);

// ─── Test 2: log_symptoms ──────────────────────────────────────────────────
const { error: symptomError } = await supabase
  .from('symptoms')
  .insert({
    user_id: userId,
    meal_id: mealId,
    onset_minutes: 30,
    raw_description: 'mild bloating after salmon',
    symptom_type: 'bloating',
    severity: 3,
    logged_at: new Date().toISOString(),
  });

if (symptomError) throw new Error(`Test 2 FAIL: ${symptomError.message}`);
console.log('Test 2 PASS: symptom inserted');

// ─── Test 3: log_wellbeing ─────────────────────────────────────────────────
const { data: wbData, error: wbError } = await supabase
  .from('wellbeing_snapshots')
  .insert({
    user_id: userId,
    energy_level: 7,
    mood: 8,
    sleep_hours: 7.5,
    notes: 'integration test snapshot',
    logged_at: new Date().toISOString(),
  })
  .select('id')
  .single();

if (wbError) throw new Error(`Test 3 FAIL: ${wbError.message}`);
console.log(`Test 3 PASS: snapshot_id=${wbData.id}`);

// ─── Test 4: query_history ─────────────────────────────────────────────────
const { data: historyData, error: historyError } = await supabase
  .from('meals')
  .select('id, description, symptoms(symptom_type, severity)')
  .eq('user_id', userId)
  .ilike('description', '%salmon%')
  .limit(5);

if (historyError) throw new Error(`Test 4 FAIL: ${historyError.message}`);
const found = historyData?.some(m => m.id === mealId);
if (!found) throw new Error(`Test 4 FAIL: inserted meal not found in query`);
console.log(`Test 4 PASS: found meal in query_history`);

// ─── Test 5: get_trends (food_triggers) ───────────────────────────────────
const { data: triggersData, error: triggersError } = await supabase
  .from('food_triggers')
  .select('food_name, symptom_type, confidence_score')
  .eq('user_id', userId)
  .limit(5);

if (triggersError) throw new Error(`Test 5 FAIL: ${triggersError.message}`);
// Empty is expected — Spec 07 (trigger analysis) not deployed yet
console.log(`Test 5 PASS: food_triggers query ok, ${triggersData?.length ?? 0} triggers`);

// ─── Test 6: get_summary (aggregate count) ────────────────────────────────
const { count, error: summaryError } = await supabase
  .from('meals')
  .select('id', { count: 'exact', head: true })
  .eq('user_id', userId);

if (summaryError) throw new Error(`Test 6 FAIL: ${summaryError.message}`);
console.log(`Test 6 PASS: meal_count=${count}`);

// ─── Test 7: error handling — missing HEARTY_USER_ID ─────────────────────
const savedId = process.env.HEARTY_USER_ID;
delete process.env.HEARTY_USER_ID;

let errorHandlingOk = false;
try {
  getUserId(); // should throw
} catch (err) {
  errorHandlingOk = err instanceof Error && err.message.includes('HEARTY_USER_ID must be set');
}

process.env.HEARTY_USER_ID = savedId;
if (!errorHandlingOk) throw new Error('Test 7 FAIL: getUserId() did not throw as expected');
console.log('Test 7 PASS: error handling works');

// ─── All tests passed ─────────────────────────────────────────────────────
console.log('\nAll 7 tests passed ✓');

// ─── Cleanup ──────────────────────────────────────────────────────────────
console.log('\nCleaning up test data...');
await supabase.from('symptoms').delete().eq('meal_id', mealId);
await supabase.from('meals').delete().ilike('description', '%integration test%');
await supabase.from('wellbeing_snapshots').delete().eq('notes', 'integration test snapshot').eq('user_id', userId);
console.log('Cleanup complete');
