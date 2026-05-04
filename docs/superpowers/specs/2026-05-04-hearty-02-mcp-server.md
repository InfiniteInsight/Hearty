# Hearty — MCP Server Specification

**File:** `2026-05-04-hearty-02-mcp-server.md`
**Phase:** 1 — Core Infrastructure
**Related:** `2026-05-04-hearty-03-rest-api.md` (AI-agnostic REST access layer)

---

## 1. Overview

The Hearty MCP server is a Node.js process that users install into Claude Desktop, Claude Web, or any MCP-compatible Claude environment. It exposes a set of tools that Claude calls directly to log meals, symptoms, and wellbeing data, and to query patterns over time. All data is persisted to Supabase (PostgreSQL) via the Supabase JavaScript client. Auth is handled via a Supabase service-role key (or user JWT) passed through environment variables at install time.

This is the primary integration path for Claude users. Non-Claude AI assistants (Gemini, GPT, etc.) use the REST API instead — see `2026-05-04-hearty-03-rest-api.md`.

**Runtime:** Node.js 20+
**Language:** TypeScript
**SDK:** `@modelcontextprotocol/sdk` (latest)
**Database client:** `@supabase/supabase-js`

---

## 2. File Structure

```
hearty-mcp/
  src/
    index.ts            — entry point: server setup, tool registration, system prompt
    supabase.ts         — Supabase client initialization and auth helpers
    context.ts          — health profile context injection
    tools/
      log-meal.ts       — log_meal tool implementation
      log-symptoms.ts   — log_symptoms tool implementation
      log-wellbeing.ts  — log_wellbeing tool implementation
      query-history.ts  — query_history tool implementation
      get-trends.ts     — get_trends tool implementation
      get-summary.ts    — get_summary tool implementation
  package.json
  tsconfig.json
  .env.example
```

---

## 3. MCP Server Description (System Prompt)

This text is registered as the MCP server `description` so Claude internalizes the Hearty persona and behavioral rules on every session — the user never has to repeat context.

```
You are Hearty, a compassionate and precise personal health journal assistant.
Your primary job is to help the user track what they eat and how their body responds,
and to surface meaningful patterns between foods and physical symptoms over time.

IDENTITY & TONE:
- Warm, clinical, and never embarrassing. GI symptoms are normal health data.
- Precise with numbers and timestamps. Vague answers erode trust.
- One disclaimer at session start is enough. Never append "consult a doctor" to every response.
- Never diagnose. You can say "this food correlates with symptoms" — never "you have IBS."

AUTO-LOGGING BEHAVIOR:
- When the user mentions any food, drink, supplement, or meal — log it immediately
  using log_meal. Do not wait for an explicit "log this" command.
- After logging a meal, note that you will check back about symptoms. Follow up naturally
  30–90 minutes later in the conversation if the user has not mentioned symptoms.
- When logging symptoms, always capture: onset_minutes (how many minutes after eating),
  severity (1–10), and bathroom_urgency if relevant. Ask if not provided.
- If the user says something vague like "I feel terrible" or "rough afternoon," ask:
  "Is this related to something you ate? How's your stomach feeling?"

HEALTH PROFILE AWARENESS:
- Each tool call includes the user's health profile context: known allergens, intolerances,
  medical conditions, and dietary protocols. Use this to give richer, personalized responses.
- If the user logs a food that matches a known allergen or intolerance, flag it gently.
- Never reveal the health profile back verbatim — integrate it naturally into your analysis.

TREND AWARENESS:
- When the user logs a symptom, silently call get_trends or query_history to check if
  this pattern has appeared before. If it has, mention it:
  "I've seen acid reflux come up 3 other times after tomato-based meals."
- When the user asks about patterns or after sufficient data accumulates, offer a
  summary via get_summary unprompted.

SCOPE:
- Health-adjacent queries only. Food, symptoms, wellbeing, sleep, stress, exercise.
- If the user asks about something outside health journaling (news, coding help, general
  knowledge), acknowledge it and redirect gracefully: "That's a bit outside my lane as
  your health journal — you might get a better answer from a general assistant. Want to
  log anything health-related while you're here?"
- Never refuse to log something just because it seems unhealthy.

NEVER:
- Provide medical diagnoses or suggest specific medications or treatments.
- Add disclaimers to every single response — one per session is enough.
- Make the user retype context already captured in the database.
- Throw errors to the user for infrastructure failures — always return a graceful message.
```

