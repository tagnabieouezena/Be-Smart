import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

type LigneEcart = {
  mois: number;
  statut_mois: "clos" | "en_cours" | "futur";
  a_budget: boolean;
  revenus_prevu: number | null;
  revenus_reel: number;
  revenus_ecart: number | null;
  revenus_ecart_pct: number | null;
  depenses_prevu: number | null;
  depenses_reel: number;
  depenses_ecart: number | null;
  depenses_ecart_pct: number | null;
  resultat_prevu: number | null;
  resultat_reel: number;
  resultat_ecart: number | null;
  resultat_ecart_pct: number | null;
  solde_debut: number;
  solde_fin_prevu: number | null;
  solde_fin_reel: number;
  solde_fin_ecart: number | null;
  alerte_revenus: boolean;
  alerte_depenses: boolean;
  depense_non_prevue: boolean;
  alerte_solde_negatif: boolean;
};

const NOMS_MOIS = [
  "Janvier",
  "Février",
  "Mars",
  "Avril",
  "Mai",
  "Juin",
  "Juillet",
  "Août",
  "Septembre",
  "Octobre",
  "Novembre",
  "Décembre",
];

const formatMontant = new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 0 });
const formatPct = new Intl.NumberFormat("fr-FR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

function montant(valeur: number | null) {
  return valeur === null ? "—" : `${formatMontant.format(valeur)} FCFA`;
}

// Le sens de l'écart ne repose jamais sur la couleur seule : signe + icône.
function Ecart({
  valeur,
  pct,
  favorableSiPositif,
  alerte,
}: {
  valeur: number | null;
  pct?: number | null;
  favorableSiPositif: boolean;
  alerte?: boolean;
}) {
  if (valeur === null) return <>—</>;
  if (valeur === 0) return <>= 0</>;

  const favorable = favorableSiPositif ? valeur > 0 : valeur < 0;
  const signe = valeur > 0 ? "+" : "−";
  const icone = favorable ? "▲" : "▼";
  const libelle = favorable ? "favorable" : "défavorable";

  return (
    <span style={{ color: favorable ? "seagreen" : "crimson", fontWeight: alerte ? 700 : 400 }}>
      <span aria-label={libelle} title={libelle}>
        {icone}
      </span>{" "}
      {signe}
      {formatMontant.format(Math.abs(valeur))}
      {pct !== null && pct !== undefined && (
        <>
          {" "}
          ({pct > 0 ? "+" : pct < 0 ? "−" : ""}
          {formatPct.format(Math.abs(pct))} %)
        </>
      )}
      {alerte && (
        <>
          {" "}
          <span role="img" aria-label="alerte : écart significatif" title="Écart défavorable significatif">
            ⚠
          </span>
        </>
      )}
    </span>
  );
}

const cellule = { padding: "0.4rem 0.6rem", borderBottom: "1px solid #ddd", whiteSpace: "nowrap" as const };

export default async function EcartsPage({
  searchParams,
}: {
  searchParams: Promise<{ annee?: string }>;
}) {
  const params = await searchParams;
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/connexion");
  }

  const { data: profil } = await supabase
    .from("utilisateurs")
    .select("role")
    .eq("id", user.id)
    .single();

  // Contrôle côté serveur — la fonction SQL renvoie de toute façon zéro ligne
  // à un non-CEO, mais la page n'a pas à s'afficher pour un comptable.
  if (!profil || profil.role !== "ceo") {
    notFound();
  }

  const anneeEnCours = new Date().getFullYear();
  const anneeDemandee = Number.parseInt(params.annee ?? "", 10);
  const annee =
    Number.isInteger(anneeDemandee) && anneeDemandee >= 2000 && anneeDemandee <= 2100
      ? anneeDemandee
      : anneeEnCours;

  const { data, error } = await supabase.rpc("ecarts_mensuels", { p_annee: annee });
  const lignes = (data ?? []) as LigneEcart[];
  const moisSoldeNegatif = lignes.filter((l) => l.alerte_solde_negatif);

  return (
    <main style={{ padding: "2rem", fontFamily: "system-ui, sans-serif" }}>
      <h1>Suivi des écarts — Prévu vs Réel</h1>

      <form method="get" style={{ display: "flex", gap: "0.5rem", alignItems: "center", margin: "1rem 0" }}>
        <label>
          Année{" "}
          <input type="number" name="annee" defaultValue={annee} min={2000} max={2100} />
        </label>
        <button type="submit">Afficher</button>
      </form>

      {error && <p style={{ color: "crimson" }}>Impossible de charger les écarts : {error.message}</p>}

      {moisSoldeNegatif.length > 0 && (
        <div
          role="alert"
          style={{ border: "2px solid crimson", padding: "0.75rem 1rem", margin: "1rem 0", background: "#fff5f5", color: "#7a0019" }}
        >
          <strong>⚠ Solde de caisse prévisionnel négatif</strong> à la fin de :{" "}
          {moisSoldeNegatif
            .map((l) => `${NOMS_MOIS[l.mois - 1]} (${montant(l.solde_fin_prevu)})`)
            .join(", ")}
          .
        </div>
      )}

      {lignes.length === 0 && !error && <p>Aucun budget ni transaction pour {annee}.</p>}

      {lignes.length > 0 && (
        <div style={{ overflowX: "auto", maxWidth: "100%" }}>
          <table style={{ borderCollapse: "collapse", minWidth: "1400px" }}>
            <thead>
              <tr>
                <th rowSpan={2} style={cellule}>Mois</th>
                <th colSpan={3} style={cellule}>Revenus</th>
                <th colSpan={3} style={cellule}>Dépenses</th>
                <th colSpan={3} style={cellule}>Résultat</th>
                <th rowSpan={2} style={cellule}>Solde de début</th>
                <th colSpan={3} style={cellule}>Solde de fin</th>
              </tr>
              <tr>
                {["Prévu", "Réel", "Écart", "Prévu", "Réel", "Écart", "Prévu", "Réel", "Écart", "Prévu", "Réel", "Écart"].map(
                  (titre, i) => (
                    <th key={i} style={cellule}>
                      {titre}
                    </th>
                  ),
                )}
              </tr>
            </thead>
            <tbody>
              {lignes.map((l) => (
                <tr key={l.mois}>
                  <td style={cellule}>
                    <strong>{NOMS_MOIS[l.mois - 1]}</strong>
                    {l.statut_mois === "en_cours" && <em> — à date</em>}
                    {!l.a_budget && <em> — Pas de budget</em>}
                    {l.depense_non_prevue && (
                      <span style={{ marginLeft: "0.5rem", border: "1px solid darkorange", padding: "0 0.3rem", color: "#8a4b00" }}>
                        ⚠ dépense non prévue
                      </span>
                    )}
                  </td>
                  <td style={cellule}>{montant(l.revenus_prevu)}</td>
                  <td style={cellule}>{montant(l.revenus_reel)}</td>
                  <td style={cellule}>
                    <Ecart valeur={l.revenus_ecart} pct={l.revenus_ecart_pct} favorableSiPositif alerte={l.alerte_revenus} />
                  </td>
                  <td style={cellule}>{montant(l.depenses_prevu)}</td>
                  <td style={cellule}>{montant(l.depenses_reel)}</td>
                  <td style={cellule}>
                    <Ecart
                      valeur={l.depenses_ecart}
                      pct={l.depenses_ecart_pct}
                      favorableSiPositif={false}
                      alerte={l.alerte_depenses}
                    />
                  </td>
                  <td style={cellule}>{montant(l.resultat_prevu)}</td>
                  <td style={cellule}>{montant(l.resultat_reel)}</td>
                  <td style={cellule}>
                    <Ecart valeur={l.resultat_ecart} pct={l.resultat_ecart_pct} favorableSiPositif />
                  </td>
                  <td style={cellule}>{montant(l.solde_debut)}</td>
                  <td style={cellule}>{montant(l.solde_fin_prevu)}</td>
                  <td style={cellule}>{montant(l.solde_fin_reel)}</td>
                  <td style={cellule}>
                    <Ecart valeur={l.solde_fin_ecart} favorableSiPositif />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <p style={{ marginTop: "1rem", fontSize: "0.9rem" }}>
        Écart = réel − prévu. Alerte d&apos;écart : défavorable, supérieur ou égal à 10 %, mois clos uniquement. Le
        solde prévu de début de mois repart du solde réel constaté.
      </p>
    </main>
  );
}
