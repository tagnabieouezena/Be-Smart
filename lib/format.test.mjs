import { test } from "node:test";
import assert from "node:assert/strict";
import {
  formaterMontant,
  formaterVariationMontant,
  formaterVariationPourcentage,
  formaterPourcentage,
  presenterVariation,
} from "./format.ts";

const IN = " "; // espace fine insécable (séparateur de milliers)
const NB = " "; // espace insécable avant l'unité

test("montants : FCFA entiers, milliers séparés par une espace insécable", () => {
  assert.equal(formaterMontant(1250000), `1${IN}250${IN}000${NB}FCFA`);
  assert.equal(formaterMontant(0), `0${NB}FCFA`);
  assert.equal(formaterMontant(590000), `590${IN}000${NB}FCFA`);
});

test("variations : signe explicite et vrai signe moins (U+2212)", () => {
  assert.equal(formaterVariationMontant(90000), `+90${IN}000${NB}FCFA`);
  assert.equal(formaterVariationMontant(-60000), `−60${IN}000${NB}FCFA`);
  assert.equal(formaterVariationMontant(0), `0${NB}FCFA`);
  assert.equal(formaterMontant(-70000), `−70${IN}000${NB}FCFA`);
  assert.ok(!formaterVariationMontant(-60000).includes("-"), "jamais le tiret du clavier");
});

test("pourcentages : 1 décimale, virgule française, signe explicite", () => {
  assert.equal(formaterVariationPourcentage(33.33), `+33,3${NB}%`);
  assert.equal(formaterVariationPourcentage(-98.89), `−98,9${NB}%`);
  assert.equal(formaterVariationPourcentage(-100), `−100,0${NB}%`);
  assert.equal(formaterVariationPourcentage(25), `+25,0${NB}%`);
  assert.equal(formaterPourcentage(12), `12,0${NB}%`);
});

test("sens de la flèche et caractère favorable (décision 1 du brief)", () => {
  // CA encaissé : hausse favorable.
  let p = presenterVariation(100000, 25, true);
  assert.deepEqual([p.sens, p.verdict, p.fleche, p.libelleAccessible], ["hausse", "favorable", "▲", "hausse favorable"]);
  assert.equal(p.montant, `+100${IN}000${NB}FCFA`);
  assert.equal(p.pourcentage, `+25,0${NB}%`);

  // Dépenses : une hausse est défavorable, une baisse favorable.
  p = presenterVariation(20000, 33.33, false);
  assert.deepEqual([p.sens, p.verdict, p.fleche, p.libelleAccessible], ["hausse", "defavorable", "▲", "hausse défavorable"]);
  p = presenterVariation(-30000, -20, false);
  assert.deepEqual([p.sens, p.verdict, p.fleche, p.libelleAccessible], ["baisse", "favorable", "▼", "baisse favorable"]);

  // Baisse du CA : défavorable.
  p = presenterVariation(-300000, -100, true);
  assert.deepEqual([p.sens, p.verdict, p.fleche, p.libelleAccessible], ["baisse", "defavorable", "▼", "baisse défavorable"]);

  // Stable : neutre, sans couleur de verdict.
  p = presenterVariation(0, 0, true);
  assert.deepEqual([p.sens, p.verdict, p.fleche, p.libelleAccessible], ["stable", "neutre", "=", "stable"]);

  // Pourcentage absent (règle 3 : précédent à 0) : le montant seul.
  p = presenterVariation(90000, null, true);
  assert.equal(p.pourcentage, null);
  assert.equal(p.montant, `+90${IN}000${NB}FCFA`);
});
