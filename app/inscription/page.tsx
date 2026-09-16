"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export default function InscriptionPage() {
  const router = useRouter();
  const [nomEntreprise, setNomEntreprise] = useState("");
  const [secteur, setSecteur] = useState("");
  const [nomCeo, setNomCeo] = useState("");
  const [email, setEmail] = useState("");
  const [motDePasse, setMotDePasse] = useState("");
  const [erreur, setErreur] = useState<string | null>(null);
  const [enCours, setEnCours] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setErreur(null);
    setEnCours(true);

    const supabase = createClient();

    const { error: signUpError } = await supabase.auth.signUp({
      email,
      password: motDePasse,
    });

    if (signUpError) {
      setErreur(signUpError.message);
      setEnCours(false);
      return;
    }

    // Le compte Auth existe déjà à ce stade même si la RPC ci-dessous échoue.
    // On ne le laisse jamais sans entreprise : en cas d'échec, l'utilisateur
    // peut se reconnecter et retenter (la RPC reste rejouable tant qu'aucune
    // entreprise ne lui a été rattachée).
    const { error: rpcError } = await supabase.rpc("creer_entreprise_et_ceo", {
      p_nom: nomEntreprise,
      p_secteur: secteur,
      p_nom_utilisateur: nomCeo,
    });

    setEnCours(false);

    if (rpcError) {
      setErreur(
        `Compte créé, mais la création de l'entreprise a échoué : ${rpcError.message}. Reconnectez-vous pour réessayer.`,
      );
      return;
    }

    router.push("/utilisateurs");
  }

  return (
    <main style={{ padding: "2rem", maxWidth: 480, fontFamily: "system-ui, sans-serif" }}>
      <h1>Inscription — Be Smart Pilotage</h1>
      <form onSubmit={onSubmit} style={{ display: "grid", gap: "0.75rem" }}>
        <label>
          Nom de l&apos;entreprise
          <input
            required
            value={nomEntreprise}
            onChange={(e) => setNomEntreprise(e.target.value)}
          />
        </label>
        <label>
          Secteur
          <input value={secteur} onChange={(e) => setSecteur(e.target.value)} />
        </label>
        <label>
          Votre nom (CEO)
          <input required value={nomCeo} onChange={(e) => setNomCeo(e.target.value)} />
        </label>
        <label>
          Email
          <input
            required
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />
        </label>
        <label>
          Mot de passe
          <input
            required
            type="password"
            minLength={6}
            value={motDePasse}
            onChange={(e) => setMotDePasse(e.target.value)}
          />
        </label>
        {erreur && <p style={{ color: "crimson" }}>{erreur}</p>}
        <button type="submit" disabled={enCours}>
          {enCours ? "Création en cours..." : "Créer mon entreprise"}
        </button>
      </form>
    </main>
  );
}
