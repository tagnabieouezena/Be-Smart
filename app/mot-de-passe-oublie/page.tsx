"use client";

import { useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";

export default function MotDePasseOubliePage() {
  const [email, setEmail] = useState("");
  const [envoye, setEnvoye] = useState(false);
  const [enCours, setEnCours] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setEnCours(true);

    const supabase = createClient();
    // Réponse identique que l'adresse existe ou non : le résultat (et toute
    // erreur) est volontairement ignoré, pour ne pas révéler quels comptes existent.
    await supabase.auth.resetPasswordForEmail(email).catch(() => undefined);

    setEnCours(false);
    setEnvoye(true);
  }

  return (
    <main style={{ padding: "2rem", maxWidth: 480, fontFamily: "system-ui, sans-serif" }}>
      <h1>Mot de passe oublié</h1>
      {envoye ? (
        <>
          <p role="status">
            Si un compte existe pour cette adresse, un e-mail contenant un lien de réinitialisation vient
            d&apos;être envoyé.
          </p>
          <p>
            <Link href="/connexion">Retour à la connexion</Link>
          </p>
        </>
      ) : (
        <form onSubmit={onSubmit} style={{ display: "grid", gap: "0.75rem" }}>
          <label>
            Email
            <input required type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
          </label>
          <button type="submit" disabled={enCours}>
            {enCours ? "Envoi..." : "Envoyer le lien de réinitialisation"}
          </button>
          <p>
            <Link href="/connexion">Retour à la connexion</Link>
          </p>
        </form>
      )}
    </main>
  );
}
