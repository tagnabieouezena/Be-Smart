"use client";

import { useRouter, useSearchParams } from "next/navigation";

type Categorie = { id: string; libelle: string };
type Utilisateur = { id: string; nom: string };

const MODES_PAIEMENT = [
  { valeur: "cash", libelle: "Cash" },
  { valeur: "mobile_money", libelle: "Mobile Money" },
  { valeur: "virement", libelle: "Virement" },
  { valeur: "cheque", libelle: "Chèque" },
];

export function FiltresTransactions({
  categories,
  utilisateurs,
}: {
  categories: Categorie[];
  utilisateurs: Utilisateur[];
}) {
  const router = useRouter();
  const searchParams = useSearchParams();

  function setParam(cle: string, valeur: string) {
    const params = new URLSearchParams(searchParams.toString());
    if (valeur) {
      params.set(cle, valeur);
    } else {
      params.delete(cle);
    }
    router.push(`/transactions?${params.toString()}`);
  }

  return (
    <div style={{ display: "flex", gap: "0.5rem", flexWrap: "wrap", alignItems: "center" }}>
      <label>
        Du
        <input
          type="date"
          defaultValue={searchParams.get("date_debut") ?? ""}
          onChange={(e) => setParam("date_debut", e.target.value)}
        />
      </label>
      <label>
        Au
        <input
          type="date"
          defaultValue={searchParams.get("date_fin") ?? ""}
          onChange={(e) => setParam("date_fin", e.target.value)}
        />
      </label>
      <label>
        Catégorie
        <select
          defaultValue={searchParams.get("categorie_id") ?? ""}
          onChange={(e) => setParam("categorie_id", e.target.value)}
        >
          <option value="">Toutes</option>
          {categories.map((c) => (
            <option key={c.id} value={c.id}>
              {c.libelle}
            </option>
          ))}
        </select>
      </label>
      <label>
        Responsable
        <select
          defaultValue={searchParams.get("saisi_par") ?? ""}
          onChange={(e) => setParam("saisi_par", e.target.value)}
        >
          <option value="">Tous</option>
          {utilisateurs.map((u) => (
            <option key={u.id} value={u.id}>
              {u.nom}
            </option>
          ))}
        </select>
      </label>
      <label>
        Mode de paiement
        <select
          defaultValue={searchParams.get("mode_paiement") ?? ""}
          onChange={(e) => setParam("mode_paiement", e.target.value)}
        >
          <option value="">Tous</option>
          {MODES_PAIEMENT.map((m) => (
            <option key={m.valeur} value={m.valeur}>
              {m.libelle}
            </option>
          ))}
        </select>
      </label>
    </div>
  );
}
