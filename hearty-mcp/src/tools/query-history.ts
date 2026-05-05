import { z } from 'zod';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { supabase, getUserId } from '../supabase.js';

export function registerQueryHistory(server: McpServer): void {
  server.registerTool(
    'query_history',
    {
      description:
        "Query past meals and symptoms. Call when the user asks 'what did I eat last week', 'when did I last have acid reflux', 'show me everything after I ate gluten', etc.",
      inputSchema: {
        start_date: z.string().optional().describe('ISO 8601 date string for the start of the query window. Defaults to 7 days ago.'),
        end_date: z.string().optional().describe('ISO 8601 date string for the end of the query window. Defaults to now.'),
        symptom_type: z.string().optional().describe("Filter to a specific symptom type, e.g. 'acid_reflux', 'bloating'."),
        food_keyword: z.string().optional().describe("Keyword to search meal descriptions and food items, e.g. 'pizza', 'dairy'."),
        limit: z.number().optional().describe('Maximum number of records to return. Default: 20.'),
      },
    },
    async (args) => {
      try {
        const userId = getUserId();

        const endDate = args.end_date ?? new Date().toISOString();
        const startDate = args.start_date ?? new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
        const limit = args.limit ?? 20;

        let query = supabase
          .from('meals')
          .select(`
            id, description, meal_type, foods, location, logged_at, input_method, notes,
            symptoms (
              id, symptom_type, severity, onset_minutes, duration_minutes,
              bathroom_urgency, bathroom_visits, stool_consistency, logged_at
            )
          `)
          .eq('user_id', userId)
          .gte('logged_at', startDate)
          .lte('logged_at', endDate)
          .order('logged_at', { ascending: false })
          .limit(limit);

        if (args.symptom_type) {
          query = query.filter('symptoms.symptom_type', 'eq', args.symptom_type);
        }
        if (args.food_keyword) {
          query = query.or(`description.ilike.%${args.food_keyword}%,foods.cs.%${args.food_keyword}%`);
        }

        const { data, error } = await query;
        if (error) throw error;

        return {
          content: [{ type: 'text' as const, text: JSON.stringify({ meals: data ?? [], count: (data ?? []).length }) }],
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
