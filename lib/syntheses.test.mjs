import { test } from "node:test";
import assert from "node:assert/strict";
import { grouperParTrimestre, etatObjectif } from "./syntheses.ts";

const ligne = (g, p, extra = {}) => ({
  granularite: g, periode: p, statut: "clos", a_activite: true, ca: 0, depenses: 0, resultat: 0,
  objectif_ca: null, statut_objectif: "absent", taux_realisation: null, verdict_objectif: null,
  solde_debut: 0, solde_fin: 0, ...extra,
});

test("regroupe les mois par trimestre, avec le total du trimestre et l'année", () => {
  const lignes = [
    ...[1, 2, 3, 4, 5, 6, 7, 8].map((m) => ligne("mois", m)),
    ligne("trimestre", 1), ligne("trimestre", 2), ligne("trimestre", 3),
    ligne("annee", 2026),
  ];
  const { groupes, annee } = grouperParTrimestre(lignes);
  assert.deepEqual(groupes.map((g) => [g.trimestre, g.mois.map((m) => m.periode), g.total?.periode]), [
    [1, [1, 2, 3], 1],
    [2, [4, 5, 6], 2],
    [3, [7, 8], 3],
  ]);
  assert.equal(annee?.periode, 2026);
});

test("année sans ligne : aucun groupe", () => {
  assert.deepEqual(grouperParTrimestre([]), { groupes: [], annee: null });
});

test("état de la colonne « Taux de réalisation »", () => {
  assert.deepEqual(etatObjectif(ligne("mois", 1, { objectif_ca: 180000, statut_objectif: "defini", taux_realisation: 111.1, verdict_objectif: "atteint" })),
    { genre: "taux", taux: 111.1, verdict: "atteint" });
  assert.deepEqual(etatObjectif(ligne("mois", 2, { objectif_ca: 150000, statut_objectif: "defini", taux_realisation: 66.6, verdict_objectif: "manque" })),
    { genre: "taux", taux: 66.6, verdict: "manque" });
  assert.deepEqual(etatObjectif(ligne("annee", 2026, { objectif_ca: 2000000, statut_objectif: "defini", taux_realisation: 54, verdict_objectif: "a_date", statut: "en_cours" })),
    { genre: "taux", taux: 54, verdict: "a_date" });
  assert.deepEqual(etatObjectif(ligne("mois", 5)), { genre: "absent" });
  assert.deepEqual(etatObjectif(ligne("mois", 3, { objectif_ca: 0, statut_objectif: "nul" })), { genre: "nul" });
  assert.deepEqual(etatObjectif(ligne("mois", 4, { objectif_ca: 100000, statut_objectif: "defini", a_activite: false })), { genre: "aucune_saisie" });
});
