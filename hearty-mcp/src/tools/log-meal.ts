import { z } from 'zod';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { supabase, getUserId } from '../supabase.js';
import { getHealthProfileContext } from '../context.js';

export function registerLogMeal(server: McpServer): void {
  server.registerTool(
    'log_meal',
    {
      description:
        'Log a meal, snack, drink, or supplement the user just consumed or is about to consume. Call this immediately whenever the user describes eating or drinking anything — do not wait for an explicit \'log this\' command.',
      inputSchema: {
        description: z.string().describe('Natural language description of the meal exactly as the user described it. Preserve their words.'),
        meal_type: z.enum(['breakfast', 'lunch', 'dinner', 'snack', 'drink', 'supplement', 'other']).optional().describe('Type of meal. Infer from context if not stated.'),
        foods: z.array(z.object({
          name: z.string().describe('Food item name'),
          quantity: z.string().optional().describe("Amount or serving size, e.g. '1 cup', '2 slices'"),
          estimated_calories: z.number().optional().describe('Best-effort calorie estimate. Omit if unknown.'),
          preparation: z.string().optional().describe("Cooking method if relevant, e.g. 'grilled', 'fried'"),
        })).optional().describe('Parsed list of individual food items extracted from the description.'),
        location: z.string().optional().describe("Where the meal was eaten. 'home', restaurant name, etc."),
        mood_before: z.number().optional().describe('User\'s mood rating 1-10 before eating.'),
        hunger_before: z.number().optional().describe('Hunger level 1-10 before eating.'),
        logged_at: z.string().optional().describe('ISO 8601 timestamp. Defaults to now if not specified.'),
        input_method: z.enum(['voice', 'text', 'photo', 'barcode']).optional().describe("How the meal was described. Default: 'text' for MCP."),
        offline_id: z.string().optional().describe('Client-generated UUID for deduplication if logging from offline queue.'),
        notes: z.string().optional().describe('Any additional context about the meal.'),
      },
    },
    async (args) => {
      try {
        const userId = getUserId();

        const { data, error } = await supabase
          .from('meals')
          .insert({
            user_id: userId,
            description: args.description,
            meal_type: args.meal_type ?? null,
            foods: args.foods ?? [],
            location: args.location ?? null,
            mood_before: args.mood_before ?? null,
            hunger_before: args.hunger_before ?? null,
            logged_at: args.logged_at ?? new Date().toISOString(),
            input_method: args.input_method ?? 'text',
            offline_id: args.offline_id ?? null,
            notes: args.notes ?? null,
          })
          .select('id')
          .single();

        if (error) throw error;

        const context = await getHealthProfileContext(userId);
        const result = { success: true, meal_id: data.id, summary: args.description };

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
