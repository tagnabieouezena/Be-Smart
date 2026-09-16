"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

type TypePeriode = "mensuel" | "trimestriel" | "annuel";

type Objectif = {
  id: string;
  type_periode: TypePeriode;
  annee: number;
  mois: number | null;
  trimestre: number | null;
  montant_cible: number;
};

export function GestionObjectifs({
  objectifs,
  entrepriseId,
}: {
  objectifs: Objectif[];
  entrepriseId: string;
}) {
  const router = useRouter();
  const [typePeriode, setTypePeriode] = useState<TypePeriode>("mensuel");
  const [annee, setAnnee] = useState(new Date().getFullYear());
  const [mois, setMois] = useState(1);
  const [trimestre, setTrimestre] = useState(1);
  const [montantCible, setMontantCible] = useState("");
  const [erreur, setErreur] = useState<string | null>(null);
  const [enCours, setEnCours] = useState(false);

  async function ajouter(e: React.FormEvent) {
    e.preventDefault();
    setErreur(null);
    setEnCours(true);

    const supabase = createClient();
    const { error } = await supabase.from("objectifs_ca").insert({
      entreprise_id: entrepriseId,
      type_periode: typePeriode,
      annee,
      mois: typePeriode === "mensuel" ? mois : null,
      trimestre: typePeriode === "trimestriel" ? trimestre : null,
      montant_cible: Number(montantCible),
    });

    setEnCours(false);

    if (error) {
      setErreur(error.message);
      return;
    }

    setMontantCible("");
    router.refresh();
  }

  return (
    <section>
      <h2>Objectifs de chiffre d&apos;affaires</h2>
      <ul>
        {objectifs.map((o) => (
          <li key={o.id}>
            {o.type_periode} {o.annee}
            {o.mois ? ` — mois ${o.mois}` : ""}
            {o.trimestre ? ` — T${o.trimestre}` : ""} : {o.montant_cible} FCFA
          </li>
        ))}
      </ul>

      <form onSubmit={ajouter} style={{ display: "grid", gap: "0.5rem", maxWidth: 320 }}>
        <label>
          Période
          <select
            value={typePeriode}
            onChange={(e) => setTypePeriode(e.target.value as TypePeriode)}
          >
            <option value="mensuel">Mensuel</option>
            <option value="trimestriel">Trimestriel</option>
            <option value="annuel">Annuel</option>
          </select>
        </label>
        <label>
          Année
          <input
            required
            type="number"
            value={annee}
            onChange={(e) => setAnnee(Number(e.target.value))}
          />
        </label>
        {typePeriode === "mensuel" && (
          <label>
            Mois
            <input
              required
              type="number"
              min={1}
              max={12}
              value={mois}
              onChange={(e) => setMois(Number(e.target.value))}
            />
          </label>
        )}
        {typePeriode === "trimestriel" && (
          <label>
            Trimestre
            <input
              required
              type="number"
              min={1}
              max={4}
              value={trimestre}
              onChange={(e) => setTrimestre(Number(e.target.value))}
            />
          </label>
        )}
        <label>
          Montant cible (FCFA)
          <input
            required
            type="number"
            min={0}
            value={montantCible}
            onChange={(e) => setMontantCible(e.target.value)}
          />
        </label>
        {erreur && <p style={{ color: "crimson" }}>{erreur}</p>}
        <button type="submit" disabled={enCours}>
          {enCours ? "Ajout..." : "Ajouter un objectif"}
        </button>
      </form>
    </section>
  );
}
