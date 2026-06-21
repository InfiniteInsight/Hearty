export function startOfTodayISO(now: Date = new Date()): string {
  const d = new Date(now); d.setHours(0, 0, 0, 0); return d.toISOString();
}
