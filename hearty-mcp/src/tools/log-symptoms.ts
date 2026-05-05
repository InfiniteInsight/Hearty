import { z } from 'zod';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { supabase, getUserId } from '../supabase.js';
import { getHealthProfileContext } from '../context.js';

export function registerLogSymptoms(server: McpServer): void {
  server.registerTool(
    'log_symptoms',
    {
      description:
        'Log one or more physical symptoms. Call this whenever the user mentions how they feel after eating, or any GI or systemic symptoms. Always capture onset_minutes and severity if possible.',
      inputSchema: {
        symptoms: z.array(z.object({
          symptom_type: z.enum([
            'acid_reflux', 'bloating', 'gas', 'nausea', 'urgency',
            'loose_stool', 'constipation', 'stomach_pain', 'cramping',
            'fatigue', 'brain_fog', 'headache', 'skin_reaction',
            'heart_palpitations', 'other',
          ]).describe('Type of symptom'),
          severity: z.number().optional().describe('Severity 1-10.'),
          duration_minutes: z.number().optional().describe('How long the symptom lasted.'),
          bathroom_urgency: z.number().optional().describe('Bathroom urgency 0-5.'),
          bathroom_visits: z.number().optional().describe('Number of bathroom trips.'),
          stool_consistency: z.number().optional().describe('Bristol Stool Scale 1-7.'),
        })).describe('Structured list of individual symptoms.'),
        meal_id: z.string().optional().describe('UUID of the most recently logged meal, if symptoms are related.'),
        onset_minutes: z.number().optional().describe('How many minutes after the meal the symptoms appeared.'),
        raw_description: z.string().optional().describe("The user's own words describing how they feel. Preserve verbatim."),
        notes: z.string().optional().describe('Additional context.'),
        logged_at: z.string().optional().describe('ISO 8601 timestamp. Defaults to now.'),
      },
    },
    async (args) => {
      try {
        const userId = getUserId();

        const loggedAt = args.logged_at ?? new Date().toISOString();
        const rows = args.symptoms.map(s => ({
          user_id: userId,
          meal_id: args.meal_id ?? null,
          onset_minutes: args.onset_minutes ?? null,
          raw_description: args.raw_description ?? null,
          notes: args.notes ?? null,
          logged_at: loggedAt,
          symptom_type: s.symptom_type,
          severity: s.severity ?? null,
          duration_minutes: s.duration_minutes ?? null,
          bathroom_urgency: s.bathroom_urgency ?? null,
          bathroom_visits: s.bathroom_visits ?? null,
          stool_consistency: s.stool_consistency ?? null,
        }));

        const { error } = await supabase.from('symptoms').insert(rows);
        if (error) throw error;

        const symptomTypes = args.symptoms.map(s => s.symptom_type);
        const { data: triggers } = await supabase
          .from('food_triggers')
          .select('food_name, symptom_type, confidence_score, occurrences')
          .eq('user_id', userId)
          .in('symptom_type', symptomTypes)
          .order('confidence_score', { ascending: false })
          .limit(5);
        const triggerWarnings = triggers ?? [];

        const context = await getHealthProfileContext(userId);
        const result = { success: true, inserted: args.symptoms.length, trigger_warnings: triggerWarnings };

        return {
          content: [
            { type: 'text' as const, text: JSON.stringify(result) },
            ...(context ? [{ type: 'text' as const, text: context }] : []),
          ],
        };
      } catch (err) {
        const message = err instanceof Error ? err.message : 'Unknown error';
        return {
          content: [
            {
              type: 'text' as const,
              text: JSON.stringify({
                success: false,
                error: message,
                hint: 'Check SUPABASE_URL, SUPABASE_SERVICE_KEY, and HEARTY_USER_ID in your MCP env config.',
              }),
            },
          ],
          isError: true,
        };
      }
    }
  );
}
