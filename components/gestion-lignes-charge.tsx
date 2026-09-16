"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

type LigneCharge = {
  id: string;
  designation: string;
  montant: number;
  categorie_id: string;
  statut: string;
};

type Categorie = { id: string; libelle: string };

export function GestionLignesCharge({
  titre,
  type,
  lignes,
  categories,
  budgetMensuelId,
  entrepriseId,
}: {
  titre: string;
  type: "fixe" | "variable";
  lignes: LigneCharge[];
  categories: Categorie[];
  budgetMensuelId: string;
  entrepriseId: string;
}) {
  const router = useRouter();
  const [designation, setDesignation] = useState("");
  const [categorieId, setCategorieId] = useState(categories[0]?.id ?? "");
  const [montant, setMontant] = useState("");
  const [erreur, setErreur] = useState<string | null>(null);
  const [enCours, setEnCours] = useState(false);

  async function ajouter(e: React.FormEvent) {
    e.preventDefault();
    setErreur(null);
    setEnCours(true);

    const supabase = createClient();
    const { error } = await supabase.from("lignes_charge_prevue").insert({
      budget_mensuel_id: budgetMensuelId,
      entreprise_id: entrepriseId,
      categorie_id: categorieId,
      designation,
      montant: Number(montant),
    });

    setEnCours(false);

    if (error) {
      setErreur(error.message);
      return;
    }

    setDesignation("");
    setMontant("");
    router.refresh();
  }

  async function supprimer(id: string) {
    const supabase = createClient();
    const { error } = await supabase.from("lignes_charge_prevue").delete().eq("id", id);
    if (error) {
      setErreur(error.message);
      return;
    }
    router.refresh();
  }

  return (
    <section>
      <h3>{titre}</h3>
      <ul>
        {lignes.map((l) => (
          <li key={l.id}>
            {l.designation} — {l.montant} FCFA ({l.statut}){" "}
            <button onClick={() => supprimer(l.id)}>Supprimer</button>
          </li>
        ))}
      </ul>

      {categories.length === 0 ? (
        <p>Aucune catégorie de type {type} — crée-la d&apos;abord dans Paramétrage.</p>
      ) : (
        <form onSubmit={ajouter} style={{ display: "grid", gap: "0.5rem", maxWidth: 320 }}>
          <label>
            Désignation
            <input required value={designation} onChange={(e) => setDesignation(e.target.value)} />
          </label>
          <label>
            Catégorie
            <select value={categorieId} onChange={(e) => setCategorieId(e.target.value)}>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.libelle}
                </option>
              ))}
            </select>
          </label>
          <label>
            Montant (FCFA)
            <input
              required
              type="number"
              min={0}
              value={montant}
              onChange={(e) => setMontant(e.target.value)}
            />
          </label>
          {erreur && <p style={{ color: "crimson" }}>{erreur}</p>}
          <button type="submit" disabled={enCours}>
            {enCours ? "Ajout..." : "Ajouter"}
          </button>
        </form>
      )}
    </section>
  );
}
