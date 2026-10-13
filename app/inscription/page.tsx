"use client";

import { useState } from "react";
import Link from "next/link";
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
  const [emailEnvoye, setEmailEnvoye] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setErreur(null);
    setEnCours(true);

    const supabase = createClient();

    // Les noms saisis voyagent dans les métadonnées de l'utilisateur ; ils ne
    // servent qu'à NOMMER l'entreprise et le CEO (jamais un rôle ni un
    // entreprise_id). L'entreprise est créée à la confirmation de l'e-mail.
    const { data, error: signUpError } = await supabase.auth.signUp({
      email,
      password: motDePasse,
      options: {
        data: { nom_entreprise: nomEntreprise, secteur, nom_ceo: nomCeo },
      },
    });

    if (signUpError) {
      setErreur(signUpError.message);
      setEnCours(false);
      return;
    }

    // Confirmation d'e-mail activée (cas normal) : pas de session tant que le
    // lien n'a pas été cliqué.
    if (!data.session) {
      setEnCours(false);
      setEmailEnvoye(true);
      return;
    }

    // Confirmation désactivée (environnement de test) : session immédiate.
    const { error: rpcError } = await supabase.rpc("creer_entreprise_et_ceo", {
      p_nom: nomEntreprise,
      p_secteur: secteur,
      p_nom_utilisateur: nomCeo,
    });

    setEnCours(false);

    if (rpcError) {
      setErreur(`La création de l'entreprise a échoué : ${rpcError.message}. Reconnectez-vous pour réessayer.`);
      return;
    }

    router.push("/parametrage");
  }

  if (emailEnvoye) {
    return (
      <main style={{ padding: "2rem", maxWidth: 480, fontFamily: "system-ui, sans-serif" }}>
        <h1>Vérifiez votre boîte e-mail</h1>
        <p role="status">
          Un e-mail de confirmation a été envoyé à <strong>{email}</strong>. Cliquez sur le lien qu&apos;il
          contient pour confirmer votre adresse : votre entreprise sera alors créée et vous arriverez
          sur le paramétrage.
        </p>
        <p>
          <Link href="/connexion">Retour à la connexion</Link>
        </p>
      </main>
    );
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