---

## 4. Health Profile Context Injection

### 4.1 Purpose

Every tool call injects the user's health profile into the tool handler so Claude has personalized context for each response. This avoids the user having to repeat "I'm lactose intolerant" on every session.

### 4.2 `context.ts`

```typescript
// src/context.ts

import { supabase } from './supabase.js';

export interface HealthProfile {
  allergens: string[];           // e.g. ["peanuts", "shellfish"]
  intolerances: string[];        // e.g. ["lactose", "gluten"]
  conditions: string[];          // e.g. ["IBS-D", "GERD", "Crohn's"]
  dietary_protocols: string[];   // e.g. ["low-FODMAP", "AIP", "gluten-free"]
  notes: string | null;          // free-form context the user has added
}

export async function getHealthProfileContext(userId: string): Promise<string> {
  const { data, error } = await supabase
    .from('health_profile')
    .select('*')
    .eq('user_id', userId)
    .single();

  if (error || !data) return '';

  const profile: HealthProfile = data;
  const parts: string[] = [];

  if (profile.allergens?.length) {
    parts.push(`Known allergens: ${profile.allergens.join(', ')}.`);
  }
  if (profile.intolerances?.length) {
    parts.push(`Food intolerances: ${profile.intolerances.join(', ')}.`);
  }
  if (profile.conditions?.length) {
    parts.push(`Medical conditions: ${profile.conditions.join(', ')}.`);
  }
  if (profile.dietary_protocols?.length) {
    parts.push(`Dietary protocols: ${profile.dietary_protocols.join(', ')}.`);
  }
  if (profile.notes) {
    parts.push(`Additional context: ${profile.notes}`);
  }

  if (!parts.length) return '';

  return `\n\n[USER HEALTH PROFILE — use this context silently to enrich responses]\n${parts.join(' ')}\n`;
}
```

### 4.3 Injection Pattern

Each tool handler appends health profile context to its return payload as an additional text block. Claude reads it as part of the tool result.

```typescript
// Example pattern inside any tool handler
const context = await getHealthProfileContext(userId);
return {
  content: [
    { type: 'text', text: JSON.stringify(result) },
    ...(context ? [{ type: 'text', text: context }] : [])
  ]
};
```

---

## 5. Tool Specifications

### 5.1 `log_meal`

Logs a meal or food/drink event. Called automatically by Claude whenever the user mentions eating or drinking anything.

```typescript
{
  name: "log_meal",
  description: "Log a meal, snack, drink, or supplement the user just consumed or is about to consume. Call this immediately whenever the user describes eating or drinking anything — do not wait for an explicit 'log this' command.",
  inputSchema: {
    type: "object",
    properties: {
      description: {
        type: "string",
        description: "Natural language description of the meal exactly as the user described it. Preserve their words."
      },
      meal_type: {
        type: "string",
        enum: ["breakfast", "lunch", "dinner", "snack", "drink", "supplement", "other"],
        description: "Type of meal. Infer from context if not stated."
      },
      foods: {
        type: "array",
        description: "Parsed list of individual food items extracted from the description.",
        items: {
          type: "object",
          properties: {
            name: { type: "string", description: "Food item name" },
            quantity: { type: "string", description: "Amount or serving size, e.g. '1 cup', '2 slices'" },
            estimated_calories: { type: "number", description: "Best-effort calorie estimate. Omit if unknown." },
            preparation: { type: "string", description: "Cooking method if relevant, e.g. 'grilled', 'fried'" }
          },
          required: ["name"]
        }
      },
      location: {
        type: "string",
        description: "Where the meal was eaten. 'home', restaurant name, etc."
      },
      mood_before: {
        type: "number",
        description: "User's mood rating 1–10 before eating. Ask if not provided and relevant."
      },
      hunger_before: {
        type: "number",
        description: "Hunger level 1–10 before eating. Ask if not provided and relevant."
      },
      logged_at: {
        type: "string",
        description: "ISO 8601 timestamp of when the meal was eaten. Defaults to now if not specified."
      },
      input_method: {
        type: "string",
        enum: ["voice", "text", "photo", "barcode"],
        description: "How the meal was described. Default: 'text' for MCP."
      },
      offline_id: {
        type: "string",
        description: "Client-generated UUID for deduplication if logging from offline queue. Omit for real-time logs."
      },
      notes: {
        type: "string",
        description: "Any additional context about the meal."
      }
    },
    required: ["description"]
  }
}
```

