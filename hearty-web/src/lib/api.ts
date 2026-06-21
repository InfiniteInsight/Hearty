import { supabase } from "./supabase";
import type {
  MealsListResponse, MealResponse, CreateMealRequest,
  SymptomResponse, SignalsResponse, SummaryResponse,
} from "@/types/api";

export class ApiError extends Error {
  constructor(public status: number, message: string) { super(message); }
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
    const res = await fetch(`${baseUrl}${path}`, {
      ...init,
      headers: { "Content-Type": "application/json", ...(await authHeader()), ...(init.headers ?? {}) },
    });
    if (!res.ok) throw new ApiError(res.status, `${res.status} ${res.statusText}`);
    if (res.status === 204) return undefined as T;
    return (await res.json()) as T;
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
  };
}

export const api = createApiClient(import.meta.env.VITE_API_URL as string);
export type ApiClient = ReturnType<typeof createApiClient>;
