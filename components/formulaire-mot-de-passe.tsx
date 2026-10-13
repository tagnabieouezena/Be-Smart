"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export function FormulaireMotDePasse({ bouton }: { bouton: string }) {
  const router = useRouter();
  const [motDePasse, setMotDePasse] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [erreur, setErreur] = useState<string | null>(null);
  const [enCours, setEnCours] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setErreur(null);

    if (motDePasse !== confirmation) {
      setErreur("Les deux mots de passe ne sont pas identiques.");
      return;
    }

    setEnCours(true);
    const supabase = createClient();
    // mot_de_passe_defini : repère d'affichage (« compte activé » côté CEO),
    // sans effet sur les droits.
    const { error } = await supabase.auth.updateUser({
      password: motDePasse,
      data: { mot_de_passe_defini: true },
    });

    if (error) {
      setEnCours(false);
      setErreur(error.message);
      return;
    }

    router.push("/");
    router.refresh();
  }

  return (
    <form onSubmit={onSubmit} style={{ display: "grid", gap: "0.75rem" }}>
      <label>
        Nouveau mot de passe
        <input required type="password" minLength={6} autoComplete="new-password" value={motDePasse} onChange={(e) => setMotDePasse(e.target.value)} />
      </label>
      <label>
        Confirmer le mot de passe
        <input required type="password" minLength={6} autoComplete="new-password" value={confirmation} onChange={(e) => setConfirmation(e.target.value)} />
      </label>
      {erreur && <p style={{ color: "crimson" }}>{erreur}</p>}
      <button type="submit" disabled={enCours}>
        {enCours ? "Enregistrement..." : bouton}
      </button>
    </form>
  );
}
