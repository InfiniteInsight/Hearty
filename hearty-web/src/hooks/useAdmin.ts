import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "../lib/api";
import type { GrantLicenseRequest, AppSettings } from "@/types/api";

export function useAdminUsers() {
  return useQuery({
    queryKey: ["admin", "users"],
    queryFn: () => api.getAdminUsers(),
    staleTime: 30_000,
  });
}

export function useAdminActions() {
  const qc = useQueryClient();
  const invalidate = () => qc.invalidateQueries({ queryKey: ["admin", "users"] });
  const grant = useMutation({ mutationFn: (body: GrantLicenseRequest) => api.grantLicense(body), onSuccess: invalidate });
  const revoke = useMutation({ mutationFn: (id: string) => api.revokeLicense(id), onSuccess: invalidate });
  const reactivate = useMutation({ mutationFn: (id: string) => api.reactivateLicense(id), onSuccess: invalidate });
  const update = useMutation({ mutationFn: ({ id, body }: { id: string; body: { expires_at?: string; tier?: string; status?: string; notes?: string } }) => api.updateLicense(id, body), onSuccess: invalidate });
  return { grant, revoke, reactivate, update };
}

export function useAppSettings() {
  return useQuery({
    queryKey: ["admin", "settings"],
    queryFn: () => api.getAppSettings(),
    staleTime: 30_000,
  });
}

export function useUpdateAppSettings() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: Partial<AppSettings>) => api.updateAppSettings(body),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin", "settings"] }),
  });
}
