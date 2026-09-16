"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export function FormulaireInvitationComptable() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [nom, setNom] = useState("");
  const [erreur, setErreur] = useState<string | null>(null);
  const [enCours, setEnCours] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setErreur(null);
    setEnCours(true);

    const reponse = await fetch("/api/comptable/inviter", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, nom }),
    });

    setEnCours(false);

    if (!reponse.ok) {
      const { error } = await reponse.json().catch(() => ({ error: "Erreur inconnue." }));
      setErreur(error);
      return;
    }

    setEmail("");
    setNom("");
    router.refresh();
  }

  return (
    <form onSubmit={onSubmit} style={{ display: "grid", gap: "0.5rem", maxWidth: 360 }}>
      <label>
        Nom du comptable
        <input required value={nom} onChange={(e) => setNom(e.target.value)} />
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
      {erreur && <p style={{ color: "crimson" }}>{erreur}</p>}
      <button type="submit" disabled={enCours}>
        {enCours ? "Invitation en cours..." : "Inviter ce comptable"}
      </button>
    </form>
  );
}
