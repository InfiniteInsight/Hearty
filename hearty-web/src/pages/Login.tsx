import { Button } from "@/components/ui/button";
import { signInWithGoogle } from "../lib/auth";

export default function Login() {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-6 px-6 text-center">
      <h1 className="font-display text-5xl">
        <span>Heart</span><span className="text-brand">y</span>
      </h1>
      <p className="text-text-muted">Your food &amp; symptom journal, on the big screen.</p>
      <Button onClick={() => signInWithGoogle()} className="bg-brand text-black">
        Continue with Google
      </Button>
    </div>
  );
}
