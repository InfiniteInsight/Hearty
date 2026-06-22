import { useCallback, useEffect, useRef, useState } from "react";
import { api } from "../lib/api";
import type { ConversationTurn, ProposedVerdict, ProposedExperiment } from "@/types/api";

export function useConversation() {
  const [history, setHistory] = useState<ConversationTurn[]>([]);
  const [proposedVerdict, setProposedVerdict] = useState<ProposedVerdict | null>(null);
  const [proposedExperiment, setProposedExperiment] = useState<ProposedExperiment | null>(null);
  const [isClosing, setIsClosing] = useState(false);
  const [isSending, setIsSending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const didInit = useRef(false);

  const apply = useCallback((res: { reply: string; proposed_verdict?: ProposedVerdict | null; proposed_experiment?: ProposedExperiment | null; is_closing: boolean }) => {
    setHistory((h) => [...h, { role: "assistant", content: res.reply }]);
    setProposedVerdict(res.proposed_verdict ?? null);
    setProposedExperiment(res.proposed_experiment ?? null);
    if (res.is_closing) setIsClosing(true);
  }, []);

  // Opener (guarded against StrictMode double-invoke).
  useEffect(() => {
    if (didInit.current) return;
    didInit.current = true;
    setIsSending(true);
    api.trendsConversation({ history: [] })
      .then(apply)
      .catch(() => setError("Couldn't start the conversation."))
      .finally(() => setIsSending(false));
  }, [apply]);

  const send = useCallback(async (content: string) => {
    const text = content.trim();
    if (!text || isSending || isClosing) return;
    const next = [...history, { role: "user" as const, content: text }];
    setHistory(next);
    setProposedVerdict(null);
    setProposedExperiment(null);
    setIsSending(true);
    setError(null);
    try {
      const res = await api.trendsConversation({ history: next });
      apply(res);
    } catch {
      setError("Couldn't send. Try again.");
    } finally {
      setIsSending(false);
    }
  }, [history, isSending, isClosing, apply]);

  const clearProposals = useCallback(() => {
    setProposedVerdict(null);
    setProposedExperiment(null);
  }, []);

  return { history, proposedVerdict, proposedExperiment, isClosing, isSending, error, send, clearProposals };
}
