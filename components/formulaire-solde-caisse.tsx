"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export function FormulaireSoldeInitial({
  entrepriseId,
  soldeInitial,
}: {
  entrepriseId: string;
  soldeInitial: number;
}) {
  const router = useRouter();
  const [valeur, setValeur] = useState(String(soldeInitial));
  const [erreur, setErreur] = useState<string | null>(null);
  const [enCours, setEnCours] = useState(false);

  async function enregistrer(e: React.FormEvent) {
    e.preventDefault();
    setErreur(null);
    setEnCours(true);

    const supabase = createClient();
    const { error } = await supabase
      .from("entreprises")
      .update({ solde_initial: Number(valeur) })
      .eq("id", entrepriseId);

    setEnCours(false);

    if (error) {
      setErreur(error.message);
      return;
    }

    router.refresh();
  }

  return (
    <section>
      <h2>Solde de caisse initial</h2>
      <form onSubmit={enregistrer} style={{ display: "grid", gap: "0.5rem", maxWidth: 320 }}>
        <label>
          Solde initial (FCFA)
          <input
            required
            type="number"
            value={valeur}
            onChange={(e) => setValeur(e.target.value)}
          />
        </label>
        {erreur && <p style={{ color: "crimson" }}>{erreur}</p>}
        <button type="submit" disabled={enCours}>
          {enCours ? "Enregistrement..." : "Enregistrer"}
        </button>
      </form>
    </section>
  );
}
