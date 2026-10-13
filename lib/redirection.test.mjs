import { test } from "node:test";
import assert from "node:assert/strict";
import { cheminInterneSur, accueilPourRole, cheminAutorisePourRole, destinationPourRole, destinationApresCreation } from "./redirection.ts";

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

test("next autorisé selon le rôle", () => {
  assert.equal(cheminAutorisePourRole("/transactions", "ceo"), true);
  assert.equal(cheminAutorisePourRole("/transactions?mode_paiement=cash", "ceo"), true);
  assert.equal(cheminAutorisePourRole("/comparaison", "ceo"), true);
  assert.equal(cheminAutorisePourRole("/comparaison", "comptable"), false);
  assert.equal(cheminAutorisePourRole("/budgets", "comptable"), false);
  assert.equal(cheminAutorisePourRole("/supervision", "ceo"), false);
  assert.equal(cheminAutorisePourRole("/transactions/../supervision", "ceo"), false);
  assert.equal(cheminAutorisePourRole("/transactionsx", "ceo"), false);
  assert.equal(cheminAutorisePourRole("//exemple.com", "ceo"), false);
  assert.equal(cheminAutorisePourRole("https://exemple.com", "ceo"), false);
  assert.equal(cheminAutorisePourRole(null, "ceo"), false);
});

test("destination : next valide et autorisé, sinon accueil du rôle", () => {
  assert.equal(destinationPourRole("/transactions", "ceo"), "/transactions");
  assert.equal(destinationPourRole("/supervision", "ceo"), "/ecarts");
  assert.equal(destinationPourRole("//exemple.com", "ceo"), "/ecarts");
  assert.equal(destinationPourRole(null, "ceo"), "/ecarts");
  assert.equal(destinationPourRole("/budgets", "comptable"), "/transactions");
  assert.equal(destinationPourRole("/creances", "comptable"), "/creances");
});

test("destination juste après la création de l'espace", () => {
  assert.equal(destinationApresCreation("/transactions"), "/transactions");
  assert.equal(destinationApresCreation(null), "/parametrage");
  assert.equal(destinationApresCreation("/supervision"), "/parametrage");
  assert.equal(destinationApresCreation("//exemple.com"), "/parametrage");
  assert.equal(destinationApresCreation("https://exemple.com"), "/parametrage");
});
