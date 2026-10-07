import { test } from "node:test";
import assert from "node:assert/strict";
import { cheminInterneSur, accueilPourRole } from "./redirection.ts";

test("accepte les chemins relatifs internes", () => {
  assert.equal(cheminInterneSur("/ecarts"), "/ecarts");
  assert.equal(cheminInterneSur("/transactions?mode_paiement=cash"), "/transactions?mode_paiement=cash");
  assert.equal(cheminInterneSur("/"), "/");
});

test("rejette les URL absolues, les chemins protocole-relatif et les détournements", () => {
  for (const mauvais of [
    "https://exemple.com",
    "http://exemple.com/x",
    "//exemple.com",
    "///exemple.com",
    "/\\exemple.com",
    "\\\\exemple.com",
    "/\t/exemple.com",
    "/\n/exemple.com",
    "javascript:alert(1)",
    "exemple.com",
    "ecarts",
    "",
    null,
    undefined,
  ]) {
    assert.equal(cheminInterneSur(mauvais), null, `devrait rejeter ${JSON.stringify(mauvais)}`);
  }
});

test("accueil par rôle", () => {
  assert.equal(accueilPourRole("ceo"), "/ecarts");
  assert.equal(accueilPourRole("comptable"), "/transactions");
  assert.equal(accueilPourRole("supervision"), "/supervision");
});
