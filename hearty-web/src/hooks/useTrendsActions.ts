import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "../lib/api";
import type { SignalVerdictRequest } from "@/types/api";

export function useAnalyzeStatus() {
  return useQuery({
    queryKey: ["trends", "status"],
    queryFn: () => api.getAnalyzeStatus(),
    staleTime: 60_000,
  });
}

export function useAnalyze() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: () => api.analyzeTrends(),
    // POST /analyze is synchronous (returns status:"completed"); just refresh.
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["trends"] });
    },
  });
}

export function useSignalVerdict() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: SignalVerdictRequest) => api.signalVerdict(body),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["trends"] });
    },
  });
}