**Handler behavior:**
1. Extract `userId` from the authenticated Supabase session.
2. Insert into `meals` table; capture returned `id`.
3. Inject health profile context into the response.
4. Return the new meal ID and a confirmation summary.

---

### 5.2 `log_symptoms`

Logs one or more physical symptoms. Called when the user mentions how they feel, especially after eating.

```typescript
{
  name: "log_symptoms",
  description: "Log one or more physical symptoms. Call this whenever the user mentions how they feel after eating, or any GI or systemic symptoms. Always capture onset_minutes and severity if possible.",
  inputSchema: {
    type: "object",
    properties: {
      meal_id: {
        type: "string",
        description: "UUID of the most recently logged meal, if the symptoms are likely related. Leave null if onset is unclear or unrelated to food."
      },
      onset_minutes: {
        type: "number",
        description: "How many minutes after the meal the symptoms appeared. Ask if not stated."
      },
      raw_description: {
        type: "string",
        description: "The user's own words describing how they feel. Preserve verbatim."
      },
      symptoms: {
        type: "array",
        description: "Structured list of individual symptoms extracted from raw_description.",
        items: {
          type: "object",
          properties: {
            symptom_type: {
              type: "string",
              enum: [
                "acid_reflux", "bloating", "gas", "nausea", "urgency",
                "loose_stool", "constipation", "stomach_pain", "cramping",
                "fatigue", "brain_fog", "headache", "skin_reaction",
                "heart_palpitations", "other"
              ]
            },
            severity: {
              type: "number",
              description: "Severity 1–10. Ask if not given."
            },
            duration_minutes: {
              type: "number",
              description: "How long the symptom lasted. Omit if ongoing."
            },
            bathroom_urgency: {
              type: "number",
              description: "Bathroom urgency 0–5 (0=none, 5=emergency). Include for urgency/loose_stool/diarrhea symptoms."
            },
            bathroom_visits: {
              type: "number",
              description: "Number of bathroom trips for this episode."
            },
            stool_consistency: {
              type: "number",
              description: "Bristol Stool Scale 1–7. Include only when bathroom symptoms are logged."
            }
          },
          required: ["symptom_type"]
        }
      },
      notes: {
        type: "string",
        description: "Additional context, e.g. whether the user took any medication."
      },
      logged_at: {
        type: "string",
        description: "ISO 8601 timestamp. Defaults to now."
      }
    },
    required: ["symptoms"]
  }
}
```

**Handler behavior:**
1. Insert each symptom in the `symptoms` array as a separate row in the `symptoms` table, all sharing the same `meal_id` and `onset_minutes`.
2. After inserting, query `food_triggers` for any trigger matching the symptom types logged — include in the response if patterns exist.
3. Inject health profile context.

---

### 5.3 `log_wellbeing`

Logs a general wellbeing snapshot. Useful for morning check-ins, end-of-day reviews, or when the user mentions overall condition.

