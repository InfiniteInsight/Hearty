import { useCallback } from "react";
import { useSearchParams } from "react-router-dom";

export interface JournalFilters {
  start_date?: string;
  end_date?: string;
  keyword?: string;
  meal_type?: string;
  symptom_type?: string;
  page: number;
}

const FILTER_KEYS = ["start_date", "end_date", "keyword", "meal_type", "symptom_type"] as const;

export function useJournalFilters() {
  const [params, setParams] = useSearchParams();

  const filters: JournalFilters = {
    start_date: params.get("start_date") || undefined,
    end_date: params.get("end_date") || undefined,
    keyword: params.get("keyword") || undefined,
    meal_type: params.get("meal_type") || undefined,
    symptom_type: params.get("symptom_type") || undefined,
    page: Math.max(0, Number(params.get("page") ?? "0") || 0),
  };

  // Single write path. A page set is honored as-is; any other (filter) change
  // resets pagination to page 0 so the user isn't stranded on an empty page.
  const setFilters = useCallback(
    (update: Partial<JournalFilters>) => {
      setParams(
        (prev) => {
          const next = new URLSearchParams(prev);
          for (const k of FILTER_KEYS) {
            if (k in update) {
              const v = update[k];
              if (v) next.set(k, v);
              else next.delete(k);
            }
          }
          if ("page" in update && update.page !== undefined) {
            next.set("page", String(update.page));
          } else {
            next.delete("page");
          }
          return next;
        },
        { replace: true }
      );
    },
    [setParams]
  );

  return { filters, setFilters };
}
