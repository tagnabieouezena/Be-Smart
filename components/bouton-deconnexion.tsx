"use client";

import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export function BoutonDeconnexion({ className }: { className?: string }) {
  const router = useRouter();

  async function deconnecter() {
    const supabase = createClient();
    await supabase.auth.signOut();
    router.push("/connexion");
    router.refresh();
  }

  return (
    <button type="button" className={className} onClick={deconnecter}>
      Se déconnecter
    </button>
  );
}
