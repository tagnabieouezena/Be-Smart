import { test } from "node:test";
import assert from "node:assert/strict";
import { DATE_DEBUT_HISTORIQUE, estDateParDefaut, formaterDateLongue, aujourdhuiISO } from "./solde.ts";

test("la date par défaut est reconnue", () => {
  assert.equal(DATE_DEBUT_HISTORIQUE, "2000-01-01");
  assert.equal(estDateParDefaut("2000-01-01"), true);
  assert.equal(estDateParDefaut("2026-10-13"), false);
});

test("date en toutes lettres, sans décalage de fuseau", () => {
  assert.equal(formaterDateLongue("2026-10-13"), "13 octobre 2026");
  assert.equal(formaterDateLongue("2025-12-31"), "31 décembre 2025");
  assert.match(formaterDateLongue("2026-01-01"), /^1(er)? janvier 2026$/);
});

test("date du jour au format AAAA-MM-JJ", () => {
  assert.match(aujourdhuiISO(), /^\d{4}-\d{2}-\d{2}$/);
});
