import { IndicateurVariation } from "@/components/indicateur-variation";
import { NOMS_MOIS, formaterMontant } from "@/lib/format";

// Ligne renvoyée par la fonction SQL comparaison_accueil.
export type LigneBandeau = {
  annee_clos: number;
  mois_clos: number;
  annee_precedent: number;
  mois_precedent: number;
  ca: number;
  depenses: number;
  resultat: number;
  a_activite: boolean;
  a_activite_precedent: boolean;
  ca_variation: number | null;
  ca_variation_pct: number | null;
  depenses_variation: number | null;
  depenses_variation_pct: number | null;
  resultat_variation: number | null;
};

// Bandeau des trois indicateurs du dernier mois clos, comparé au mois calendaire
// précédent (solution provisoire, repris par le tableau de bord du Module 4.11).
export function BandeauVariations({ ligne }: { ligne: LigneBandeau }) {
  const sansComparaison =
    ligne.ca_variation === null && ligne.depenses_variation === null && ligne.resultat_variation === null;

  const indicateurs = [
    {
      cle: "ca",
      libelle: "CA encaissé",
      valeur: ligne.ca,
      variation: ligne.ca_variation,
      pct: ligne.ca_variation_pct,
      hausseFavorable: true,
    },
    {
      cle: "depenses",
      libelle: "Dépenses",
      valeur: ligne.depenses,
      variation: ligne.depenses_variation,
      pct: ligne.depenses_variation_pct,
      hausseFavorable: false,
    },
    {
      cle: "resultat",
      libelle: "Résultat net",
      valeur: ligne.resultat,
      variation: ligne.resultat_variation,
      pct: null,
      hausseFavorable: true,
    },
  ];

  return (
    <section aria-labelledby="titre-bandeau">
      <h2 id="titre-bandeau" style={{ fontSize: "1.1rem" }}>
        {NOMS_MOIS[ligne.mois_clos - 1]} {ligne.annee_clos}, comparé à {NOMS_MOIS[ligne.mois_precedent - 1]}{" "}
        {ligne.annee_precedent}
      </h2>
      <div className="bandeau-variations">
        {indicateurs.map((i) => (
          <div key={i.cle}>
            <div>{i.libelle}</div>
            <div style={{ fontSize: "1.25rem", fontWeight: 700 }}>{formaterMontant(i.valeur)}</div>
            <div style={{ fontSize: "0.9rem" }}>
              {sansComparaison ? (
                <span>Pas de comparaison</span>
              ) : (
                <>
                  <IndicateurVariation variation={i.variation} variationPct={i.pct} hausseFavorable={i.hausseFavorable} />{" "}
                  <span>vs mois précédent</span>
                </>
              )}
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}