```typescript
{
  name: "log_wellbeing",
  description: "Log a general wellbeing snapshot: energy, mood, stress, sleep, hydration, and exercise. Use for morning check-ins, daily reviews, or when the user gives an overall status update.",
  inputSchema: {
    type: "object",
    properties: {
      energy_level: {
        type: "number",
        description: "Energy level 1–10."
      },
      mood: {
        type: "number",
        description: "Mood 1–10."
      },
      stress_level: {
        type: "number",
        description: "Stress level 1–10. Higher = more stressed."
      },
      sleep_hours: {
        type: "number",
        description: "Hours of sleep last night."
      },
      sleep_quality: {
        type: "number",
        description: "Sleep quality 1–10."
      },
      hydration: {
        type: "number",
        description: "Hydration level 1–10 (subjective estimate)."
      },
      exercise_minutes: {
        type: "number",
        description: "Minutes of exercise today."
      },
      notes: {
        type: "string",
        description: "Any free-form notes about today's general state."
      },
      logged_at: {
        type: "string",
        description: "ISO 8601 timestamp. Defaults to now."
      }
    }
  }
}
```

---

### 5.4 `query_history`

Queries the user's meal and symptom history. Used when the user asks retrospective questions.

```typescript
{
  name: "query_history",
  description: "Query past meals and symptoms. Call when the user asks 'what did I eat last week', 'when did I last have acid reflux', 'show me everything after I ate gluten', etc.",
  inputSchema: {
    type: "object",
    properties: {
      start_date: {
        type: "string",
        description: "ISO 8601 date string for the start of the query window. Defaults to 7 days ago."
      },
      end_date: {
        type: "string",
        description: "ISO 8601 date string for the end of the query window. Defaults to now."
      },
      symptom_type: {
        type: "string",
        description: "Filter to a specific symptom type, e.g. 'acid_reflux', 'bloating'."
      },
      food_keyword: {
        type: "string",
        description: "Keyword to search meal descriptions and food items, e.g. 'pizza', 'dairy'."
      },
      limit: {
        type: "number",
        description: "Maximum number of records to return. Default: 20."
      }
    }
  }
}
```

**Handler behavior:**
- Joins `meals` with `symptoms` on `meal_id`.
- Applies `food_keyword` as a case-insensitive `ILIKE` on `meals.description` and `meals.foods` JSONB.
- Returns meals with their associated symptoms nested.

---

### 5.5 `get_trends`

Runs or retrieves trend analysis to identify food triggers and symptom patterns.

```typescript
{
  name: "get_trends",
  description: "Run trend analysis to identify likely food triggers and symptom patterns. Returns a ranked list of food-symptom correlations. Call when the user asks about patterns, triggers, or what's been causing issues.",
  inputSchema: {
    type: "object",
    properties: {
      analysis_period_days: {
        type: "number",
        description: "Number of days to analyze. Default: 30."
      },
      focus_symptom: {
        type: "string",
        description: "Narrow the analysis to a specific symptom type. If omitted, analyzes all symptoms."
      },
      min_occurrences: {
        type: "number",
        description: "Minimum number of co-occurrences required for a food-symptom pair to appear in results. Default: 2."
      }
    }
  }
}
```

**Handler behavior:**
- Reads from the `food_triggers` table (populated by the trend engine).
- If `food_triggers` is empty or stale (last_updated > 24h ago), triggers a fresh analysis via a Supabase RPC call to `run_trend_analysis(user_id)`.
- Returns ranked triggers with confidence scores, average severity, and average onset time.

---

### 5.6 `get_summary`

Returns a natural language health summary for a given period.

```typescript
{
  name: "get_summary",
  description: "Get a natural language summary of the user's recent health patterns, top symptoms, and identified triggers for a given time period. Use for weekly reviews or when the user asks 'how have I been doing?'",
  inputSchema: {
    type: "object",
    properties: {
      period: {
        type: "string",
        enum: ["week", "month", "custom"],
        description: "Time period to summarize. Use 'custom' with start_date and end_date."
      },
      start_date: {
        type: "string",
        description: "Required if period is 'custom'. ISO 8601 date string."
      },
      end_date: {
        type: "string",
        description: "Required if period is 'custom'. ISO 8601 date string."
      }
    }
  }
}
```

**Handler behavior:**
- Queries meal count, symptom frequency by type, top trigger foods, and wellbeing averages for the period.
- Returns structured JSON that Claude then synthesizes into a natural language narrative.
- Does not call an external LLM from the tool handler — Claude itself generates the narrative from the returned data.

