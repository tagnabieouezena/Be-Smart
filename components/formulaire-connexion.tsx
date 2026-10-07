"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

function messageErreur(message: string) {
  if (message.includes("Email not confirmed")) {
    return "Adresse e-mail non confirmée : cliquez d'abord sur le lien reçu par e-mail.";
  }
  if (message.includes("Invalid login credentials")) {
    return "E-mail ou mot de passe incorrect.";
  }
  return message;
}

// `suite` a déjà été validée côté serveur (chemin interne uniquement) ; sans
// elle on passe par « / » qui renvoie vers l'accueil du rôle.
export function FormulaireConnexion({ suite }: { suite: string | null }) {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [motDePasse, setMotDePasse] = useState("");
  const [erreur, setErreur] = useState<string | null>(null);
  const [enCours, setEnCours] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setErreur(null);
    setEnCours(true);

    const supabase = createClient();
    const { error } = await supabase.auth.signInWithPassword({
      email,
      password: motDePasse,
    });

    if (error) {
      setEnCours(false);
      setErreur(messageErreur(error.message));
      return;
    }

    router.push(suite ?? "/");
    router.refresh();
  }

  return (
    <form onSubmit={onSubmit} style={{ display: "grid", gap: "0.75rem" }}>
      <label>
        Email
        <input required type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
      </label>
      <label>
        Mot de passe
        <input required type="password" value={motDePasse} onChange={(e) => setMotDePasse(e.target.value)} />
      </label>
      {erreur && <p style={{ color: "crimson" }}>{erreur}</p>}
      <button type="submit" disabled={enCours}>
        {enCours ? "Connexion..." : "Se connecter"}
      </button>
      <p>
        <Link href="/mot-de-passe-oublie">Mot de passe oublié ?</Link>
      </p>
    </form>
  );
}
