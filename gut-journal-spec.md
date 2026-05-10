# Hearty — Food & Symptom Journal: Full Build Specification

> **Instructions for the executing Claude:** This document is a complete specification for building a multi-device food and symptom tracking application. Follow every section in order. Ask for clarification only if you hit a genuine blocker—otherwise, make smart decisions aligned with the architecture described here and build it. The owner wants a polished, production-grade result.

---

## 1. Project Overview

**Name:** Hearty (or suggest a better name to the owner)

**Purpose:** A personal health intelligence tool that lets the owner log meals and subsequent physical symptoms via voice or text, stores all data in a structured cloud database, visualizes trends over time, and uses AI to automatically surface correlations between foods and health outcomes.

**Key goals:**
- Minimal friction for logging (voice-first, never more than a sentence or two)
- Data is richly structured and easy to query
- Multi-device, multi-AI-assistant compatible
- Automated trend detection, not just raw storage
- Beautiful, functional web dashboard for reviewing and exporting data

---

## 2. Tech Stack

| Layer | Technology | Reason |
|---|---|---|
| Database | Supabase (PostgreSQL) | Relational, real-time, REST + SDK, RLS security |
| MCP Server | Node.js + `@modelcontextprotocol/sdk` | Claude native integration |
| REST API | FastAPI (Python) or Express (Node.js) | AI-agnostic access for Gemini, GPT, etc. |
| Web Frontend | React + Vite + TailwindCSS | Component-driven, fast, modern |
| Charts | Recharts | Flexible, React-native charting |
| PDF Reports | `react-pdf` or `pdfmake` | Client-side PDF generation |
| Auth | Supabase Auth (magic link / Google OAuth) | Simple, built-in |
| Hosting | Vercel (frontend) + Railway or Render (API) | Easy deploys |
| Voice | Web Speech API (browser) + Claude voice mode | Dual path |

---

## 3. Supabase Database Schema

Create the following tables in Supabase. Enable Row Level Security (RLS) on all tables and lock each row to `auth.uid()`.

### 3.1 `meals`
```sql
create table meals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users not null,
  logged_at timestamptz not null default now(),
  meal_type text check (meal_type in ('breakfast','lunch','dinner','snack','drink','supplement','other')),
  description text not null,               -- free text: "grilled salmon with rice and broccoli"
  foods jsonb,                              -- parsed food items: [{"name":"salmon","quantity":"1 fillet","estimated_calories":300}]
  location text,                            -- "home", "restaurant name", etc.
  mood_before int check (mood_before between 1 and 10),
  hunger_before int check (hunger_before between 1 and 10),
  notes text,
  created_at timestamptz default now()
);
```

### 3.2 `symptoms`
```sql
create table symptoms (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users not null,
  meal_id uuid references meals(id) on delete cascade,
  logged_at timestamptz not null default now(),
  onset_minutes int,                        -- minutes after meal symptom appeared
  symptom_type text not null check (symptom_type in (
    'acid_reflux','bloating','gas','nausea','urgency','loose_stool',
    'constipation','stomach_pain','cramping','fatigue','brain_fog',
    'headache','skin_reaction','heart_palpitations','other'
  )),
  severity int check (severity between 1 and 10),
  duration_minutes int,                     -- how long it lasted
  bathroom_urgency int check (bathroom_urgency between 0 and 5),  -- 0=none, 5=emergency
  bathroom_visits int default 0,
  stool_consistency int check (stool_consistency between 1 and 7), -- Bristol Stool Scale
  notes text,
  created_at timestamptz default now()
);
```

### 3.3 `wellbeing_snapshots`
```sql
create table wellbeing_snapshots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users not null,
  logged_at timestamptz not null default now(),
  energy_level int check (energy_level between 1 and 10),
  mood int check (mood between 1 and 10),
  stress_level int check (stress_level between 1 and 10),
  sleep_hours numeric(4,1),
  sleep_quality int check (sleep_quality between 1 and 10),
  hydration int check (hydration between 1 and 10),
  exercise_minutes int default 0,
  notes text,
  created_at timestamptz default now()
);
```

### 3.4 `food_triggers` (derived/curated)
```sql
create table food_triggers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users not null,
  food_name text not null,
  symptom_type text not null,
  confidence_score numeric(4,2),           -- 0.0 to 1.0, calculated by trend engine
  occurrence_count int default 1,
  avg_onset_minutes int,
  avg_severity numeric(4,2),
  last_updated timestamptz default now(),
  is_confirmed boolean default false,      -- owner manually confirms trigger
  notes text
);
```

