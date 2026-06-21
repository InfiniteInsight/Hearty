import { useQueryClient } from "@tanstack/react-query";
import SyncIndicator, { type SyncStatus } from "./SyncIndicator";
import { Button } from "@/components/ui/button";
import { signOut } from "../../lib/auth";
export default function Header({ status }: { status: SyncStatus }) {
  const qc = useQueryClient();
  return (
    <header className="flex items-center justify-between border-b border-surface-border px-6 py-3">
      <SyncIndicator status={status} />
      <div className="flex items-center gap-2">
        <Button variant="ghost" size="sm" onClick={() => qc.invalidateQueries()}>Refresh</Button>
        <Button variant="ghost" size="sm" onClick={() => signOut()}>Sign out</Button>
      </div>
    </header>
  );
}
