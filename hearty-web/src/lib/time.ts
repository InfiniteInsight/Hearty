// Local midnight (the user's "today"), serialized to UTC ISO for the API.
// Intentional: "today's timeline" means the user's calendar day, not UTC midnight.
export function startOfTodayISO(now: Date = new Date()): string {
  const d = new Date(now); d.setHours(0, 0, 0, 0); return d.toISOString();
}