### 3.5 Indexes
```sql
create index on meals (user_id, logged_at desc);
create index on symptoms (meal_id);
create index on symptoms (user_id, logged_at desc);
create index on symptoms (symptom_type);
create index on wellbeing_snapshots (user_id, logged_at desc);
```

### 3.6 Row Level Security
```sql
-- Apply to all tables
alter table meals enable row level security;
alter table symptoms enable row level security;
alter table wellbeing_snapshots enable row level security;
alter table food_triggers enable row level security;

-- Example policy (repeat for each table)
create policy "Users can only access their own data"
  on meals for all
  using (auth.uid() = user_id);
```

---

## 4. MCP Server

### 4.1 Overview
Build a Node.js MCP server using `@modelcontextprotocol/sdk`. This is what gets installed into Claude Desktop, the Claude mobile app, or Claude Web. It exposes tools that Claude can call to log and query data.

**File structure:**
```
gutlog-mcp/
  src/
    index.ts         -- MCP server entry point
    supabase.ts      -- Supabase client
    tools/
      log-meal.ts
      log-symptoms.ts
      log-wellbeing.ts
      query-history.ts
      get-trends.ts
      get-summary.ts
  package.json
  tsconfig.json
  .env.example
```

### 4.2 MCP Server Behavioral Instructions

**CRITICAL:** Include the following as the MCP server `description` so Claude internalizes this behavior without the owner repeating it:

```
You are Hearty, a compassionate and precise personal health journal assistant. 
Your primary job is to help the owner track what they eat and how their body responds.

LOGGING BEHAVIOR:
- When the user mentions any food or meal, immediately log it. Do not wait for explicit commands.
- After logging a meal, set a gentle follow-up reminder in the conversation to ask about symptoms 
  30-90 minutes later if the user hasn't mentioned any.
- When logging symptoms, always ask about onset time (how many minutes after eating), severity (1-10), 
  and whether there was any bathroom urgency.
- Be clinical but warm. Never make the user feel embarrassed about GI symptoms.
- If the user says something like "I feel terrible" without specifying why, ask: 
  "Is this related to something you ate? How's your stomach?"

TREND AWARENESS:
- When the user logs a symptom, check if this pattern has occurred before and mention it.
  Example: "Noted. I've seen acid reflux come up 3 other times after you ate tomato-based foods."
- Periodically (when asked or when there's enough data) offer a trend summary.

NEVER:
- Provide medical diagnoses or replace medical advice.
- Add disclaimers to every single response—one initial disclaimer is enough.
- Make the user retype context they've already given.
```

### 4.3 MCP Tools to Implement

#### `log_meal`
```typescript
{
  name: "log_meal",
  description: "Log a meal or food/drink the user just consumed. Call this whenever the user describes eating or drinking anything.",
  inputSchema: {
    type: "object",
    properties: {
      description: { type: "string", description: "Natural language description of the meal" },
      meal_type: { type: "string", enum: ["breakfast","lunch","dinner","snack","drink","supplement","other"] },
      foods: { type: "array", description: "Parsed list of individual food items with name and estimated quantity" },
      location: { type: "string" },
      mood_before: { type: "number", description: "Mood 1-10 before eating" },
      hunger_before: { type: "number", description: "Hunger level 1-10 before eating" },
      logged_at: { type: "string", description: "ISO timestamp, defaults to now" }
    },
    required: ["description"]
  }
}
```

#### `log_symptoms`
```typescript
{
  name: "log_symptoms",
  description: "Log one or more physical symptoms. Always call this when the user mentions how they feel after eating.",
  inputSchema: {
    type: "object",
    properties: {
      meal_id: { type: "string", description: "UUID of the associated meal if known" },
      onset_minutes: { type: "number", description: "Minutes after eating the symptom appeared" },
      symptoms: {
        type: "array",
        items: {
          type: "object",
          properties: {
            symptom_type: { type: "string" },
            severity: { type: "number" },
            duration_minutes: { type: "number" },
            bathroom_urgency: { type: "number" },
            bathroom_visits: { type: "number" },
            stool_consistency: { type: "number", description: "Bristol Stool Scale 1-7" }
          }
        }
      },
      notes: { type: "string" }
    },
    required: ["symptoms"]
  }
}
```

#### `log_wellbeing`
```typescript
{
  name: "log_wellbeing",
  description: "Log a general wellbeing snapshot. Useful for morning check-ins or when user mentions overall condition.",
  inputSchema: {
    type: "object",
    properties: {
      energy_level: { type: "number" },
      mood: { type: "number" },
      stress_level: { type: "number" },
      sleep_hours: { type: "number" },
      sleep_quality: { type: "number" },
      hydration: { type: "number" },
      exercise_minutes: { type: "number" },
      notes: { type: "string" }
    }
  }
}
```

