// Formatage d'affichage uniquement : aucun calcul de montant n'est fait ici.
// Les valeurs arrivent déjà calculées en `numeric` par la base (fonctions
// comparaison_*), TypeScript ne fait que les mettre en forme.
//
// Conventions (brief du Module 4.7) :
//   - FCFA entiers, espace insécable (U+202F, l'espace fine insécable du
//     français) comme séparateur de milliers ;
//   - vrai signe moins « − » (U+2212), jamais le tiret du clavier ;
//   - pourcentage à 1 décimale, virgule française.

const NBSP = " ";

const nombreEntier = new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 0 });
const nombreEntierSigne = new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 0, signDisplay: "exceptZero" });
const pourcentage = new Intl.NumberFormat("fr-FR", { minimumFractionDigits: 1, maximumFractionDigits: 1 });
const pourcentageSigne = new Intl.NumberFormat("fr-FR", {
  minimumFractionDigits: 1,
  maximumFractionDigits: 1,
  signDisplay: "exceptZero",
});

function vraiMoins(texte: string): string {
  return texte.replace("-", "−");
}

// « 1 250 000 FCFA » (valeur sans signe explicite ; le moins reste un vrai moins).
export function formaterMontant(valeur: number): string {
  return `${vraiMoins(nombreEntier.format(valeur))}${NBSP}FCFA`;
}

// « +90 000 FCFA » / « −60 000 FCFA » ; zéro sans signe.
export function formaterVariationMontant(valeur: number): string {
  return `${vraiMoins(nombreEntierSigne.format(valeur))}${NBSP}FCFA`;
}

// « +33,3 % » / « −100,0 % ».
export function formaterVariationPourcentage(valeur: number): string {
  return `${vraiMoins(pourcentageSigne.format(valeur))}${NBSP}%`;
}

export function formaterPourcentage(valeur: number): string {
  return `${vraiMoins(pourcentage.format(valeur))}${NBSP}%`;
}

export const NOMS_MOIS = [
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
] as const;

export const NOMS_MOIS_COURTS = ["Janv.", "Févr.", "Mars", "Avr.", "Mai", "Juin", "Juil.", "Août", "Sept.", "Oct.", "Nov.", "Déc."] as const;

export type Sens = "hausse" | "baisse" | "stable";
export type Verdict = "favorable" | "defavorable" | "neutre";

// Présentation d'une variation : la flèche suit le SENS de la variation, la
// couleur suit son caractère FAVORABLE. Le signal ne repose jamais sur la
// couleur seule : signe explicite, flèche et libellé accessible.
//   - CA encaissé et résultat net : une hausse est favorable ;
//   - dépenses : une hausse est défavorable.
export type Presentation = {
  sens: Sens;
  verdict: Verdict;
  fleche: "▲" | "▼" | "=";
  libelleAccessible: string; // « hausse favorable », « baisse défavorable », « stable »
  montant: string; // « +90 000 FCFA »
  pourcentage: string | null; // « +33,3 % » ou null quand le pourcentage n'existe pas
};

export function presenterVariation(
  variation: number,
  variationPct: number | null,
  hausseFavorable: boolean,
): Presentation {
  const sens: Sens = variation > 0 ? "hausse" : variation < 0 ? "baisse" : "stable";
  const verdict: Verdict =
    sens === "stable" ? "neutre" : (sens === "hausse") === hausseFavorable ? "favorable" : "defavorable";
  const fleche = sens === "hausse" ? "▲" : sens === "baisse" ? "▼" : "=";
  const libelleAccessible =
    sens === "stable" ? "stable" : `${sens} ${verdict === "favorable" ? "favorable" : "défavorable"}`;

  return {
    sens,
    verdict,
    fleche,
    libelleAccessible,
    montant: formaterVariationMontant(variation),
    pourcentage: variationPct === null ? null : formaterVariationPourcentage(variationPct),
  };
}
