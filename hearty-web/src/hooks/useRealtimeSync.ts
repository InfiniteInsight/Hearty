import { useEffect, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { supabase } from "../lib/supabase";
import type { SyncStatus } from "../components/layout/SyncIndicator";

export function useRealtimeSync(): SyncStatus {
  const qc = useQueryClient();
  const [status, setStatus] = useState<SyncStatus>("connecting");
  useEffect(() => {
    let channel: ReturnType<typeof supabase.channel> | null = null;
    let active = true;
    (async () => {
      try {
        const { data } = await supabase.auth.getUser();
        const uid = data.user?.id;
        if (!active) return;
        if (!uid) { setStatus("offline"); return; }
        const invalidate = () => qc.invalidateQueries();
        channel = supabase.channel(`rt-${uid}`);
        for (const table of ["meals", "symptoms"]) {
          channel.on("postgres_changes", { event: "*", schema: "public", table, filter: `user_id=eq.${uid}` }, invalidate);
        }
        channel.subscribe((s: string) => {
          if (!active) return;
          if (s === "SUBSCRIBED") setStatus("live");
          else if (s === "CHANNEL_ERROR" || s === "TIMED_OUT" || s === "CLOSED") setStatus("reconnecting");
        });
      } catch (err) {
        console.error("realtime sync setup failed", err);
        if (active) setStatus("offline");
      }
    })();
    return () => { active = false; if (channel) supabase.removeChannel(channel); };
  }, [qc]);
  return status;
}