#### `query_history`
```typescript
{
  name: "query_history",
  description: "Query past meals and symptoms. Use when user asks 'what did I eat last week' or 'when did I last have acid reflux'.",
  inputSchema: {
    type: "object",
    properties: {
      start_date: { type: "string" },
      end_date: { type: "string" },
      symptom_type: { type: "string" },
      food_keyword: { type: "string" },
      limit: { type: "number", default: 20 }
    }
  }
}
```

#### `get_trends`
```typescript
{
  name: "get_trends",
  description: "Run trend analysis to identify food triggers and symptom patterns. Returns ranked list of likely trigger foods.",
  inputSchema: {
    type: "object",
    properties: {
      analysis_period_days: { type: "number", default: 30 },
      focus_symptom: { type: "string", description: "Narrow analysis to a specific symptom type" },
      min_occurrences: { type: "number", default: 2 }
    }
  }
}
```

#### `get_summary`
```typescript
{
  name: "get_summary",
  description: "Get a natural language summary of recent health patterns. Useful for weekly reviews.",
  inputSchema: {
    type: "object",
    properties: {
      period: { type: "string", enum: ["week","month","custom"] },
      start_date: { type: "string" },
      end_date: { type: "string" }
    }
  }
}
```

---

## 5. REST API Layer

Build a lightweight REST API so other AI assistants (Gemini, GPT, etc.) and third-party tools can interact with Hearty without needing the MCP protocol.

**Recommended:** FastAPI (Python) for speed and auto-generated OpenAPI docs.

### Endpoints

```
POST   /api/meals                  -- Log a meal
POST   /api/symptoms               -- Log symptoms
POST   /api/wellbeing              -- Log wellbeing snapshot
GET    /api/meals                  -- Query meals (supports date, keyword filters)
GET    /api/symptoms               -- Query symptoms
GET    /api/trends                 -- Get trend analysis
GET    /api/summary                -- Get natural language summary
GET    /api/export/json            -- Export all data as JSON
GET    /api/export/csv             -- Export all data as CSV
GET    /api/export/xml             -- Export all data as XML
POST   /api/export/pdf             -- Generate a PDF trend report
```

### Authentication
All endpoints require a Bearer token (Supabase JWT). The user logs into the web app once, gets their token, and pastes it into any AI assistant's setup instructions once.

### System Prompt for External AI Assistants
Include this in the documentation so Gemini or GPT users can paste it once:

```
You are connected to Hearty, a personal food and symptom journal API. 
The base URL is: [DEPLOYED_API_URL]
Bearer token: [USER_TOKEN]

When the user mentions food or symptoms, call the appropriate API endpoint.
After logging a meal, follow up about symptoms 30-90 minutes later.
When asked about trends or patterns, call GET /api/trends.
Never ask for information already captured in previous logs.
```

---

## 6. Web Frontend

### 6.1 Design Direction
Go for a dark, clinical-but-warm aesthetic. Think medical dashboard meets personal journal. Deep charcoal backgrounds, warm amber and teal accents, clean typography using a monospace or semi-technical feel for data, paired with a human readable serif or soft sans for prose. Not sterile—personal and intelligent.

### 6.2 Pages / Views

#### Dashboard (Home)
- Today's meals and symptoms timeline
- Quick log button (opens voice or text modal)
- Today's wellbeing score card
- Recent alert: "⚠ Acid reflux logged 3x this week. Possible trigger: tomatoes."

#### Food Journal
- Scrollable log of all meals with expandable symptom details
- Filter by date range, food keyword, symptom type
- Each entry shows: meal description, foods parsed, timestamp, linked symptoms with severity

#### Symptoms Log
- Dedicated view for symptoms with severity heatmap over time
- Bristol Stool Scale tracker (rendered tastefully)
- Urgency frequency chart

#### Trends & Analytics
- Top trigger foods (ranked by correlation score)
- Symptom frequency chart (by type, over time)
- Onset time distribution (how quickly symptoms appear)
- Mood/energy correlation with meals
- Wellbeing trends over time

#### Export
- Choose format: JSON, CSV, XML, PDF Report
- Date range selector
- PDF report auto-generates a trend summary with charts embedded

### 6.3 Quick Log Modal
- Triggered by voice button or keyboard shortcut (Cmd+L)
- Accepts free text or voice via Web Speech API
- AI interprets the input and pre-fills the form fields
- Confirm and save in under 10 seconds

