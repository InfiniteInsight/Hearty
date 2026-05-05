import { z } from 'zod';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { supabase, getUserId } from '../supabase.js';
import { getHealthProfileContext } from '../context.js';

export function registerGetSummary(server: McpServer): void {
  server.registerTool(
    'get_summary',
    {
      description:
        "Get a natural language summary of the user's recent health patterns, top symptoms, and identified triggers for a given time period. Use for weekly reviews or when the user asks 'how have I been doing?'",
      inputSchema: {
        period: z.enum(['week', 'month', 'custom']).optional().describe("Time period to summarize. Use 'custom' with start_date and end_date."),
        start_date: z.string().optional().describe("Required if period is 'custom'. ISO 8601 date string."),
        end_date: z.string().optional().describe("Required if period is 'custom'. ISO 8601 date string."),
      },
    },
    async (args) => {
      try {
        const userId = getUserId();

        const now = new Date();
        let startDate: string;
        let endDate: string = now.toISOString();

        const period = args.period ?? 'week';
        if (period === 'week') {
          startDate = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000).toISOString();
        } else if (period === 'month') {
          startDate = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000).toISOString();
        } else {
          // custom
          if (!args.start_date || !args.end_date) {
            throw new Error("start_date and end_date are required when period is 'custom'.");
          }
          startDate = args.start_date;
          endDate = args.end_date;
        }

        const [mealsResult, symptomsResult, triggersResult, wellbeingResult] = await Promise.all([
          supabase
            .from('meals')
            .select('id', { count: 'exact', head: true })
            .eq('user_id', userId)
            .gte('logged_at', startDate)
            .lte('logged_at', endDate),

          supabase
            .from('symptoms')
            .select('symptom_type')
            .eq('user_id', userId)
            .gte('logged_at', startDate)
            .lte('logged_at', endDate),

          supabase
            .from('food_triggers')
            .select('food_name, symptom_type, confidence_score')
            .eq('user_id', userId)
            .order('confidence_score', { ascending: false })
            .limit(5),

          supabase
            .from('wellbeing_snapshots')
            .select('energy_level, mood, stress_level, sleep_hours, sleep_quality')
            .eq('user_id', userId)
            .gte('logged_at', startDate)
            .lte('logged_at', endDate),
        ]);

        if (mealsResult.error) throw mealsResult.error;
        if (symptomsResult.error) throw symptomsResult.error;
        if (triggersResult.error) throw triggersResult.error;
        if (wellbeingResult.error) throw wellbeingResult.error;

        // Symptom frequency
        const symptomFrequency: Record<string, number> = {};
        for (const row of symptomsResult.data ?? []) {
          symptomFrequency[row.symptom_type] = (symptomFrequency[row.symptom_type] ?? 0) + 1;
        }

        // Wellbeing averages
        const wb = wellbeingResult.data ?? [];
        const avg = (key: keyof typeof wb[0]) => {
          const vals = wb.map(r => r[key]).filter((v): v is number => v !== null && v !== undefined);
          return vals.length ? vals.reduce((a, b) => a + b, 0) / vals.length : null;
        };
        const wellbeingAverages = {
          energy_level: avg('energy_level'),
          mood: avg('mood'),
          stress_level: avg('stress_level'),
          sleep_hours: avg('sleep_hours'),
          sleep_quality: avg('sleep_quality'),
        };

        const result = {
          period,
          start_date: startDate,
          end_date: endDate,
          meal_count: mealsResult.count ?? 0,
          symptom_frequency: symptomFrequency,
          top_triggers: triggersResult.data ?? [],
          wellbeing_averages: wellbeingAverages,
        };

        const context = await getHealthProfileContext(userId);
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
