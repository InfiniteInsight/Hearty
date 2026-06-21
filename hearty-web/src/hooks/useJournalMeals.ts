import { useQuery } from "@tanstack/react-query";
import { api } from "../lib/api";
import type { JournalFilters } from "./useJournalFilters";

export const JOURNAL_PAGE_SIZE = 25;

export function useJournalMeals(filters: JournalFilters) {
  const { start_date, end_date, keyword, meal_type, page } = filters;
  return useQuery({
    queryKey: ["meals", { start_date, end_date, keyword, meal_type, page }],
    queryFn: () =>
      api.getMeals({
        start_date,
        end_date,
        keyword,
        meal_type,
        limit: JOURNAL_PAGE_SIZE,
        offset: page * JOURNAL_PAGE_SIZE,
      }),
  });
}
