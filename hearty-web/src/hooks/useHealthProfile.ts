import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "../lib/api";
import type { HealthProfilePutRequest } from "@/types/api";

export function useHealthProfile() {
  return useQuery({ queryKey: ["health-profile"], queryFn: () => api.getHealthProfile(), staleTime: 300_000 });
}

export function useHealthProfileDefaults() {
  return useQuery({ queryKey: ["health-profile", "defaults"], queryFn: () => api.getHealthProfileDefaults(), staleTime: Infinity });
}

export function useSaveHealthProfile() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: HealthProfilePutRequest) => api.putHealthProfile(body),
    onSuccess: (data) => qc.setQueryData(["health-profile"], data),
  });
}
