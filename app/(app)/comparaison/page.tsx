import { exigerRole } from "@/lib/acces";
import { createClient } from "@/lib/supabase/server";
import { GraphiqueComparaison } from "@/components/graphique-comparaison";
import { IndicateurVariation } from "@/components/indicateur-variation";
import { NOMS_MOIS, formaterMontant } from "@/lib/format";

// Ligne renvoyée par la fonction SQL comparaison_mensuelle (CEO uniquement).
type LigneComparaison = {
  mois: number;
  statut_mois: "clos" | "en_cours";
  a_activite: boolean;
  ca: number;
  depenses: number;
  resultat: number;
  ca_variation: number | null;
  ca_variation_pct: number | null;
  depenses_variation: number | null;
  depenses_variation_pct: number | null;
  resultat_variation: number | null;
  ca_cumul: number;
  depenses_cumul: number;
  resultat_cumul: number;
};

const cellule = { padding: "0.4rem 0.6rem", borderBottom: "1px solid var(--graph-grille)", whiteSpace: "nowrap" as const };
const celluleDroite = { ...cellule, textAlign: "right" as const };

export default async function ComparaisonPage({
  searchParams,
}: {
  searchParams: Promise<{ annee?: string }>;
}) {
  await exigerRole(["ceo"], "/comparaison");
  const params = await searchParams;
  const supabase = await createClient();

  const anneeEnCours = new Date().getFullYear();
  const anneeDemandee = Number.parseInt(params.annee ?? "", 10);
  // Année future non proposée : toute valeur hors [2000, année en cours] retombe sur l'année en cours.
  const annee =
    Number.isInteger(anneeDemandee) && anneeDemandee >= 2000 && anneeDemandee <= anneeEnCours ? anneeDemandee : anneeEnCours;
  const annees = Array.from({ length: anneeEnCours - 2000 + 1 }, (_, i) => anneeEnCours - i);

  const { data, error } = await supabase.rpc("comparaison_mensuelle", { p_annee: annee });
  const lignes = (data ?? []) as LigneComparaison[];
  const derniere = lignes[lignes.length - 1];

  return (
    <main style={{ padding: "2rem", fontFamily: "system-ui, sans-serif" }}>
      <h1>Comparaison mensuelle</h1>
      <p>Base trésorerie : une facture compte au mois de son paiement.</p>

      <form method="get" style={{ display: "flex", gap: "0.5rem", alignItems: "center", margin: "1rem 0" }}>
        <label>
          Année{" "}
          <select name="annee" defaultValue={annee}>
            {annees.map((a) => (
              <option key={a} value={a}>
                {a}
              </option>
            ))}
          </select>
        </label>
        <button type="submit">Afficher</button>
      </form>

      {error && <p style={{ color: "var(--color-negatif)" }}>Impossible de charger la comparaison : {error.message}</p>}
      {lignes.length === 0 && !error && <p>Aucune donnée pour {annee}.</p>}

      {lignes.length > 0 && (
        <>
          <GraphiqueComparaison
            annee={annee}
            points={lignes.map((l) => ({ mois: l.mois, ca: l.ca, depenses: l.depenses, resultat: l.resultat }))}
          />

          <h2 id="titre-tableau" style={{ fontSize: "1.1rem", marginTop: "1.5rem" }}>
            Mois par mois, {annee}
          </h2>
          <p>Chaque variation se lit par rapport au mois précédent.</p>
          <div className="tableau-defilant" style={{ marginTop: "0.5rem" }}>
            <table aria-labelledby="titre-tableau" style={{ borderCollapse: "collapse", minWidth: "980px" }}>
              <thead>
                <tr>
                  <th scope="col" style={cellule}>Mois</th>
                  <th scope="col" style={celluleDroite}>CA encaissé</th>
                  <th scope="col" style={cellule}>Variation CA</th>
                  <th scope="col" style={celluleDroite}>Dépenses</th>
                  <th scope="col" style={cellule}>Variation dépenses</th>
                  <th scope="col" style={celluleDroite}>Résultat net</th>
                  <th scope="col" style={cellule}>Variation résultat</th>
                </tr>
              </thead>
              <tbody>
                {lignes.map((l) => (
                  <tr key={l.mois}>
                    <th scope="row" style={{ ...cellule, textAlign: "left" }}>
                      {NOMS_MOIS[l.mois - 1]}
                      {l.statut_mois === "en_cours" && <em> — à date</em>}
                      {!l.a_activite && <em> — aucune saisie</em>}
                    </th>
                    <td style={celluleDroite}>{formaterMontant(l.ca)}</td>
                    <td style={cellule}>
                      <IndicateurVariation variation={l.ca_variation} variationPct={l.ca_variation_pct} hausseFavorable />
                    </td>
                    <td style={celluleDroite}>{formaterMontant(l.depenses)}</td>
                    <td style={cellule}>
                      <IndicateurVariation
                        variation={l.depenses_variation}
                        variationPct={l.depenses_variation_pct}
                        hausseFavorable={false}
                      />
                    </td>
                    <td style={celluleDroite}>{formaterMontant(l.resultat)}</td>
                    <td style={cellule}>
                      <IndicateurVariation variation={l.resultat_variation} variationPct={null} hausseFavorable avecPourcentage={false} />
                    </td>
                  </tr>
                ))}
              </tbody>
              <tfoot>
                <tr>
                  <th scope="row" style={{ ...cellule, textAlign: "left" }}>Total année à date</th>
                  <td style={{ ...celluleDroite, fontWeight: 700 }}>{formaterMontant(derniere.ca_cumul)}</td>
                  <td style={cellule} />
                  <td style={{ ...celluleDroite, fontWeight: 700 }}>{formaterMontant(derniere.depenses_cumul)}</td>
                  <td style={cellule} />
                  <td style={{ ...celluleDroite, fontWeight: 700 }}>{formaterMontant(derniere.resultat_cumul)}</td>
                  <td style={cellule} />
                </tr>
              </tfoot>
            </table>
          </div>
        </>
      )}
    </main>
  );
}
