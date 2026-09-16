"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

type LigneRevenu = {
  id: string;
  source: string;
  montant_estime: number;
  statut: string;
};

export function GestionLignesRevenu({
  lignes,
  budgetMensuelId,
  entrepriseId,
}: {
  lignes: LigneRevenu[];
  budgetMensuelId: string;
  entrepriseId: string;
}) {
  const router = useRouter();
  const [source, setSource] = useState("");
  const [montantEstime, setMontantEstime] = useState("");
  const [erreur, setErreur] = useState<string | null>(null);
  const [enCours, setEnCours] = useState(false);

  async function ajouter(e: React.FormEvent) {
    e.preventDefault();
    setErreur(null);
    setEnCours(true);

    const supabase = createClient();
    const { error } = await supabase.from("lignes_revenu_prevu").insert({
      budget_mensuel_id: budgetMensuelId,
      entreprise_id: entrepriseId,
      source,
      montant_estime: Number(montantEstime),
    });

    setEnCours(false);

    if (error) {
      setErreur(error.message);
      return;
    }

    setSource("");
    setMontantEstime("");
    router.refresh();
  }

  async function supprimer(id: string) {
    const supabase = createClient();
    const { error } = await supabase.from("lignes_revenu_prevu").delete().eq("id", id);
    if (error) {
      setErreur(error.message);
      return;
    }
    router.refresh();
  }

  return (
    <section>
      <h3>Revenus prévus</h3>
      <ul>
        {lignes.map((l) => (
          <li key={l.id}>
            {l.source} — {l.montant_estime} FCFA ({l.statut}){" "}
            <button onClick={() => supprimer(l.id)}>Supprimer</button>
          </li>
        ))}
      </ul>

      <form onSubmit={ajouter} style={{ display: "grid", gap: "0.5rem", maxWidth: 320 }}>
        <label>
          Source
          <input required value={source} onChange={(e) => setSource(e.target.value)} />
        </label>
        <label>
          Montant estimé (FCFA)
          <input
            required
            type="number"
            min={0}
            value={montantEstime}
            onChange={(e) => setMontantEstime(e.target.value)}
          />
        </label>
        {erreur && <p style={{ color: "crimson" }}>{erreur}</p>}
        <button type="submit" disabled={enCours}>
          {enCours ? "Ajout..." : "Ajouter"}
        </button>
      </form>
    </section>
  );
}
