# Brief Claude Code — Module 4.6 : Suivi des écarts (Prévu vs Réel)

*À donner tel quel à Claude Code, depuis `main` (Modules 4.1 à 4.4 mergés, job de promotion prod mergé ou en cours — indépendant). Branche courte dédiée : `feat/module-4.6-suivi-ecarts`.*

## Objectif de ce module (CDC 4.6)

Pour chaque mois, comparer automatiquement le prévu (Module 4.3) au réel (Module 4.4) sur les revenus, les dépenses, le résultat et le solde de caisse. Afficher des alertes visuelles en cas d'écart significatif ou de solde de fin de mois prévisionnel négatif. C'est l'équivalent du bloc de synthèse « Prévu / Actuel / Écart » en bas de chaque onglet `Prev_Mois` de l'Excel (CDC 2.1).

**Accès réservé au CEO.** Le résultat et le solde sont des indicateurs stratégiques (CDC 3.2). Le comptable et la supervision Be Smart n'y ont aucun accès.

Ce module est en **lecture seule** : aucune nouvelle table, aucune écriture.

## Règles de calcul (décisions actées par Ouezz)

### Réel du mois M
- Revenus réels = somme des `transactions.montant` avec `type = 'entree'` et `date` dans le mois M.
- Dépenses réelles = somme des `transactions.montant` avec `type = 'sortie'` dans le mois M, ventilées en fixes et variables selon le `type` de la catégorie.
- Résultat réel = revenus réels − dépenses réelles.
- **Le réel se calcule toujours sur les montants des transactions, jamais sur le statut des lignes prévisionnelles.** Rappel du Module 4.4 : un paiement partiel rapproché passe la ligne à `ok`, donc le statut n'est pas fiable pour mesurer l'argent réellement encaissé.

### Prévu du mois M
- Revenus prévus = somme des `lignes_revenu_prevu.montant_estime` du budget de M, **hors statut `annule`**.
- Charges prévues = somme des `lignes_charge_prevue.montant` du budget de M, **hors statut `annule`**, ventilées en fixes et variables.
- Résultat prévu = revenus prévus − charges prévues.
- **Mois sans budget** : les colonnes du prévu sont à `null` (pas à 0), l'écart est `null` et aucune alerte n'est levée. L'écran affiche « Pas de budget ».
- À vérifier au passage : la vue `v_budget_mensuel_totaux` du Module 4.3 exclut-elle les lignes `annule` ? Si non, la corriger dans une migration de ce module, pour qu'il n'y ait qu'une seule règle dans tout le produit. Signale-le dans la PR.

### Solde de caisse
- Solde réel de début de M = `entreprises.solde_initial` + (toutes les entrées − toutes les sorties) des transactions datées avant le 1er jour de M.
- Solde réel de fin de M = solde réel de début de M + résultat réel de M.
- **Solde prévu de début de M = solde réel de début de M** (décision Ouezz). Le prévisionnel repart chaque mois de la réalité constatée. Sans cette règle, l'écart de janvier se reporterait sur tous les mois suivants et rendrait leurs écarts illisibles. La chaîne 100 % prévisionnelle sur plusieurs mois relève du Module 4.9 (Cashflow), pas de celui-ci.
- Solde prévu de fin de M = solde prévu de début de M + résultat prévu de M.

