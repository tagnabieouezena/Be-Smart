import { presenterVariation } from "@/lib/format";

// Variation d'un mois sur l'autre : flèche (sens), couleur (caractère favorable),
// signe explicite et libellé accessible toujours présents. Aucun calcul ici : la
// valeur et le pourcentage viennent de la base.
export function IndicateurVariation({
  variation,
  variationPct,
  hausseFavorable,
  avecPourcentage = true,
}: {
  variation: number | null;
  variationPct: number | null;
  hausseFavorable: boolean;
  avecPourcentage?: boolean;
}) {
  if (variation === null) {
    return <span>—</span>;
  }

  const p = presenterVariation(variation, avecPourcentage ? variationPct : null, hausseFavorable);
  const classe =
    p.verdict === "favorable" ? "variation-favorable" : p.verdict === "defavorable" ? "variation-defavorable" : "variation-neutre";

  return (
    <span className={classe}>
      <span aria-hidden="true">{p.fleche}</span> <span className="sr-seul">{p.libelleAccessible} : </span>
      {p.montant}
      {p.pourcentage !== null && <> ({p.pourcentage})</>}
    </span>
  );
}
