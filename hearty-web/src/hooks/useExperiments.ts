import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "../lib/api";
import type { CreateExperimentRequest } from "@/types/api";

export function useActiveExperiments() {
  return useQuery({
    queryKey: ["experiments"],
    queryFn: () => api.getActiveExperiments(),
    staleTime: 60_000,
  });
}

export function useExperimentActions() {
  const qc = useQueryClient();
  const invalidate = () => qc.invalidateQueries({ queryKey: ["experiments"] });
  return {
    create: useMutation({ mutationFn: (b: CreateExperimentRequest) => api.createExperiment(b), onSuccess: invalidate }),
    evaluate: useMutation({ mutationFn: (id: string) => api.evaluateExperiment(id), onSuccess: invalidate }),
    abandon: useMutation({ mutationFn: (id: string) => api.abandonExperiment(id), onSuccess: invalidate }),
    restart: useMutation({ mutationFn: (id: string) => api.restartExperiment(id), onSuccess: invalidate }),
    ackNudge: useMutation({ mutationFn: (id: string) => api.ackNudge(id), onSuccess: invalidate }),
  };
}
