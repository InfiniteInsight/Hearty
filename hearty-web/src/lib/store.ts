import { create } from "zustand";

export type TrendsPeriod = "7d" | "30d" | "90d";

interface UiState {
  sidebarOpen: boolean;
  setSidebarOpen: (open: boolean) => void;
  trendsPeriod: TrendsPeriod;
  setTrendsPeriod: (p: TrendsPeriod) => void;
}

export const useUiStore = create<UiState>((set) => ({
  sidebarOpen: true,
  setSidebarOpen: (open) => set({ sidebarOpen: open }),
  trendsPeriod: "30d",
  setTrendsPeriod: (p) => set({ trendsPeriod: p }),
}));
