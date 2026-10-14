"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { formaterMontant } from "@/lib/format";
import { aujourdhuiISO, estDateParDefaut, formaterDateLongue } from "@/lib/solde";

// Solde de caisse daté : le montant et sa date sont saisis et enregistrés
// ENSEMBLE (un seul update, atomique). Le montant part en chaîne (jamais de
// Number()). Aucun solde n'est calculé ici : la règle vit dans la base.
export function FormulaireSoldeCaisse({
  entrepriseId,
  soldeInitial,
  dateSoldeInitial,
}: {
  entrepriseId: string;
  soldeInitial: number;
  dateSoldeInitial: string;
}) {
  const router = useRouter();
  const sansDate = estDateParDefaut(dateSoldeInitial);
  const [valeur, setValeur] = useState(String(soldeInitial));
  // Date par défaut : champ vide, le CEO doit choisir une vraie date.
  const [dateSolde, setDateSolde] = useState(sansDate ? "" : dateSoldeInitial);
  const [erreur, setErreur] = useState<string | null>(null);
  const [enCours, setEnCours] = useState(false);

  async function enregistrer(e: React.FormEvent) {
    e.preventDefault();
    setErreur(null);
    setEnCours(true);

    const supabase = createClient();
    const { error } = await supabase
      .from("entreprises")
      .update({ solde_initial: valeur, date_solde_initial: dateSolde })
      .eq("id", entrepriseId);

    setEnCours(false);

    if (error) {
      setErreur(error.message);
      return;
    }

    router.refresh();
  }

  return (
    <section aria-labelledby="titre-solde-caisse">
      <h2 id="titre-solde-caisse">Solde de caisse</h2>
      <p>
        {sansDate
          ? "Aucune date renseignée : toutes les transactions saisies s'ajoutent à ce montant."
          : `Solde de ${formaterMontant(soldeInitial)} à la fin du ${formaterDateLongue(dateSoldeInitial)}.`}
      </p>
      <form onSubmit={enregistrer} style={{ display: "grid", gap: "0.5rem", maxWidth: 420 }}>
        <label>
          Solde de caisse (FCFA)
          <input
            required
            type="number"
            step="any"
            value={valeur}
            onChange={(e) => setValeur(e.target.value)}
          />
        </label>
        <label>
          Date du solde
          <input
            required
            type="date"
            max={aujourdhuiISO()}
            value={dateSolde}
            onChange={(e) => setDateSolde(e.target.value)}
          />
        </label>
        <p style={{ fontSize: "0.9rem" }}>
          Indiquez le solde de votre caisse à la fin de cette journée, après toutes les opérations du jour. Les
          transactions de cette date et des dates antérieures ne s&apos;y ajoutent pas : elles sont déjà dans ce solde.
          L&apos;ordre dans lequel vous saisissez le solde et l&apos;historique n&apos;a aucune importance.
        </p>
        {erreur && <p style={{ color: "var(--color-negatif)" }}>{erreur}</p>}
        <button type="submit" disabled={enCours}>
          {enCours ? "Enregistrement..." : "Enregistrer"}
        </button>
      </form>
    </section>
  );
}
