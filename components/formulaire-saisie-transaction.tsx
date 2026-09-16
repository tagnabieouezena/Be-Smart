"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

type Categorie = { id: string; libelle: string; type: "fixe" | "variable" | "revenu" };
type LigneRevenuPrevu = { id: string; source: string; montant_estime: number };

const MODES_PAIEMENT = [
  { valeur: "cash", libelle: "Cash" },
  { valeur: "mobile_money", libelle: "Mobile Money" },
  { valeur: "virement", libelle: "Virement" },
  { valeur: "cheque", libelle: "Chèque" },
];

export function FormulaireSaisieTransaction({
  entrepriseId,
  categories,
  lignesRevenuPrevuEnAttente,
}: {
  entrepriseId: string;
  categories: Categorie[];
  lignesRevenuPrevuEnAttente: LigneRevenuPrevu[];
}) {
  const router = useRouter();
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [description, setDescription] = useState("");
  const [type, setType] = useState<"entree" | "sortie">("sortie");
  const categoriesFiltrees = categories.filter((c) =>
    type === "entree" ? c.type === "revenu" : c.type !== "revenu",
  );
  const [categorieId, setCategorieId] = useState(categoriesFiltrees[0]?.id ?? "");
  const [montant, setMontant] = useState("");
  const [modePaiement, setModePaiement] = useState(MODES_PAIEMENT[0].valeur);
  const [notes, setNotes] = useState("");
  const [ligneRevenuPrevuId, setLigneRevenuPrevuId] = useState("");
  const [fichier, setFichier] = useState<File | null>(null);
  const [erreur, setErreur] = useState<string | null>(null);
  const [avertissement, setAvertissement] = useState<string | null>(null);
  const [enCours, setEnCours] = useState(false);

  function changerType(nouveauType: "entree" | "sortie") {
    setType(nouveauType);
    const filtrees = categories.filter((c) =>
      nouveauType === "entree" ? c.type === "revenu" : c.type !== "revenu",
    );
    setCategorieId(filtrees[0]?.id ?? "");
    if (nouveauType === "sortie") {
      setLigneRevenuPrevuId("");
    }
  }

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setErreur(null);
    setAvertissement(null);
    setEnCours(true);

    const supabase = createClient();
    const id = crypto.randomUUID();
    let justificatifPath: string | null = null;

    if (fichier) {
      const chemin = `${entrepriseId}/${id}/${fichier.name}`;
      const { error: uploadError } = await supabase.storage
        .from("justificatifs")
        .upload(chemin, fichier);

      if (uploadError) {
        // Ne bloque pas la saisie (CDC 5.1 : connexion instable) — la
        // transaction reste créable sans justificatif.
        setAvertissement(`Justificatif non enregistré (${uploadError.message}), transaction créée sans.`);
      } else {
        justificatifPath = chemin;
      }
    }

    const { error } = await supabase.from("transactions").insert({
      id,
      entreprise_id: entrepriseId,
      date,
      description,
      categorie_id: categorieId,
      type,
      montant: Number(montant),
      mode_paiement: modePaiement,
      notes: notes || null,
      ligne_revenu_prevu_id: ligneRevenuPrevuId || null,
      justificatif_path: justificatifPath,
    });

    setEnCours(false);

    if (error) {
      setErreur(error.message);
      return;
    }

    setDescription("");
    setMontant("");
    setNotes("");
    setLigneRevenuPrevuId("");
    setFichier(null);
    router.refresh();
  }

  return (
    <form onSubmit={onSubmit} style={{ display: "grid", gap: "0.5rem", maxWidth: 400 }}>
      <h3>Nouvelle saisie</h3>
      <label>
        Date
        <input required type="date" value={date} onChange={(e) => setDate(e.target.value)} />
      </label>
      <label>
        Type
        <select value={type} onChange={(e) => changerType(e.target.value as "entree" | "sortie")}>
          <option value="sortie">Sortie</option>
          <option value="entree">Entrée</option>
        </select>
      </label>
      <label>
        Description
        <input required value={description} onChange={(e) => setDescription(e.target.value)} />
      </label>
      <label>
        Catégorie
        <select value={categorieId} onChange={(e) => setCategorieId(e.target.value)}>
          {categoriesFiltrees.map((c) => (
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
      <label>
        Mode de paiement
        <select value={modePaiement} onChange={(e) => setModePaiement(e.target.value)}>
          {MODES_PAIEMENT.map((m) => (
            <option key={m.valeur} value={m.valeur}>
              {m.libelle}
            </option>
          ))}
        </select>
      </label>
      {type === "entree" && lignesRevenuPrevuEnAttente.length > 0 && (
        <label>
          Rapprocher avec une ligne de CA prévisionnel (optionnel)
          <select
            value={ligneRevenuPrevuId}
            onChange={(e) => setLigneRevenuPrevuId(e.target.value)}
          >
            <option value="">Aucun rapprochement</option>
            {lignesRevenuPrevuEnAttente.map((l) => (
              <option key={l.id} value={l.id}>
                {l.source} ({l.montant_estime} FCFA)
              </option>
            ))}
          </select>
        </label>
      )}
      <label>
        Notes (optionnel)
        <input value={notes} onChange={(e) => setNotes(e.target.value)} />
      </label>
      <label>
        Justificatif (optionnel)
        <input
          type="file"
          accept="image/*,application/pdf"
          onChange={(e) => setFichier(e.target.files?.[0] ?? null)}
        />
      </label>
      {avertissement && <p style={{ color: "darkorange" }}>{avertissement}</p>}
      {erreur && <p style={{ color: "crimson" }}>{erreur}</p>}
      <button type="submit" disabled={enCours}>
        {enCours ? "Enregistrement..." : "Enregistrer"}
      </button>
    </form>
  );
}
