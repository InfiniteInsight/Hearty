import { useQuery } from "@tanstack/react-query";
import { api } from "../lib/api";
export function useWeekSummary() {
  return useQuery({ queryKey: ["summary", { period: "week" }], queryFn: () => api.getSummary({ period: "week" }), staleTime: 300_000 });
}
