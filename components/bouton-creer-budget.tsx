"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export function BoutonCreerBudget({
  entrepriseId,
  mois,
  annee,
}: {
  entrepriseId: string;
  mois: number;
  annee: number;
}) {
  const router = useRouter();
  const [erreur, setErreur] = useState<string | null>(null);
  const [enCours, setEnCours] = useState(false);

  async function creer() {
    setErreur(null);
    setEnCours(true);

    const supabase = createClient();
    const { error } = await supabase
      .from("budgets_mensuels")
      .insert({ entreprise_id: entrepriseId, mois, annee });

    setEnCours(false);

    if (error) {
      setErreur(error.message);
      return;
    }

    router.refresh();
  }

  return (
    <div>
      <p>Aucun budget pour {mois}/{annee}.</p>
      <button onClick={creer} disabled={enCours}>
        {enCours ? "Création..." : "Créer le budget de ce mois"}
      </button>
      {erreur && <p style={{ color: "crimson" }}>{erreur}</p>}
    </div>
  );
}
