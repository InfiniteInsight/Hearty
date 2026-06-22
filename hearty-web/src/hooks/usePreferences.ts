import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "../lib/api";
import type { UserPreferences } from "@/types/api";

export function usePreferences() {
  return useQuery({ queryKey: ["preferences"], queryFn: () => api.getPreferences(), staleTime: 300_000 });
}

export function useSavePreferences() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: UserPreferences) => api.putPreferences(body),
    onSuccess: (data) => qc.setQueryData(["preferences"], data),
  });
}