### 6.4 Component Library
Use Tailwind + shadcn/ui for base components, Recharts for all visualizations. Keep the component tree clean and typed with TypeScript.

---

## 7. Trend Analysis Engine

This runs server-side, either as a Supabase Edge Function or a scheduled job in the API.

### Algorithm

1. **Co-occurrence analysis:** For each food item mentioned across all meals, calculate what percentage of times a symptom appeared within 4 hours.

2. **Severity weighting:** Weight by severity score—a mild bloat after salmon counts less than an urgency-9 bathroom sprint.

3. **Confidence scoring:**
   ```
   confidence = (co_occurrence_rate * 0.5) + (avg_severity / 10 * 0.3) + (frequency_penalty * 0.2)
   ```
   Minimum 3 occurrences to appear in trigger list.

4. **Time-of-day / day-of-week patterns:** Surface if symptoms cluster on specific days or times regardless of food.

5. **Cumulative vs. single-dose triggers:** Detect if a food only causes symptoms after multiple consecutive days of consumption.

6. **Wellbeing correlation:** Cross-reference sleep quality and stress levels with symptom severity—poor sleep may amplify reactions.

### Output
Populates the `food_triggers` table automatically. Claude reads from this table when the user asks about patterns.

---

## 8. Export & Reporting

### JSON / CSV / XML
- Query all tables, join meals to symptoms, serialize and return
- Include human-readable column headers, not just IDs
- CSV: flat structure, one row per symptom with meal fields denormalized
- XML: nested structure with `<meal>` parent and `<symptom>` children

### PDF Report
Generate a structured summary document including:
- **Period:** Date range covered
- **Meals logged:** Total count, breakdown by type
- **Top symptoms:** Frequency and average severity
- **Identified triggers:** Confidence-ranked list with evidence
- **Best days:** Days with lowest symptom burden
- **Trend charts:** Embedded as images (use canvas-to-image before PDF generation)
- **Recommendations section:** AI-generated, clearly marked as not medical advice

---

## 9. Voice Interaction Flow

**Via Claude (MCP):**
1. User speaks: "I just had a large pepperoni pizza and two beers at the game."
2. Claude calls `log_meal` with parsed details.
3. Claude replies: "Logged. That's a heavy one—pepperoni is high in fat and beer is carbonated. I'll check back in about an hour."
4. ~60 min later in conversation, Claude asks: "How are you feeling since the pizza?"
5. User: "Awful. Heartburn and I'm really gassy."
6. Claude calls `log_symptoms`, then: "Got it—acid reflux severity 8, gas logged. This is the 4th time heartburn appeared after pizza or tomato sauce. Starting to look like a pattern."

**Via Web App:**
1. Click mic button
2. Speak meal description
3. App transcribes, sends to backend for parsing
4. Form pre-filled for review and confirmation

---

## 10. Installation & Setup Instructions (for owner to use later)

### Supabase Setup
1. Create a new Supabase project
2. Run all SQL from Section 3 in the SQL editor
3. Enable Email/Google OAuth in Authentication settings
4. Note your project URL and anon key

### MCP Server Installation
```bash
git clone [repo]
cd gutlog-mcp
npm install
cp .env.example .env
# Add SUPABASE_URL and SUPABASE_SERVICE_KEY to .env
npm run build
```

Add to Claude Desktop `claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "gutlog": {
      "command": "node",
      "args": ["/path/to/gutlog-mcp/dist/index.js"],
      "env": {
        "SUPABASE_URL": "...",
        "SUPABASE_SERVICE_KEY": "..."
      }
    }
  }
}
```

### Web App
```bash
cd gutlog-web
npm install
cp .env.example .env.local
# Add VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY
npm run dev
```

Deploy to Vercel: `vercel deploy`

---

## 11. Future Enhancements (do not build now, document for later)

- Photo logging: snap a photo of a meal and AI identifies foods automatically
- Wearable integration: import heart rate data around meal times
- Doctor export: generate a clinical summary formatted for a gastroenterologist
- Notification system: remind owner to log symptoms X minutes after meals
- Barcode scanner: log packaged foods by scanning barcode
- Medication tracking: log supplements and medications alongside meals

---

## 12. Non-Negotiables

- **All data is private.** Row Level Security must be enabled and enforced. Never expose another user's data.
- **No medical advice.** The app can say "this food correlates with symptoms" but must never say "you have IBS" or similar.
- **Offline resilience.** The web app should queue logs locally if offline and sync when back online.
- **Mobile-first web.** The owner uses this on their phone. Every UI element must work perfectly on a small screen.
- **Fast logging.** A meal should be loggable in under 15 seconds including confirmation. No multi-page flows.
