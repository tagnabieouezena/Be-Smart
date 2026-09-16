"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export function ActionsBudget({
  budgetMensuelId,
  statut,
}: {
  budgetMensuelId: string;
  statut: string;
}) {
  const router = useRouter();
  const [message, setMessage] = useState<string | null>(null);
  const [enCours, setEnCours] = useState(false);

  async function dupliquer() {
    setEnCours(true);
    setMessage(null);

    const supabase = createClient();
    const { data, error } = await supabase.rpc(
      "dupliquer_charges_fixes_mois_precedent",
      { p_budget_mensuel_id: budgetMensuelId },
    );

    setEnCours(false);

    if (error) {
      setMessage(error.message);
      return;
    }

    setMessage(`${data} charge(s) fixe(s) dupliquée(s) depuis le mois précédent.`);
    router.refresh();
  }

  async function valider() {
    setEnCours(true);
    setMessage(null);

    const supabase = createClient();
    const { error } = await supabase
      .from("budgets_mensuels")
      .update({ statut: "valide" })
      .eq("id", budgetMensuelId);

    setEnCours(false);

    if (error) {
      setMessage(error.message);
      return;
    }

    router.refresh();
  }

  return (
    <div style={{ display: "flex", gap: "0.5rem", alignItems: "center" }}>
      <button onClick={dupliquer} disabled={enCours}>
        Dupliquer les charges fixes du mois précédent
      </button>
      {statut !== "valide" && (
        <button onClick={valider} disabled={enCours}>
          Valider le budget
        </button>
      )}
      {statut === "valide" && <span>Budget validé</span>}
      {message && <span>{message}</span>}
    </div>
  );
}