### Écarts et alertes
- Écart = réel − prévu. Écart % = écart / prévu si prévu > 0, sinon `null` (jamais de division par zéro ni d'infini).
- **Seuil d'écart significatif : 10 %, fixe en V1** (décision Ouezz). Il est défini dans **une seule** fonction SQL `seuil_ecart_significatif()` qui renvoie `0.10::numeric`, jamais en dur à plusieurs endroits. Le rendre réglable plus tard ne demandera ainsi que de modifier cette fonction.
- Une alerte d'écart ne se déclenche que pour un **écart défavorable** : revenus réels inférieurs au prévu, ou dépenses réelles supérieures au prévu. Un écart favorable s'affiche, mais sans alerte.
- Une alerte d'écart ne se déclenche que sur un **mois clos**, c'est-à-dire antérieur au mois de la date de référence. Un mois en cours est affiché « à date », sans alerte d'écart : un CA à −60 % le 10 du mois est normal.
- **Dépense non prévue** : si les charges prévues valent 0 alors que les dépenses réelles sont positives, le mois porte un indicateur `depense_non_prevue` (l'écart % est `null`).
- **Alerte de solde prévisionnel négatif** : si le solde prévu de fin de M est < 0, pour le mois en cours et les mois futurs.

## Étapes attendues

### 1. Fonction SQL `ecarts_mensuels(p_annee int, p_date_reference date default current_date)`

- Renvoie une ligne par mois de l'année (1 à 12) qui a un budget ou au moins une transaction. Colonnes :
  - `mois`, `statut_mois` (`clos` / `en_cours` / `futur`) ;
  - pour les revenus, les dépenses (dont fixes et variables), le résultat et le solde de fin, trois colonnes chacune : prévu, réel, écart ;
  - `ecart_pct` pour les revenus, les dépenses et le résultat ;
  - `solde_debut` ;
  - les indicateurs `alerte_revenus`, `alerte_depenses`, `depense_non_prevue`, `alerte_solde_negatif`.
- Le paramètre `p_date_reference` sert à rendre les tests déterministes. L'écran appelle la fonction sans ce paramètre.
- Tous les montants sont en `numeric`, sans aucun cast en float. Les pourcentages sont en `numeric` arrondi à 2 décimales, uniquement à l'affichage final.
- Le cumul du solde se calcule par une somme cumulative (fonction de fenêtre) sur des agrégats mensuels, pas par une sous-requête par ligne.
- **Sécurité :**
  - fonction `security invoker`, jamais `security definer` ;
  - `set search_path = public` ;
  - filtre `entreprise_id = current_entreprise_id()` ;
  - elle renvoie **zéro ligne** si `current_role_utilisateur() <> 'ceo'`. Même comportement que `objectifs_ca` au Module 4.2 : un résultat vide, pas une erreur ;
  - `revoke execute ... from anon` ; `grant execute` à `authenticated` uniquement.
- Index : vérifier qu'il existe un index sur `transactions (entreprise_id, date)`, et l'ajouter sinon (CDC 5.3 : plusieurs années d'historique).

### 2. Écran (CEO)

- Page `/ecarts` avec un sélecteur d'année (année en cours par défaut).
- Tableau mois par mois. Pour chaque indicateur, trois colonnes : Prévu / Réel / Écart. Le mois en cours porte la mention « à date », un mois sans budget la mention « Pas de budget ».
- Alertes visuelles : couleur et icône sur les écarts défavorables significatifs, bandeau en cas de solde prévisionnel négatif, badge « dépense non prévue ». Le sens de l'écart ne doit jamais reposer sur la couleur seule : il faut aussi un signe ou une icône.
- Montants au format FCFA francophone (espace comme séparateur de milliers). Tableau utilisable sur mobile, avec défilement horizontal dans son conteneur.
- Contrôle du rôle CEO côté serveur, comme dans les modules précédents. Le lien n'apparaît pas dans la navigation du comptable.

### 3. Tests de calcul chiffrés (obligatoires, règle du projet)

Dans le script de test, créer une **entreprise dédiée** (dans `BEGIN … ROLLBACK`, pour que le seed n'influence pas les sommes), avec `solde_initial = 500 000`, puis appeler `ecarts_mensuels(2026, '2026-09-15')` en tant que son CEO.

**Juillet 2026 (clos)**
- Budget :
  - charges fixes : loyer 100 000, salaires 200 000 ;
  - charges variables : marketing 50 000, et une ligne `annule` de 30 000 (exclue) ;
  - revenus prévus : 400 000, et une ligne `annule` de 100 000 (exclue).
- Transactions : entrée de 300 000 ; sorties de 100 000 (loyer), 200 000 (salaires) et 70 000 (marketing).
- Attendus :

| Indicateur | Prévu | Réel | Écart | Écart % | Alerte |
|---|---|---|---|---|---|
| Revenus | 400 000 | 300 000 | −100 000 | −25,00 % | oui |
| Dépenses | 350 000 | 370 000 | +20 000 | +5,71 % | non (sous le seuil) |
| Résultat | 50 000 | −70 000 | −120 000 | | |
| Solde de début | 500 000 | 500 000 | | | |
| Solde de fin | 550 000 | 430 000 | | | |

**Août 2026 (clos)**
- Budget : charges fixes 300 000 ; revenus prévus 250 000.
- Transactions : entrée de 250 000 ; sortie de 300 000.
- Attendus :
  - solde de début réel = 430 000, et solde de début prévu = 430 000 (et non 550 000) ;
  - solde de fin prévu = solde de fin réel = 380 000 ;
  - tous les écarts sont à 0, aucune alerte.
- Ce cas prouve la règle « le prévu repart du réel ».

**Septembre 2026 (en cours au 15/09)**
- Budget : charges fixes 300 000, variables 400 000 ; revenus prévus 200 000.
- Transaction : sortie de 100 000.
- Attendus :
  - `statut_mois = en_cours` ;
  - solde de début = 380 000 ;
  - résultat prévu = −500 000, donc solde de fin prévu = −120 000, donc **`alerte_solde_negatif = true`** ;
  - revenus réels 0 contre 200 000 prévus, mais **`alerte_revenus = false`** (mois non clos).

**Juin 2026 (sans budget)**
- Ajouter dans un **second scénario** (autre entreprise dédiée, pour ne pas décaler les soldes du premier) une entrée de 50 000 en juin, sans budget.
- Attendus : revenus réels = 50 000, prévu `null`, écart `null`, aucune alerte.

**Dépense non prévue**
- Dans ce second scénario, un budget en juillet sans aucune ligne de charge, et une sortie de 20 000.
- Attendus : `depense_non_prevue = true`, écart % des dépenses `null`.

### 4. Tests adversariaux (obligatoires)

- Le comptable de l'entreprise appelle `ecarts_mensuels` : **zéro ligne**, alors que les transactions et les budgets de son entreprise lui sont lisibles. C'est la preuve que la restriction au CEO vient bien de la fonction.
- Le compte de supervision Be Smart appelle la fonction : zéro ligne.
- Le CEO de l'entreprise B appelle la fonction : aucune donnée de A ne remonte.
- Un appel en `anon` est refusé (`permission denied`).
- Tous ces tests s'exécutent en utilisateur authentifié réel (`role: authenticated` + `sub`), jamais en `service_role`.

## Explicitement hors de ce module

- Écarts par catégorie de dépense : ce module travaille sur des totaux (la répartition par catégorie relève du Module 4.10).
- Projection sur plusieurs mois et simulateur : Module 4.9 (Cashflow).
- Notifications (email, résumé) : Module 4.12. Ici, les alertes sont uniquement visuelles, dans l'écran.
- Seuil réglable par le CEO : non en V1. La fonction `seuil_ecart_significatif()` suffit pour le préparer.
- Comparaison année sur année (CDC 4.14).

## Livrable attendu pour revue

PR depuis `feat/module-4.6-suivi-ecarts` vers `main`, avec :
- Le SQL complet en clair dans la description (fonction, seuil, index, et éventuelle correction de `v_budget_mensuel_totaux`).
- Les résultats réels des tests chiffrés, comparés aux valeurs attendues ci-dessus, mois par mois.
- La preuve des quatre tests adversariaux.
- CI verte (jobs existants + nouveaux tests).
