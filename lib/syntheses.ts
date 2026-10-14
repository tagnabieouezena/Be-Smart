// Mise en forme de la synthèse par période : regroupement et libellés d'état.
// Aucun calcul de montant, de taux ni de verdict ici : tout vient de la fonction
// SQL syntheses_periodes (voir docs/briefs/Module-4.8-Syntheses.md).

export type LigneSynthese = {
  granularite: "mois" | "trimestre" | "annee";
  periode: number;
  statut: "clos" | "en_cours";
  a_activite: boolean;
  ca: number;
  depenses: number;
  resultat: number;
  objectif_ca: number | null;
  statut_objectif: "absent" | "nul" | "defini";
  taux_realisation: number | null;
  verdict_objectif: "atteint" | "manque" | "a_date" | null;
  solde_debut: number;
  solde_fin: number;
};

export type GroupeTrimestre = {
  trimestre: number;
  mois: LigneSynthese[];
  total: LigneSynthese | null;
};

// Regroupe les lignes renvoyées par la base : les mois par trimestre (avec la
// ligne de total du trimestre) et la ligne de l'année.
export function grouperParTrimestre(lignes: LigneSynthese[]): { groupes: GroupeTrimestre[]; annee: LigneSynthese | null } {
  const groupes: GroupeTrimestre[] = [];
  for (const t of [1, 2, 3, 4]) {
    const mois = lignes.filter((l) => l.granularite === "mois" && Math.floor((l.periode - 1) / 3) + 1 === t);
    if (mois.length === 0) continue;
    const total = lignes.find((l) => l.granularite === "trimestre" && l.periode === t) ?? null;
    groupes.push({ trimestre: t, mois, total });
  }
  return { groupes, annee: lignes.find((l) => l.granularite === "annee") ?? null };
}

// Ce que la colonne « Taux de réalisation » affiche pour une ligne.
export type EtatObjectif =
  | { genre: "taux"; taux: number; verdict: "atteint" | "manque" | "a_date" }
  | { genre: "absent" } // « Pas d'objectif »
  | { genre: "nul" } // « Objectif à 0 »
  | { genre: "aucune_saisie" }; // objectif défini, mais aucune transaction dans la période

export function etatObjectif(l: LigneSynthese): EtatObjectif {
  if (l.taux_realisation !== null && l.verdict_objectif !== null) {
    return { genre: "taux", taux: l.taux_realisation, verdict: l.verdict_objectif };
  }
  if (l.statut_objectif === "absent") return { genre: "absent" };
  if (l.statut_objectif === "nul") return { genre: "nul" };
  return { genre: "aucune_saisie" };
}
