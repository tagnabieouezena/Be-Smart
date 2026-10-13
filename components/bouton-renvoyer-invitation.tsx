"use client";

import { useState } from "react";

export function BoutonRenvoyerInvitation({ utilisateurId }: { utilisateurId: string }) {
  const [etat, setEtat] = useState<"repos" | "envoi" | "envoye" | "erreur">("repos");
  const [message, setMessage] = useState<string | null>(null);

  async function renvoyer() {
    setEtat("envoi");
    setMessage(null);

    const reponse = await fetch("/api/comptable/renvoyer-invitation", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id: utilisateurId }),
    });

    if (reponse.ok) {
      setEtat("envoye");
      return;
    }

    const corps = await reponse.json().catch(() => ({}));
    setEtat("erreur");
    setMessage(corps.error ?? "Échec de l'envoi.");
  }

  return (
    <span>
      <button type="button" onClick={renvoyer} disabled={etat === "envoi"}>
        {etat === "envoi" ? "Envoi..." : "Renvoyer l'invitation"}
      </button>{" "}
      {etat === "envoye" && <span role="status">Invitation renvoyée.</span>}
      {etat === "erreur" && <span role="alert" style={{ color: "crimson" }}>{message}</span>}
    </span>
  );
}
