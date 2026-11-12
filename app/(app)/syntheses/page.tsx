import Link from "next/link";
import { exigerRole } from "@/lib/acces";
import { createClient } from "@/lib/supabase/server";
import { NOMS_MOIS, formaterMontant, formaterPourcentage } from "@/lib/format";
import { etatObjectif, grouperParTrimestre, type LigneSynthese } from "@/lib/syntheses";

const cellule = { padding: "0.4rem 0.6rem", borderBottom: "1px solid var(--graph-grille)", whiteSpace: "nowrap" as const };
const celluleDroite = { ...cellule, textAlign: "right" as const };
const celluleTotal = { ...celluleDroite, fontWeight: 700 };

function Solde({ valeur }: { valeur: number }) {
  return (
    <>
      {formaterMontant(valeur)}
      {valeur < 0 && <span className="variation-defavorable"> solde négatif</span>}
    </>
  );
}

// Colonne « Taux de réalisation » : le verdict est toujours écrit (texte et icône),
// jamais porté par la couleur seule.
function Taux({ ligne }: { ligne: LigneSynthese }) {
  const etat = etatObjectif(ligne);
  if (etat.genre === "absent") return <>Pas d&apos;objectif</>;
  if (etat.genre === "nul") return <>Objectif à 0</>;
  if (etat.genre === "aucune_saisie") return <>Aucune saisie</>;
  return (
    <>
      {formaterPourcentage(etat.taux)}{" "}
      {etat.verdict === "atteint" && <span className="variation-favorable">✓ Objectif atteint</span>}
      {etat.verdict === "manque" && <span className="variation-defavorable">✗ Objectif manqué</span>}
      {etat.verdict === "a_date" && <em>à date</em>}
    </>
  );
}

function Ligne({ ligne, libelle, total = false }: { ligne: LigneSynthese; libelle: React.ReactNode; total?: boolean }) {
  const droite = total ? celluleTotal : celluleDroite;
  return (
    <tr >
      <th scope="row" style={{ ...cellule, textAlign: "left", fontWeight: total ? 700 : 400 }}>
        {libelle}
      </th>
      <td style={droite}>{formaterMontant(ligne.ca)}</td>
      <td style={droite}>{formaterMontant(ligne.depenses)}</td>
      <td style={droite}>{formaterMontant(ligne.resultat)}</td>
      <td style={droite}>{ligne.objectif_ca === null ? "—" : formaterMontant(ligne.objectif_ca)}</td>
      <td style={cellule}>
        <Taux ligne={ligne} />
      </td>
      <td style={droite}>
        <Solde valeur={ligne.solde_debut} />
      </td>
      <td style={droite}>
        <Solde valeur={ligne.solde_fin} />
      </td>
    </tr>
  );
}

export default async function SynthesesPage({
  searchParams,
}: {
  searchParams: Promise<{ annee?: string }>;
}) {
  await exigerRole(["ceo"], "/syntheses");
  const params = await searchParams;
  const supabase = await createClient();

  const anneeEnCours = new Date().getFullYear();
  const anneeDemandee = Number.parseInt(params.annee ?? "", 10);
  // Année future non proposée : toute valeur hors [2000, année en cours] retombe sur l'année en cours.
  const annee =
    Number.isInteger(anneeDemandee) && anneeDemandee >= 2000 && anneeDemandee <= anneeEnCours ? anneeDemandee : anneeEnCours;
  const annees = Array.from({ length: anneeEnCours - 2000 + 1 }, (_, i) => anneeEnCours - i);

  const { data, error } = await supabase.rpc("syntheses_periodes", { p_annee: annee });
  const lignes = (data ?? []) as LigneSynthese[];
  const { groupes, annee: ligneAnnee } = grouperParTrimestre(lignes);

  return (
    <main style={{ padding: "2rem", fontFamily: "system-ui, sans-serif" }}>
      <h1>Synthèses</h1>
      <p>Base trésorerie : une facture compte au mois de son paiement.</p>
      <p>
        Les objectifs de CA et le solde de caisse (montant et date) se saisissent dans le{" "}
        <Link href="/parametrage">Paramétrage</Link>.
      </p>

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

      {error && <p style={{ color: "var(--color-negatif)" }}>Impossible de charger les synthèses : {error.message}</p>}
      {lignes.length === 0 && !error && <p>Aucune donnée pour {annee}.</p>}

      {lignes.length > 0 && (
        <>
          <h2 id="titre-tableau" style={{ fontSize: "1.1rem" }}>
            Mois, trimestres et année {annee}
          </h2>
          <div className="tableau-defilant" style={{ marginTop: "0.5rem" }}>
            <table aria-labelledby="titre-tableau" style={{ borderCollapse: "collapse", minWidth: "1100px" }}>
              <thead>
                <tr>
                  <th scope="col" style={cellule}>Période</th>
                  <th scope="col" style={celluleDroite}>CA encaissé</th>
                  <th scope="col" style={celluleDroite}>Dépenses</th>
                  <th scope="col" style={celluleDroite}>Résultat net</th>
                  <th scope="col" style={celluleDroite}>Objectif de CA</th>
                  <th scope="col" style={cellule}>Taux de réalisation</th>
                  <th scope="col" style={celluleDroite}>Solde de caisse au début</th>
                  <th scope="col" style={celluleDroite}>Solde de caisse à la fin</th>
                </tr>
              </thead>
              <tbody>
                {groupes.map((g) => (
                  <GroupeLignes key={g.trimestre} g={g} />
                ))}
              </tbody>
              {ligneAnnee && (
                <tfoot>
                  <Ligne
                    ligne={ligneAnnee}
                    total
                    libelle={<>Total année {annee}{ligneAnnee.statut === "en_cours" && <em> — à date</em>}</>}
                  />
                </tfoot>
              )}
            </table>
          </div>
        </>
      )}
    </main>
  );
}

function GroupeLignes({ g }: { g: { trimestre: number; mois: LigneSynthese[]; total: LigneSynthese | null } }) {
  return (
    <>
      {g.mois.map((l) => (
        <Ligne
          key={l.periode}
          ligne={l}
          libelle={<>{NOMS_MOIS[l.periode - 1]}{l.statut === "en_cours" && <em> — à date</em>}</>}
        />
      ))}
      {g.total && (
        <Ligne
          ligne={g.total}
          total
          libelle={<>Total T{g.trimestre}{g.total.statut === "en_cours" && <em> — à date</em>}</>}
        />
      )}
    </>
  );
}