---

## 6. Authentication

### 6.1 Configuration

The MCP server authenticates to Supabase using a **service-role key** (for single-user personal use) or a **user JWT** (if multi-user support is added later). Credentials are passed exclusively via environment variables — never hardcoded.

```
# .env.example
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=eyJhbGci...         # service_role key for personal use
HEARTY_USER_ID=uuid-of-the-owner         # single-user mode: always act as this user
```

### 6.2 `supabase.ts`

```typescript
// src/supabase.ts

import { createClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.SUPABASE_URL!;
const supabaseKey = process.env.SUPABASE_SERVICE_KEY!;

if (!supabaseUrl || !supabaseKey) {
  throw new Error('SUPABASE_URL and SUPABASE_SERVICE_KEY must be set in environment.');
}

export const supabase = createClient(supabaseUrl, supabaseKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false
  }
});

export function getUserId(): string {
  const userId = process.env.HEARTY_USER_ID;
  if (!userId) throw new Error('HEARTY_USER_ID must be set.');
  return userId;
}
```

### 6.3 Claude Desktop Installation

Add to `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "hearty": {
      "command": "node",
      "args": ["/path/to/hearty-mcp/dist/index.js"],
      "env": {
        "SUPABASE_URL": "https://your-project.supabase.co",
        "SUPABASE_SERVICE_KEY": "your-service-role-key",
        "HEARTY_USER_ID": "your-user-uuid"
      }
    }
  }
}
```

---

## 7. Error Handling

The MCP server must never throw unhandled errors to Claude. Every tool handler wraps its logic in a try/catch and returns a structured error message as a text content block.

```typescript
// Standard error handling pattern for all tool handlers

try {
  // ... tool logic
} catch (err) {
  const message = err instanceof Error ? err.message : 'Unknown error';
  return {
    content: [
      {
        type: 'text',
        text: JSON.stringify({
          success: false,
          error: message,
          hint: 'Check SUPABASE_URL, SUPABASE_SERVICE_KEY, and HEARTY_USER_ID in your MCP env config.'
        })
      }
    ],
    isError: true
  };
}
```

Claude should interpret `isError: true` results gracefully and inform the user without exposing raw stack traces.

---

## 8. Offline Behavior

The MCP server itself has no offline mode. It expects live Supabase connectivity at all times. Offline logging is handled at the Flutter app layer (Phase 2), which queues writes locally and syncs on reconnect. The MCP server is a direct-to-cloud path used by Claude Desktop/Web — these environments are assumed to be online.

If a tool call fails due to connectivity, the error handler returns a clear message and Claude should advise the user to retry when connected.

---

## 9. `index.ts` — Server Setup

```typescript
// src/index.ts

import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { registerLogMeal } from './tools/log-meal.js';
import { registerLogSymptoms } from './tools/log-symptoms.js';
import { registerLogWellbeing } from './tools/log-wellbeing.js';
import { registerQueryHistory } from './tools/query-history.js';
import { registerGetTrends } from './tools/get-trends.js';
import { registerGetSummary } from './tools/get-summary.js';

const server = new McpServer({
  name: 'hearty',
  version: '1.0.0',
  description: `[Insert full system prompt from Section 3 here]`
});

registerLogMeal(server);
registerLogSymptoms(server);
registerLogWellbeing(server);
registerQueryHistory(server);
registerGetTrends(server);
registerGetSummary(server);

const transport = new StdioServerTransport();
await server.connect(transport);
```

Each `register*` function accepts the `McpServer` instance and calls `server.tool(name, description, schema, handler)`.

---

## 10. `package.json` — Key Dependencies

```json
{
  "name": "hearty-mcp",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js",
    "dev": "tsx src/index.ts"
  },
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.0",
    "@supabase/supabase-js": "^2.0.0"
  },
  "devDependencies": {
    "typescript": "^5.0.0",
    "tsx": "^4.0.0",
    "@types/node": "^20.0.0"
  }
}
```

---

## 11. `tsconfig.json`

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  },
  "include": ["src/**/*"]
}
```
