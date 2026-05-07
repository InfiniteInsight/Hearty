import { z } from 'zod';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { supabase, getUserId } from '../supabase.js';
import { getHealthProfileContext } from '../context.js';

export function registerGetTrends(server: McpServer): void {
  server.registerTool(
    'get_trends',
    {
      description:
        'Run trend analysis to identify likely food triggers and symptom patterns. Returns a ranked list of food-symptom correlations. Call when the user asks about patterns, triggers, or what\'s been causing issues.',
      inputSchema: {
        analysis_period_days: z.number().optional().describe('Number of days to analyze. Default: 30.'),
        focus_symptom: z.string().optional().describe('Narrow the analysis to a specific symptom type. If omitted, analyzes all symptoms.'),
        min_occurrences: z.number().optional().describe('Minimum number of co-occurrences required. Default: 2.'),
      },
    },
    async (args) => {
      try {
        const userId = getUserId();

        const minOccurrences = args.min_occurrences ?? 2;
        let query = supabase
          .from('food_triggers')
          .select('food_name, symptom_type, confidence_score, avg_severity, avg_onset_minutes, occurrence_count, last_updated')
          .eq('user_id', userId)
          .gte('occurrence_count', minOccurrences)
          .order('confidence_score', { ascending: false });

        if (args.focus_symptom) {
          query = query.eq('symptom_type', args.focus_symptom);
        }

        const { data: triggers, error } = await query;
        if (error) throw error;

        const now = new Date();
        const hasFreshData = triggers && triggers.length > 0 &&
          triggers.some(t => t.last_updated && (now.getTime() - new Date(t.last_updated).getTime()) < 24 * 60 * 60 * 1000);

        type TrendsResult = { triggers: []; note: string } | { triggers: Record<string, unknown>[] };
        let result: TrendsResult;
        if (!hasFreshData) {
          result = {
            triggers: [],
            note: 'Trend analysis not yet available — will activate once food intelligence (Spec 07) is deployed.',
          };
        } else {
          result = { triggers };
        }

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
