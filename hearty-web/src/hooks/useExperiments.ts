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
  // Each useMutation is called unconditionally, in stable order, at the hook's top
  // level — assigned to a const so consumers read live isPending/isSuccess state.
  const create = useMutation({ mutationFn: (b: CreateExperimentRequest) => api.createExperiment(b), onSuccess: invalidate });
  const evaluate = useMutation({ mutationFn: (id: string) => api.evaluateExperiment(id), onSuccess: invalidate });
  const abandon = useMutation({ mutationFn: (id: string) => api.abandonExperiment(id), onSuccess: invalidate });
  const restart = useMutation({ mutationFn: (id: string) => api.restartExperiment(id), onSuccess: invalidate });
  const ackNudge = useMutation({ mutationFn: (id: string) => api.ackNudge(id), onSuccess: invalidate });
  return { create, evaluate, abandon, restart, ackNudge };
}
