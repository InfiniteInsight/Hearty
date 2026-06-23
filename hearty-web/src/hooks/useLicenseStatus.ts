import { useQuery } from "@tanstack/react-query";
import { api } from "../lib/api";
export function useLicenseStatus() {
  return useQuery({ queryKey: ["license-status"], queryFn: () => api.getLicenseStatus(), staleTime: 60_000 });
}
