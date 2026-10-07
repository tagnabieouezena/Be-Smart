"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { FormulaireSaisieTransaction } from "@/components/formulaire-saisie-transaction";

export type LigneCreance = {
  id: string;
  client: string;
  montant_du: number;
  date_facturation: string;
  echeance: string;
  notes: string | null;
  montant_encaisse: number;
  reste_du: number;
  statut: "en_attente" | "partiellement_paye" | "paye" | "en_retard";
  jours_retard: number;
  tranche: string | null;
};

type Categorie = { id: string; libelle: string; type: "fixe" | "variable" | "revenu" };

const LIBELLES_STATUT: Record<LigneCreance["statut"], string> = {
  en_attente: "En attente",
  partiellement_paye: "Partiellement payé",
  paye: "Payé",
  en_retard: "En retard",
};

const formatMontant = new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 0 });
const montant = (v: number) => `${formatMontant.format(v)} FCFA`;

const cellule = { padding: "0.4rem 0.6rem", borderBottom: "1px solid #ddd", whiteSpace: "nowrap" as const };

function aujourdhui() {
  return new Date().toISOString().slice(0, 10);
}

function FormulaireCreance({
  entrepriseId,
  creance,
  onTermine,
}: {
  entrepriseId: string;
  creance?: LigneCreance;
  onTermine: () => void;
}) {
  const router = useRouter();
  const [client, setClient] = useState(creance?.client ?? "");
  const [montantDu, setMontantDu] = useState(creance ? String(creance.montant_du) : "");
  const [dateFacturation, setDateFacturation] = useState(creance?.date_facturation ?? aujourdhui());
  const [echeance, setEcheance] = useState(creance?.echeance ?? aujourdhui());
  const [notes, setNotes] = useState(creance?.notes ?? "");
  const [erreur, setErreur] = useState<string | null>(null);
  const [enCours, setEnCours] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setErreur(null);
    setEnCours(true);

    const supabase = createClient();
    // Le montant part en chaîne : PostgREST le caste directement en numeric,
    // sans passage par un float JavaScript. saisi_par est forcé côté serveur.
    const valeurs = {
      client: client.trim(),
      montant_du: montantDu,
      date_facturation: dateFacturation,
      echeance,
      notes: notes || null,
    };

    const { error } = creance
      ? await supabase.from("creances").update(valeurs).eq("id", creance.id)
      : await supabase.from("creances").insert({ ...valeurs, entreprise_id: entrepriseId });

    setEnCours(false);

    if (error) {
      setErreur(error.message);
      return;
    }

    router.refresh();
    onTermine();
  }

  return (
    <form onSubmit={onSubmit} style={{ display: "grid", gap: "0.5rem", maxWidth: 400, margin: "1rem 0" }}>
      <h3>{creance ? `Modifier la créance — ${creance.client}` : "Nouvelle créance"}</h3>
      <label>
        Client
        <input required value={client} onChange={(e) => setClient(e.target.value)} />
      </label>
      <label>
        Montant dû (FCFA)
        <input
          required
          type="number"
          min={1}
          step="any"
          value={montantDu}
          onChange={(e) => setMontantDu(e.target.value)}
        />
      </label>
      <label>
        Date de facturation
        <input required type="date" value={dateFacturation} onChange={(e) => setDateFacturation(e.target.value)} />
      </label>
      <label>
        Échéance
        <input required type="date" min={dateFacturation} value={echeance} onChange={(e) => setEcheance(e.target.value)} />
      </label>
      <label>
        Notes (optionnel)
        <input value={notes} onChange={(e) => setNotes(e.target.value)} />
      </label>
      {erreur && <p style={{ color: "crimson" }}>{erreur}</p>}
      <div style={{ display: "flex", gap: "0.5rem" }}>
        <button type="submit" disabled={enCours}>
          {enCours ? "Enregistrement..." : "Enregistrer"}
        </button>
        <button type="button" onClick={onTermine}>
          Annuler
        </button>
      </div>
    </form>
  );
}

