import { useQuery } from "@tanstack/react-query";
import { api } from "../lib/api";
import { startOfTodayISO } from "../lib/time";
export function useTodayMeals() {
  const start = startOfTodayISO();
  return useQuery({ queryKey: ["meals", { start }], queryFn: () => api.getMeals({ start_date: start }) });
}
