import { supabase } from "./supabase";
import type {
  MealsListResponse, MealResponse, CreateMealRequest,
  SymptomResponse, SignalsResponse, SummaryResponse,
  MealUpdateRequest, SymptomUpdateRequest,
  AnalyzeResponse, AnalyzeStatusResponse,
  SignalVerdictRequest, SignalVerdictResponse,
  TrendsConversationRequest, TrendsConversationResponse,
  CreateExperimentRequest, ExperimentResponse, ActiveExperimentsResponse,
  UserPreferences, ExportDateRange, BlobDownload,
  HealthProfileResponse, HealthProfilePutRequest, HealthProfileDefaults,
  LicenseStatus, AdminUsersResponse, GrantLicenseRequest,
} from "@/types/api";

export class ApiError extends Error {
  status: number;
  constructor(status: number, message: string) { super(message); this.name = "ApiError"; this.status = status; }
}

async function authHeader(): Promise<Record<string, string>> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  return token ? { Authorization: `Bearer ${token}` } : {};
}

function qs(params: Record<string, string | number | undefined>): string {
  const u = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) if (v !== undefined && v !== "") u.set(k, String(v));
  const s = u.toString();
  return s ? `?${s}` : "";
}

export function createApiClient(baseUrl: string) {
  async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const headers: Record<string, string> = { ...(await authHeader()) };
    // Only send Content-Type on requests with a body; on cross-origin GETs it can trigger CORS preflight.
    if (init.method && init.method !== "GET") headers["Content-Type"] = "application/json";
    Object.assign(headers, (init.headers as Record<string, string> | undefined) ?? {});
    const res = await fetch(`${baseUrl}${path}`, { ...init, headers });
    if (!res.ok) throw new ApiError(res.status, `${res.status} ${res.statusText}`);
    if (res.status === 204) return undefined as T;
    return (await res.json()) as T;
  }
  async function requestBlob(path: string, init: RequestInit = {}): Promise<BlobDownload> {
    const headers: Record<string, string> = { ...(await authHeader()) };
    if (init.method && init.method !== "GET") headers["Content-Type"] = "application/json";
    const res = await fetch(`${baseUrl}${path}`, { ...init, headers });
    if (!res.ok) throw new ApiError(res.status, `${res.status} ${res.statusText}`);
    const blob = await res.blob();
    const cd = res.headers.get("Content-Disposition") ?? "";
    const match = /filename="?([^";]+)"?/.exec(cd);
    return { blob, filename: match?.[1] ?? "download" };
  }
  return {
    getMeals: (p: { start_date?: string; end_date?: string; meal_type?: string; keyword?: string; limit?: number; offset?: number } = {}) =>
      request<MealsListResponse>(`/api/meals${qs(p)}`),
    createMeal: (body: CreateMealRequest) =>
      request<MealResponse>(`/api/meals`, { method: "POST", body: JSON.stringify(body) }),
    getSymptoms: (p: { start_date?: string; end_date?: string; symptom_type?: string; min_severity?: number; limit?: number } = {}) =>
      request<SymptomResponse[]>(`/api/symptoms${qs(p)}`),
    getTrends: () => request<SignalsResponse>(`/api/trends`),
    getSummary: (p: { period?: string; start_date?: string; end_date?: string } = {}) =>
      request<SummaryResponse>(`/api/summary${qs(p)}`),
    patchMeal: (id: string, body: MealUpdateRequest) =>
      request<MealResponse>(`/api/meals/${id}`, { method: "PATCH", body: JSON.stringify(body) }),
    deleteMeal: (id: string) =>
      request<void>(`/api/meals/${id}`, { method: "DELETE" }),
    patchSymptom: (id: string, body: SymptomUpdateRequest) =>
      request<SymptomResponse>(`/api/symptoms/${id}`, { method: "PATCH", body: JSON.stringify(body) }),
    deleteSymptom: (id: string) =>
      request<void>(`/api/symptoms/${id}`, { method: "DELETE" }),
    analyzeTrends: () =>
      request<AnalyzeResponse>(`/api/trends/analyze`, { method: "POST" }),
    getAnalyzeStatus: () =>
      request<AnalyzeStatusResponse>(`/api/trends/analyze/status`),
    signalVerdict: (body: SignalVerdictRequest) =>
      request<SignalVerdictResponse>(`/api/trends/signal-verdict`, { method: "POST", body: JSON.stringify(body) }),
    trendsConversation: (body: TrendsConversationRequest) =>
      request<TrendsConversationResponse>(`/api/trends/conversation`, { method: "POST", body: JSON.stringify(body) }),
    createExperiment: (body: CreateExperimentRequest) =>
      request<ExperimentResponse>(`/api/experiments`, { method: "POST", body: JSON.stringify(body) }),
    getActiveExperiments: () =>
      request<ActiveExperimentsResponse>(`/api/experiments/active`),
    evaluateExperiment: (id: string) =>
      request<ExperimentResponse>(`/api/experiments/${id}/evaluate`, { method: "POST" }),
    abandonExperiment: (id: string) =>
      request<{ ok: boolean }>(`/api/experiments/${id}/abandon`, { method: "POST" }),
    restartExperiment: (id: string) =>
      request<ExperimentResponse>(`/api/experiments/${id}/restart`, { method: "POST" }),
    ackNudge: (id: string) =>
      request<{ ok: boolean }>(`/api/experiments/${id}/ack-nudge`, { method: "POST" }),
    exportCsv: (p: ExportDateRange = {}) => requestBlob(`/api/export/csv${qs(p as Record<string, string | undefined>)}`),
    exportJson: (p: ExportDateRange = {}) => requestBlob(`/api/export/json${qs(p as Record<string, string | undefined>)}`),
    exportPdf: (body: ExportDateRange) => requestBlob(`/api/export/pdf`, { method: "POST", body: JSON.stringify(body) }),
    getPreferences: () => request<UserPreferences>(`/api/preferences`),
    putPreferences: (body: UserPreferences) => request<UserPreferences>(`/api/preferences`, { method: "PUT", body: JSON.stringify(body) }),
    deleteAccount: () => request<void>(`/api/account`, { method: "DELETE" }),
    getHealthProfile: () => request<HealthProfileResponse>(`/api/health-profile`),
    putHealthProfile: (body: HealthProfilePutRequest) => request<HealthProfileResponse>(`/api/health-profile`, { method: "PUT", body: JSON.stringify(body) }),
    getHealthProfileDefaults: () => request<HealthProfileDefaults>(`/api/health-profile/defaults`),
    getLicenseStatus: () => request<LicenseStatus>(`/api/license/status`),
    getAdminUsers: () => request<AdminUsersResponse>(`/api/admin/users`),
    grantLicense: (body: GrantLicenseRequest) => request<unknown>(`/api/admin/licenses`, { method: "POST", body: JSON.stringify(body) }),
    revokeLicense: (id: string) => request<unknown>(`/api/admin/licenses/${id}/revoke`, { method: "POST" }),
    reactivateLicense: (id: string) => request<unknown>(`/api/admin/licenses/${id}/reactivate`, { method: "POST" }),
    updateLicense: (id: string, body: { expires_at?: string; tier?: string; status?: string; notes?: string }) => request<unknown>(`/api/admin/licenses/${id}`, { method: "PATCH", body: JSON.stringify(body) }),
  };
}

export const api = createApiClient(import.meta.env.VITE_API_URL as string);
export type ApiClient = ReturnType<typeof createApiClient>;