export function GestionCreances({
  creances,
  estComptable,
  entrepriseId,
  categories,
}: {
  creances: LigneCreance[];
  estComptable: boolean;
  entrepriseId: string;
  categories: Categorie[];
}) {
  const router = useRouter();
  const [creation, setCreation] = useState(false);
  const [edition, setEdition] = useState<LigneCreance | null>(null);
  const [paiement, setPaiement] = useState<LigneCreance | null>(null);
  const [erreur, setErreur] = useState<string | null>(null);

  async function supprimer(creance: LigneCreance) {
    setErreur(null);
    const supabase = createClient();
    const { error } = await supabase.from("creances").delete().eq("id", creance.id);
    if (error) {
      setErreur(error.message);
      return;
    }
    router.refresh();
  }

  return (
    <div>
      {erreur && <p style={{ color: "crimson" }}>{erreur}</p>}

      {creances.length === 0 ? (
        <p>Aucune créance.</p>
      ) : (
        <div style={{ overflowX: "auto", maxWidth: "100%" }}>
          <table style={{ borderCollapse: "collapse", minWidth: "900px" }}>
            <thead>
              <tr>
                {["Client", "Montant dû", "Encaissé", "Reste dû", "Échéance", "Statut", "Jours de retard"].map((t) => (
                  <th key={t} style={{ ...cellule, textAlign: "left" }}>
                    {t}
                  </th>
                ))}
                {estComptable && <th style={cellule}>Actions</th>}
              </tr>
            </thead>
            <tbody>
              {creances.map((c) => (
                <tr key={c.id}>
                  <td style={cellule}>{c.client}</td>
                  <td style={cellule}>{montant(c.montant_du)}</td>
                  <td style={cellule}>{montant(c.montant_encaisse)}</td>
                  <td style={cellule}>{montant(c.reste_du)}</td>
                  <td style={cellule}>{c.echeance}</td>
                  <td style={cellule}>
                    {c.statut === "en_retard" ? (
                      <strong style={{ color: "crimson", border: "1px solid crimson", padding: "0 0.3rem" }}>
                        <span aria-hidden="true">⚠ </span>
                        {LIBELLES_STATUT[c.statut]}
                      </strong>
                    ) : (
                      LIBELLES_STATUT[c.statut]
                    )}
                  </td>
                  <td style={cellule}>{c.jours_retard > 0 ? `${c.jours_retard} j` : "—"}</td>
                  {estComptable && (
                    <td style={cellule}>
                      {c.reste_du > 0 && (
                        <button
                          type="button"
                          onClick={() => {
                            setPaiement(c);
                            setEdition(null);
                            setCreation(false);
                          }}
                        >
                          Enregistrer un paiement
                        </button>
                      )}{" "}
                      <button
                        type="button"
                        onClick={() => {
                          setEdition(c);
                          setPaiement(null);
                          setCreation(false);
                        }}
                      >
                        Modifier
                      </button>
                      {c.montant_encaisse === 0 && (
                        <>
                          {" "}
                          <button type="button" onClick={() => supprimer(c)}>
                            Supprimer
                          </button>
                        </>
                      )}
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {estComptable && (
        <div style={{ marginTop: "1.5rem" }}>
          {!creation && !edition && !paiement && (
            <button type="button" onClick={() => setCreation(true)}>
              Nouvelle créance
            </button>
          )}
          {creation && <FormulaireCreance entrepriseId={entrepriseId} onTermine={() => setCreation(false)} />}
          {edition && (
            <FormulaireCreance
              key={edition.id}
              entrepriseId={entrepriseId}
              creance={edition}
              onTermine={() => setEdition(null)}
            />
          )}
          {paiement && (
            <div>
              <FormulaireSaisieTransaction
                key={paiement.id}
                entrepriseId={entrepriseId}
                categories={categories}
                lignesRevenuPrevuEnAttente={[]}
                paiementCreance={{
                  creanceId: paiement.id,
                  client: paiement.client,
                  resteDu: paiement.reste_du,
                  onTermine: () => setPaiement(null),
                }}
              />
              <button type="button" onClick={() => setPaiement(null)}>
                Annuler
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
