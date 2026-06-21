import { useQuery } from "@tanstack/react-query";
import { api } from "../lib/api";
import { startOfTodayISO } from "../lib/time";
export function useTodaySymptoms() {
  const start = startOfTodayISO();
  return useQuery({ queryKey: ["symptoms", { start }], queryFn: () => api.getSymptoms({ start_date: start }) });
}
