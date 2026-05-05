import { z } from 'zod';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { supabase, getUserId } from '../supabase.js';
import { getHealthProfileContext } from '../context.js';

export function registerLogWellbeing(server: McpServer): void {
  server.registerTool(
    'log_wellbeing',
    {
      description:
        'Log a general wellbeing snapshot: energy, mood, stress, sleep, hydration, and exercise. Use for morning check-ins, daily reviews, or when the user gives an overall status update.',
      inputSchema: {
        energy_level: z.number().optional().describe('Energy level 1-10.'),
        mood: z.number().optional().describe('Mood 1-10.'),
        stress_level: z.number().optional().describe('Stress level 1-10. Higher = more stressed.'),
        sleep_hours: z.number().optional().describe('Hours of sleep last night.'),
        sleep_quality: z.number().optional().describe('Sleep quality 1-10.'),
        hydration: z.number().optional().describe('Hydration level 1-10 (subjective estimate).'),
        exercise_minutes: z.number().optional().describe('Minutes of exercise today.'),
        notes: z.string().optional().describe("Any free-form notes about today's general state."),
        logged_at: z.string().optional().describe('ISO 8601 timestamp. Defaults to now.'),
      },
    },
    async (args) => {
      try {
        const userId = getUserId();

        const { data, error } = await supabase
          .from('wellbeing_snapshots')
          .insert({
            user_id: userId,
            energy_level: args.energy_level ?? null,
            mood: args.mood ?? null,
            stress_level: args.stress_level ?? null,
            sleep_hours: args.sleep_hours ?? null,
            sleep_quality: args.sleep_quality ?? null,
            hydration: args.hydration ?? null,
            exercise_minutes: args.exercise_minutes ?? null,
            notes: args.notes ?? null,
            logged_at: args.logged_at ?? new Date().toISOString(),
          })
          .select('id')
          .single();

        if (error) throw error;

        const context = await getHealthProfileContext(userId);
        const result = { success: true, snapshot_id: data.id };

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
