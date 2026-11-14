# Audit indépendant des calculs financiers — 2026

**Entreprise auditée** : Faso Info Équipement SARL (démo, `de000000-0000-0000-0000-000000000001`)
**Date de référence** : 2026-11-14. Novembre 2026 est le mois en cours, janvier à octobre sont clos, décembre est futur.
**Environnement** : Supabase local (`supabase_db_Be_smart`) et application Next.js sur le port 3011.

## Résumé chiffré

| | Nombre |
|---|---|
| ✅ Contrôles conformes | **70** |
| ❌ Écarts constatés | **5** |

Chaque ligne des tableaux ci-dessous compte pour un contrôle. Une ligne de mois regroupe toutes les grandeurs de ce mois, soit 10 à 30 valeurs. Le script compare aussi chaque valeur une par une : **970 valeurs recalculées sont identiques aux sorties des fonctions SQL, et aucune ne diffère.**

Les 5 ❌ :
1. **Écarts, décembre (mois futur)** : le réel est affiché à 0 FCFA et les écarts à −100,00 % (revenus, dépenses, résultat). Défaut connu, confirmé.
2. **Écarts, septembre** : le résultat réel est affiché « -1 970 000 FCFA » avec un tiret (U+002D) au lieu du vrai signe moins (U+2212). Défaut connu, confirmé.
3. **Budget** : les totaux et les montants des lignes n'ont pas de séparateur de milliers (« 1840000 FCFA »).
4. **Transactions** (CEO et comptable) : les montants n'ont pas de séparateur de milliers (« 305000 FCFA »).
5. **Paramétrage** : les objectifs de CA n'ont pas de séparateur de milliers (« 5000000 FCFA »).

**Aucun écart de calcul n'a été trouvé** sur les mois clos, le mois en cours, les trimestres, l'année, les soldes, les créances et la facturation des lignes de CA. Les 5 ❌ portent sur la **présentation** : un mois futur traité comme un mois constaté (1), puis le format des montants (2 à 5).

## Introduction

### Périmètre
- Année 2026 de l'entreprise de démo : écarts prévu/réel (4.6), comparaison mensuelle et bandeau d'accueil (4.7), synthèses (4.8), solde de caisse daté, créances et balance âgée (4.5), budget avec facturation des lignes de CA (4.3 et lien créance ↔ revenu prévu), journal (4.4), paramétrage.
- Chaque valeur est contrôlée à trois niveaux : recalcul indépendant, sortie de la fonction SQL ou de la vue, valeur affichée à l'écran.

### Méthode
1. **Données** : `SELECT` sur les tables brutes `entreprises`, `categories`, `objectifs_ca`, `budgets_mensuels`, `lignes_charge_prevue`, `lignes_revenu_prevu`, `transactions` et `creances`, filtrés sur l'entreprise de démo. Session forcée en lecture seule (`default_transaction_read_only=on`, vérifié : `on`), puis export CSV.
   - Volumes : 228 transactions (du 2026-01-03 au 2026-11-12), 5 créances, 12 budgets, 96 lignes de charge (aucune `annule`), 25 lignes de revenu (aucune `annule`), 13 objectifs (12 mensuels et 1 annuel de 61 500 000, aucun trimestriel).
   - Solde initial : 3 500 000 FCFA à la fin du 2025-12-31.
2. **Recalcul** : un script Python en `decimal.Decimal`, jamais en float (annexe), écrit uniquement à partir des règles des briefs.
3. **Fonctions** : appelées en tant que CEO (`set role authenticated` et claims `sub = de100000-…c1`), dans une session en lecture seule.
   - Fonctions : `ecarts_mensuels(2026)`, `comparaison_mensuelle(2026)`, `comparaison_accueil()`, `syntheses_periodes(2026)`, `creances_situation()`, `creances_balance_agee()`.
   - Vues : `v_lignes_revenu_facturation`, `v_budget_mensuel_totaux`.
   - `solde_caisse_a(d)` aux bornes de chaque mois.
   - Toutes ont été appelées sans le paramètre de date, donc avec `current_date` = 2026-11-14. Le script compare automatiquement chaque colonne commune.
4. **Écran** : navigateur intégré, dans un **onglet séparé sur `http://127.0.0.1:3011`**.
   - Cette origine a ses propres cookies : la session de la démo en cours sur `localhost:3011` n'a donc pas été touchée.
   - Lecture par `get_page_text` et inspection DOM en lecture seule : codes des caractères (signe moins, espaces), nombre de lignes, sommes des montants du journal.
   - Aucun bouton d'enregistrement ou de suppression n'a été cliqué. Les deux sessions (CEO puis comptable) ont été déconnectées, puis l'onglet a été fermé.

### Sources lues
`docs/briefs/module-4.3-budget-previsionnel.md`, `module-4.4-journal-transactions.md`, `Module-4.5-Creances-Clients.md`, `Module-4.6-Suivi-Ecarts.md`, `Module-4.7-Comparaison-Mensuelle.md`, `Module-4.8-Syntheses.md`, `Solde-Initial-Date.md`, `Lien-Creance-Revenu-Prevu.md` et `docs/03-modele-de-donnees.md`. Seules les **règles et définitions** ont servi au recalcul. Les tableaux d'attendus des scénarios de test des briefs portent sur d'autres entreprises et n'ont pas été utilisés.

### Sources NON lues
- `supabase/migrations/`, `supabase/tests/`, `supabase/seed.sql`, `supabase/demo/`, `app/`, `lib/`, `components/`.
- Aucune définition SQL de fonction ou de vue : ni `pg_get_functiondef`, ni `\sf`, ni `\d+`.

### Limites
- **Le CDC complet (§4.3 à §4.8) n'est pas dans le dépôt** (il est sur claude.ai). Seuls les extraits du CDC cités dans les briefs ont été pris en compte.
- La **date de référence est 2026-11-14** : les statuts des mois, les jours de retard, les tranches et le mois « en cours » en dépendent.
- Points de règle que les briefs ne tranchent pas explicitement, et hypothèse retenue pour chacun :
  - `jours_retard` d'une créance **payée** : 0, par cohérence avec `tranche = null`.
  - Seuil d'alerte « ≥ 10 % » ou « > 10 % » : aucun écart de la démo ne tombe exactement sur 10 %, donc le choix est sans effet ici. L'écran indique « supérieur ou égal ».
  - Écart d'un **mois futur** : voir ❌ n° 1.
- Pas vérifiable sans lire le code : le passage en chaîne du montant du solde au Paramétrage, et la présence du formulaire de saisie du comptable (non visible dans le texte lu de `/transactions`).
- La table `utilisateurs` n'est pas dans le périmètre de données autorisé. L'attribution « Saisi par » n'a donc été lue qu'à l'écran.

---

## Rappel des valeurs recalculées (réel par mois, 2026)

| Mois | Statut | CA encaissé | Dépenses fixes | Dépenses variables | Dépenses | Résultat | Solde début | Solde fin réel |
|---|---|---|---|---|---|---|---|---|
| Janvier | clos | 4 605 000 | 1 825 000 | 2 692 000 | 4 517 000 | 88 000 | 3 500 000 | 3 588 000 |
| Février | clos | 5 055 000 | | | 4 738 000 | 317 000 | 3 588 000 | 3 905 000 |
| Mars | clos | 5 415 000 | | | 4 848 000 | 567 000 | 3 905 000 | 4 472 000 |
| Avril | clos | 4 775 000 | | | 4 537 000 | 238 000 | 4 472 000 | 4 710 000 |
| Mai | clos | 5 700 000 | | | 4 966 000 | 734 000 | 4 710 000 | 5 444 000 |
| Juin | clos | 5 165 000 | | | 4 712 000 | 453 000 | 5 444 000 | 5 897 000 |
| Juillet | clos | 6 640 000 | | | 4 543 000 | 2 097 000 | 5 897 000 | 7 994 000 |
| Août | clos | 6 815 000 | | | 4 315 000 | 2 500 000 | 7 994 000 | 10 494 000 |
| Septembre | clos | 3 675 000 | 1 822 000 | 3 823 000 | 5 645 000 | −1 970 000 | 10 494 000 | 8 524 000 |
| Octobre | clos | 5 975 000 | | | 4 903 000 | 1 072 000 | 8 524 000 | 9 596 000 |
| Novembre | en cours | 2 260 000 | 510 000 | 1 385 000 | 1 895 000 | 365 000 | 9 596 000 | 9 961 000 |
| Décembre | futur | 0 | 0 | 0 | 0 | 0 | 9 961 000 | 9 961 000 |

La ventilation fixes/variables de chaque mois est recalculée par le script et identique à la fonction ; seuls quelques mois sont repris ici.

Prévu (budgets validés) : janvier à novembre, revenus 5 050 000, charges 4 670 000 (fixes 1 840 000, variables 2 830 000), résultat 380 000. Décembre (brouillon) : revenus 8 750 000, charges 5 070 000 (1 840 000 et 3 230 000), résultat 3 680 000.

---

## 1. Écran Écarts (`/ecarts`, fonction `ecarts_mensuels(2026)`)

Valeurs contrôlées pour chaque mois :
- revenus, dépenses (dont fixes et variables) et résultat : prévu, réel, écart et écart % ;
- solde de début, solde de fin prévu, solde de fin réel et écart de solde ;
- indicateurs `alerte_revenus`, `alerte_depenses`, `depense_non_prevue`, `alerte_solde_negatif`.

| Élément | Valeur attendue (recalcul) | Valeur fonction | Valeur affichée | Statut |
|---|---|---|---|---|
| Janvier (clos) | rev. 5 050 000 / 4 605 000 / −445 000 (−8,81 %) ; dép. 4 670 000 / 4 517 000 / −153 000 (−3,28 %) ; rés. 380 000 / 88 000 / −292 000 (−76,84 %) ; solde 3 500 000 → prévu 3 880 000, réel 3 588 000 | identique | identique | ✅ |
| Février (clos) | rev. +5 000 (+0,10 %) ; dép. +68 000 (+1,46 %) ; rés. 317 000, −63 000 (−16,58 %) ; solde 3 588 000 → 3 968 000 / 3 905 000 | identique | identique | ✅ |
| Mars (clos) | rev. +365 000 (+7,23 %) ; dép. +178 000 (+3,81 %) ; rés. 567 000, +187 000 (+49,21 %) ; solde 3 905 000 → 4 285 000 / 4 472 000 | identique | identique | ✅ |
| Avril (clos) | rev. −275 000 (−5,45 %) ; dép. −133 000 (−2,85 %) ; rés. 238 000, −142 000 (−37,37 %) ; solde 4 472 000 → 4 852 000 / 4 710 000 | identique | identique | ✅ |
| Mai (clos) | rev. +650 000 (+12,87 %) ; dép. +296 000 (+6,34 %) ; rés. 734 000, +354 000 (+93,16 %) ; solde 4 710 000 → 5 090 000 / 5 444 000 | identique | identique | ✅ |
| Juin (clos) | rev. +115 000 (+2,28 %) ; dép. +42 000 (+0,90 %) ; rés. 453 000, +73 000 (+19,21 %) ; solde 5 444 000 → 5 824 000 / 5 897 000 | identique | identique | ✅ |
| Juillet (clos) | rev. +1 590 000 (+31,49 %) ; dép. −127 000 (−2,72 %) ; rés. 2 097 000, +1 717 000 (+451,84 %) ; solde 5 897 000 → 6 277 000 / 7 994 000 | identique | identique | ✅ |
| Août (clos) | rev. +1 765 000 (+34,95 %) ; dép. −355 000 (−7,60 %) ; rés. 2 500 000, +2 120 000 (+557,89 %) ; solde 7 994 000 → 8 374 000 / 10 494 000 | identique | identique | ✅ |
| Septembre (clos), montants | rev. 3 675 000, −1 375 000 (−27,23 %) ; dép. 5 645 000, +975 000 (+20,88 %) ; rés. −1 970 000, −2 350 000 (−618,42 %) ; solde 10 494 000 → 10 874 000 / 8 524 000 | identique | identique (hors signe, ligne suivante) | ✅ |
| **Septembre : signe du résultat réel** | « −1 970 000 FCFA » (U+2212) | −1970000 | « **-1 970 000 FCFA** » (U+002D, seul tiret de la page ; les 43 autres signes négatifs sont des U+2212) | ❌ |
| Octobre (clos) | rev. +925 000 (+18,32 %) ; dép. +233 000 (+4,99 %) ; rés. 1 072 000, +692 000 (+182,11 %) ; solde 8 524 000 → 8 904 000 / 9 596 000 | identique | identique | ✅ |
| Novembre (en cours, « à date ») | rev. 2 260 000, −2 790 000 (−55,25 %) ; dép. 1 895 000, −2 775 000 (−59,42 %) ; rés. 365 000, −15 000 (−3,95 %) ; solde 9 596 000 → 9 976 000 / 9 961 000 ; aucune alerte (mois non clos) | identique | identique, mention « Novembre — à date » | ✅ |
| Décembre (futur) : prévu et solde | prévu rev. 8 750 000, dép. 5 070 000, rés. 3 680 000 ; solde début 9 961 000 ; solde fin prévu 13 641 000 ; `alerte_solde_negatif` faux | identique | identique | ✅ |
| **Décembre (futur) : réel et écarts** | Mois non constaté : pas de réel ni d'écart (« — », mois à venir) | réel 0 ; écarts −8 750 000 / −5 070 000 / −3 680 000, **−100,00 %** ; solde fin réel 9 961 000, écart −3 680 000 | « 0 FCFA » et « ▼ −8 750 000 (−100,00 %) », « ▲ −5 070 000 (−100,00 %) », « ▼ −3 680 000 (−100,00 %) », écart de solde ▼ −3 680 000 | ❌ |
| Alertes (12 mois) | `alerte_revenus` et `alerte_depenses` vraies **uniquement en septembre** (−27,23 % et +20,88 %, défavorables, mois clos) ; aucune `depense_non_prevue` ; aucune `alerte_solde_negatif` | identique | ⚠ « alerte : écart significatif » sur les revenus et les dépenses de septembre uniquement | ✅ |
| Accès comptable à `/ecarts` | refusé (404) | — | HTTP 404 | ✅ |

Format : séparateur de milliers U+202F (espace fine insécable) partout, et U+00A0 avant « FCFA ».

## 2. Bandeau d'accueil (haut de `/ecarts`, fonction `comparaison_accueil()`)

| Élément | Valeur attendue (recalcul) | Valeur fonction | Valeur affichée | Statut |
|---|---|---|---|---|
| Périodes comparées | dernier mois clos octobre 2026, comparé à septembre 2026 | 2026/10 contre 2026/9 | « Octobre 2026, comparé à Septembre 2026 » | ✅ |
| CA encaissé | 5 975 000 ; +2 300 000 (+62,59 % → 62,6) ; ▲ hausse favorable | 5975000 ; 2300000 ; 62.59 | « 5 975 000 FCFA ▲ hausse favorable : +2 300 000 FCFA (+62,6 %) » | ✅ |
| Dépenses | 4 903 000 ; −742 000 (−13,14 % → −13,1) ; ▼ baisse favorable | 4903000 ; −742000 ; −13.14 | « 4 903 000 FCFA ▼ baisse favorable : −742 000 FCFA (−13,1 %) » | ✅ |
| Résultat net | 1 072 000 ; +3 042 000 (FCFA seul) ; ▲ hausse favorable | 1072000 ; 3042000 | « 1 072 000 FCFA ▲ hausse favorable : +3 042 000 FCFA » | ✅ |

## 3. Comparaison mensuelle (`/comparaison`, fonction `comparaison_mensuelle(2026)`)

Pour chaque mois : CA, dépenses, résultat, variations en FCFA et en %, cumuls, statut, `a_activite`. Le pourcentage de la fonction (2 décimales) est affiché à 1 décimale. Un contrôle séparé a vérifié que l'arrondi à 1 décimale du pourcentage exact donne le même chiffre que l'arrondi de la valeur à 2 décimales, pour les 20 pourcentages.

| Élément | Valeur attendue (recalcul) | Valeur fonction | Valeur affichée | Statut |
|---|---|---|---|---|
| Janvier | 4 605 000 / 4 517 000 / 88 000 ; variations `null` (règle 1) | identique | « — » partout | ✅ |
| Février | +450 000 (+9,77) ; +221 000 (+4,89) ; +229 000 | identique | +450 000 (+9,8 %) ; +221 000 (+4,9 %) ; +229 000 | ✅ |
| Mars | +360 000 (+7,12) ; +110 000 (+2,32) ; +250 000 | identique | +7,1 % ; +2,3 % | ✅ |
| Avril | −640 000 (−11,82) ; −311 000 (−6,42) ; −329 000 | identique | −11,8 % ; −6,4 % | ✅ |
| Mai | +925 000 (+19,37) ; +429 000 (+9,46) ; +496 000 | identique | +19,4 % ; +9,5 % | ✅ |
| Juin | −535 000 (−9,39) ; −254 000 (−5,11) ; −281 000 | identique | −9,4 % ; −5,1 % | ✅ |
| Juillet | +1 475 000 (+28,56) ; −169 000 (−3,59) ; +1 644 000 | identique | +28,6 % ; −3,6 % | ✅ |
| Août | +175 000 (+2,64) ; −228 000 (−5,02) ; +403 000 | identique | +2,6 % ; −5,0 % | ✅ |
| Septembre | −3 140 000 (−46,07) ; +1 330 000 (+30,82) ; −4 470 000 ; résultat −1 970 000 | identique | −46,1 % ; +30,8 % ; « −1 970 000 FCFA » (vrai moins ici) | ✅ |
| Octobre | +2 300 000 (+62,59) ; −742 000 (−13,14) ; +3 042 000 | identique | +62,6 % ; −13,1 % | ✅ |
| Novembre (en cours) | −3 715 000 (−62,18) ; −3 008 000 (−61,35) ; −707 000 | identique | « Novembre — à date », −62,2 % ; −61,4 % | ✅ |
| Total année à date (cumul de novembre) | 56 080 000 / 49 619 000 / 6 461 000 | identique | identique | ✅ |
| Graphique | 11 points par série (janvier à novembre), aucun mois futur | — | 3 courbes de 11 points ; résumé « de Janvier à Novembre 2026 » | ✅ |
| Format des signes et flèches | vrai moins, signe explicite, ▲/▼ selon le sens, couleur selon le caractère favorable, libellé accessible | — | aucun tiret ; « hausse défavorable » pour les dépenses en hausse, etc. | ✅ |

## 4. Synthèses (`/syntheses`, fonction `syntheses_periodes(2026)`)

| Élément | Valeur attendue (recalcul) | Valeur fonction | Valeur affichée | Statut |
|---|---|---|---|---|
| Janvier | 4 605 000 / 4 517 000 / 88 000 ; obj. 5 000 000 ; 92,1 % manqué ; 3 500 000 → 3 588 000 | identique | « 92,1 % ✗ Objectif manqué » | ✅ |
| Février | 5 055 000 ; 101,1 % atteint ; 3 588 000 → 3 905 000 | identique | identique | ✅ |
| Mars | 5 415 000 ; 108,3 % atteint ; 3 905 000 → 4 472 000 | identique | identique | ✅ |
| Avril | 4 775 000 ; 95,5 % manqué ; 4 472 000 → 4 710 000 | identique | identique | ✅ |
| Mai | 5 700 000 ; 114,0 % atteint ; 4 710 000 → 5 444 000 | identique | identique | ✅ |
| Juin | 5 165 000 ; 103,3 % atteint ; 5 444 000 → 5 897 000 | identique | identique | ✅ |
| Juillet | 6 640 000 ; 132,8 % atteint ; 5 897 000 → 7 994 000 | identique | identique | ✅ |
| Août | 6 815 000 ; 136,3 % atteint ; 7 994 000 → 10 494 000 | identique | identique | ✅ |
| Septembre | 3 675 000 ; résultat −1 970 000 ; 73,5 % manqué ; 10 494 000 → 8 524 000 | identique | « −1 970 000 FCFA » (U+2212) | ✅ |
| Octobre | 5 975 000 ; 119,5 % atteint ; 8 524 000 → 9 596 000 | identique | identique | ✅ |
| Novembre (en cours) | 2 260 000 ; 45,2 % (tronqué), verdict `a_date` ; 9 596 000 → 9 961 000 | identique | « 45,2 % à date » | ✅ |
| T1 (clos) | 15 075 000 / 14 103 000 / 972 000 ; objectif absent ; 3 500 000 → 4 472 000 | identique | « Pas d'objectif » | ✅ |
| T2 (clos) | 15 640 000 / 14 215 000 / 1 425 000 ; absent ; 4 472 000 → 5 897 000 | identique | identique | ✅ |
| T3 (clos) | 17 130 000 / 14 503 000 / 2 627 000 ; absent ; 5 897 000 → 8 524 000 | identique | identique | ✅ |
| T4 (en cours, octobre et novembre) | 8 235 000 / 6 798 000 / 1 437 000 ; absent ; 8 524 000 → 9 961 000 | identique | « Total T4 — à date » | ✅ |
| Année 2026 (en cours) | 56 080 000 / 49 619 000 / 6 461 000 ; obj. annuel 61 500 000 ; 91,1 % (91,187 tronqué), `a_date` ; 3 500 000 → 9 961 000 | identique | « 91,1 % à date » | ✅ |
| Identités et format | `solde_fin = solde_debut + résultat` sur les 16 lignes ; continuité mois → mois et trimestre → trimestre ; pas de prorata de l'objectif annuel ; vrai moins | vérifié | U+202F et U+00A0 partout, aucun tiret | ✅ |

## 5. Budget (`/budgets?mois=M&annee=2026`, vues `v_budget_mensuel_totaux` et `v_lignes_revenu_facturation`)

| Élément | Valeur attendue (recalcul) | Valeur fonction | Valeur affichée | Statut |
|---|---|---|---|---|
| Totaux des 12 budgets (vue) | janvier à novembre : fixes 1 840 000, variables 2 830 000, CA 5 050 000, résultat 380 000 ; décembre : 1 840 000 / 3 230 000 / 8 750 000 / 3 680 000 | identique (12/12) | — | ✅ |
| Janvier, totaux et lignes | 1 840 000 / 2 830 000 / 5 050 000 / 380 000 ; Ventes 4 300 000 et Maintenance 750 000, facturé 0, reste 4 300 000 et 750 000 | identique | valeurs identiques (format : voir ❌) | ✅ |
| Septembre, totaux et lignes | idem janvier | identique | valeurs identiques | ✅ |
| Novembre, totaux et lignes | idem, lignes de CA `en_attente` | identique | valeurs identiques | ✅ |
| Décembre, totaux | 1 840 000 / 3 230 000 / 8 750 000 / 3 680 000 ; statut brouillon | identique | valeurs identiques, bouton « Valider le budget » | ✅ |
| Facturation des 25 lignes de CA (vue) | 24 lignes : facturé 0, reste = estimé ; « Contrat Mairie arr. 12 » (décembre) : 1 créance, facturé 3 000 000, reste 0 | identique (25/25) | — | ✅ |
| Décembre, ligne « Contrat Mairie arr. 12 » | facturé 3 000 000 (1 créance), reste à facturer 0 | identique | « Facturé : 3 000 000 FCFA (1 créance) — Reste à facturer : 0 FCFA » | ✅ |
| **Format des montants du budget** | « 1 840 000 FCFA » (séparateur insécable) | — | « Charges fixes : **1840000 FCFA** », lignes « — 450000 FCFA (realise) », « 4300000 FCFA (ok) ». Seules les colonnes « Facturé » et « Reste à facturer » sont formatées | ❌ |

## 6. Créances (`/creances`, fonctions `creances_situation()` et `creances_balance_agee()`, référence 2026-11-14)

| Élément | Valeur attendue (recalcul) | Valeur fonction | Valeur affichée | Statut |
|---|---|---|---|---|
| Lycée Philippe Zinda Kaboré | dû 4 500 000 ; encaissé 4 500 000 (2 000 000 le 07-10 et 2 500 000 le 08-05) ; reste 0 ; `paye` ; 0 j ; tranche `null` | identique | « Payé », « — » | ✅ |
| ONG Wend-Panga | 1 250 000 ; 0 ; reste 1 250 000 ; `en_retard` ; 91 j (échéance 08-15) ; `plus_60` | identique | « ⚠ En retard », « 91 j » | ✅ |
| Cabinet Sawadogo & Associés | 850 000 ; 400 000 ; reste 450 000 ; `en_retard` (partiellement payée et échue) ; 25 j ; `1_30` | identique | « ⚠ En retard », « 25 j » | ✅ |
| Clinique Notre-Dame de la Paix | 600 000 ; 0 ; 600 000 ; `en_attente` (échéance 11-30) ; 0 ; `non_echue` | identique | « En attente » | ✅ |
| Mairie de l'arrondissement 12 | 3 000 000 ; 0 ; 3 000 000 ; `en_attente` ; 0 ; `non_echue` ; liée à la ligne de décembre | identique | « En attente », ligne du budget « Décembre 2026 — Contrat Mairie arr. 12 — salle informatique » | ✅ |
| Total en cours | 5 300 000 | 5300000 | 5 300 000 FCFA | ✅ |
| Balance âgée | non échue 3 600 000 ; 1-30 j 450 000 ; 31-60 j 0 ; > 60 j 1 250 000 (somme 5 300 000) | identique | identique | ✅ |
| Reste dû par mois d'échéance | août 1 250 000 ; octobre 450 000 ; novembre 600 000 ; décembre 3 000 000 | identique | identique | ✅ |
| Vue comptable | mêmes valeurs ; « Supprimer » seulement sans encaissement | — | mêmes valeurs ; pas de « Supprimer » pour le Lycée ni le Cabinet, présent pour l'ONG, la Clinique et la Mairie | ✅ |

## 7. Transactions (`/transactions`)

| Élément | Valeur attendue (recalcul) | Valeur fonction | Valeur affichée | Statut |
|---|---|---|---|---|
| Vue CEO : nombre et sommes mensuelles | 228 lignes ; entrées/sorties par mois = CA/dépenses du tableau de rappel (ex. septembre 3 675 000 / 5 645 000) | n/a (table) | 228 lignes ; les 11 sommes mensuelles recalculées depuis le DOM sont identiques | ✅ |
| Vue comptable : nombre et sommes mensuelles | idem (lecture de toute l'entreprise, décision 4.4) | n/a | 228 lignes, sommes identiques | ✅ |
| **Format des montants du journal** | « 305 000 FCFA » | — | « **305000 FCFA** », « 1200000 FCFA » (aucun séparateur) | ❌ |

## 8. Paramétrage (`/parametrage`)

| Élément | Valeur attendue (recalcul) | Valeur fonction | Valeur affichée | Statut |
|---|---|---|---|---|
| Solde de caisse daté | 3 500 000 à la fin du 2025-12-31 | — | « Solde de 3 500 000 FCFA à la fin du 31 décembre 2025 » ; champ date `max` = 2026-11-14 | ✅ |
| `solde_caisse_a` aux bornes des mois | 2025-12-31 : 3 500 000 ; fins de mois de janvier à novembre = soldes de fin du tableau de rappel ; 2026-11-14, 11-30 et 12-31 : 9 961 000 ; 2025-01-01 : 3 500 000 | identique (27 dates) | (repris dans Écarts et Synthèses) | ✅ |
| Objectifs de CA (valeurs) | mensuels 2026 : 5 000 000 × 11, décembre 6 500 000 ; annuel 61 500 000 | — | valeurs identiques | ✅ |
| **Format des objectifs** | « 5 000 000 FCFA » | — | « mensuel 2026 — mois 1 : **5000000 FCFA** », « annuel 2026 : 61500000 FCFA » | ❌ |

---

## Écarts constatés

### ❌ 1. Écarts, décembre (mois futur) : réel 0 et écart −100 %
- **Constat** : `ecarts_mensuels(2026)` renvoie pour décembre (`statut_mois = futur`) `revenus_reel = 0`, `revenus_ecart = −8 750 000`, `revenus_ecart_pct = −100.00` (de même pour les dépenses et le résultat), et `solde_fin_ecart = −3 680 000`. L'écran l'affiche tel quel, avec des flèches « défavorable ». Le réel d'un mois qui n'a pas commencé est montré comme un constat, et l'écart de −100 % ressemble à une contre-performance.
- **Règle en jeu** : `Module-4.6-Suivi-Ecarts.md`, § « Écarts et alertes ». Une alerte d'écart ne se déclenche que sur un **mois clos**, et un mois en cours est affiché « à date ». Le statut `futur` existe (§1), mais **le brief ne dit pas ce que valent le réel et l'écart d'un mois futur** : c'est un trou de la règle. La formule « Écart = réel − prévu » est appliquée mécaniquement. Les alertes, elles, sont correctement à faux.
- **Hypothèse sur la cause** : la fonction calcule réel et écart pour toute ligne qui a un budget, sans tenir compte de `statut_mois`. L'écran affiche le mois futur comme un mois constaté. Piste : réel et écarts à `null` pour un mois futur, et mention « Mois à venir » à l'écran. Cette règle est à faire trancher par Ouezz et à ajouter au brief 4.6.

### ❌ 2. Écarts, septembre : tiret au lieu du vrai signe moins
- **Constat** : la cellule « Résultat réel » de septembre affiche « -1 970 000 FCFA » avec U+002D. C'est le seul tiret de la page : les 43 autres signes négatifs (écarts, bandeau) sont des U+2212. La même valeur est correcte (« −1 970 000 FCFA ») sur `/comparaison` et `/syntheses`.
- **Règle en jeu** :
  - `Module-4.7-Comparaison-Mensuelle.md`, § « Arrondi et format » : « avec le vrai signe moins ».
  - `Module-4.8-Syntheses.md`, § « Ce qui existe déjà » : `lib/format.ts` (« montants FCFA, vrai signe moins, espaces insécables »).
- **Hypothèse sur la cause** : les colonnes Prévu et Réel de `/ecarts` passent par un formatage qui ne remplace pas le tiret de `Intl.NumberFormat` (ou par un formateur antérieur au 4.7). Les colonnes d'écart passent, elles, par le formateur signé. Les montants prévus et réels négatifs sont rares, d'où un défaut resté invisible. À vérifier dans le composant de `/ecarts` (non lu, règle d'indépendance).

### ❌ 3. Budget : montants sans séparateur de milliers
- **Constat** : totaux (« Charges fixes : 1840000 FCFA ») et lignes (« 450000 FCFA (realise) ») bruts, sur les quatre mois vérifiés. Les colonnes « Facturé » et « Reste à facturer », ajoutées par le prérequis lien créance ↔ revenu prévu, sont bien formatées (« 4 300 000 FCFA »). Le même écran mélange donc deux formats.
- **Règle en jeu** :
  - `Module-4.6-Suivi-Ecarts.md` §2 et `Module-4.5-Creances-Clients.md` §4 : « Montants au format FCFA francophone (espace comme séparateur de milliers) ».
  - `Module-4.7-Comparaison-Mensuelle.md`, § « Arrondi et format ».
  - `module-4.3-budget-previsionnel.md` ne précise aucun format.
- **Hypothèse sur la cause** : l'écran du Budget (4.3) est antérieur au formateur commun et concatène la valeur `numeric` brute avec « FCFA ». Les statuts sont aussi affichés en code brut (`realise`, `planifie`, `a_faire`, `en_attente`, `ok`).

### ❌ 4. Transactions : montants sans séparateur de milliers
- **Constat** : « 305000 FCFA », « 1200000 FCFA » sur les 228 lignes, en vue CEO comme en vue comptable. Les codes techniques sont aussi affichés tels quels (`entree`, `sortie`, `mobile_money`), et les dates en ISO.
- **Règle en jeu** : même convention que le ❌ 3 (briefs 4.5 §4, 4.6 §2 et 4.7 « Arrondi et format ») ; `module-4.4-journal-transactions.md` ne précise aucun format.
- **Hypothèse sur la cause** : l'écran du Journal (4.4), antérieur au formateur commun, n'a pas été repris.

### ❌ 5. Paramétrage : objectifs sans séparateur de milliers
- **Constat** : « mensuel 2026 — mois 1 : 5000000 FCFA », « annuel 2026 : 61500000 FCFA ». Le solde de caisse, juste au-dessus, est bien formaté (« 3 500 000 FCFA »).
- **Règle en jeu** : même convention. `Module-4.8-Syntheses.md` en fait la source des objectifs affichés en Synthèses, où ils sont bien formatés.
- **Hypothèse sur la cause** : la liste des objectifs (4.2) concatène la valeur brute. La section du solde a été refaite par le prérequis `Solde-Initial-Date` avec le formateur commun.

---

## Observations (non comptées)

Ce ne sont pas des écarts à une règle écrite, mais des points à signaler :
- **Sens des flèches différent sur une même page** : dans le tableau de `/ecarts`, ▲/▼ indique le caractère favorable ou défavorable (« ▲ −153 000 » = dépenses en baisse, favorable). Dans le bandeau juste au-dessus, ▲/▼ suit le sens de la variation (« ▼ −742 000 baisse favorable »), comme le veut la décision 1 du brief 4.7. Les deux sont accessibles par leur libellé, mais un même symbole a deux sens sur la même page. Le brief 4.6 n'impose qu'« un signe ou une icône ».
- **Colonnes « Écart » de `/ecarts` sans « FCFA »** (« ▼ −445 000 (−8,81 %) ») : l'unité est implicite par l'en-tête. Le brief 4.7 écrit « −60 000 FCFA » pour les variations, mais il porte sur son propre écran.
- **Graphique de `/comparaison`** : l'axe des abscisses porte l'étiquette « Déc. » alors que les courbes s'arrêtent à novembre (conforme sur les données).
- **`/creances`** : espace ordinaire (U+0020) avant « FCFA », au lieu de l'espace insécable des autres écrans ; échéances en ISO (« 2026-07-15 ») ; libellé de la ligne du budget au format « Décembre 2026 — Contrat… » au lieu de « Contrat… — décembre 2026 » (brief Lien, § « Liste des créances »).
- **Attribution des saisies dans la démo** : les 228 transactions et les 5 créances ont `saisi_par = de100000-…c1`, le même identifiant que la session CEO utilisée. L'écran affiche « Issa Kaboré » (en-tête : « Issa Kaboré — CEO »). Selon le brief 4.4, le CEO ne crée jamais de transaction. C'est sans effet sur les calculs, mais incohérent pour une démonstration de la traçabilité : il faudrait attribuer ces saisies au comptable (Aminata Ouédraogo, présente dans le filtre « Responsable »).
- **Écran comptable `/transactions`** : le formulaire de saisie n'apparaît pas dans le texte lu en haut de page (un seul formulaire, le filtre). Non vérifié plus avant (aucun clic sur un bouton d'action).
- Le sélecteur d'année de `/comparaison` et `/syntheses` propose 2000 à 2026 : année future non proposée, conforme.

---

## Annexe — script de recalcul (rejouable)

Mode d'emploi :
1. Exporter les tables brutes dans `data/*.csv`, en lecture seule :

```
docker exec -e PGOPTIONS='-c default_transaction_read_only=on' -i supabase_db_Be_smart psql -U postgres -d postgres \
  -c "copy (select * from transactions where entreprise_id='de000000-0000-0000-0000-000000000001') to stdout with csv header"
```

   Faire de même pour `entreprises` (filtre `id=`), `categories`, `objectifs_ca`, `budgets_mensuels`, `lignes_charge_prevue`, `lignes_revenu_prevu` et `creances`.
2. Exporter les sorties des fonctions dans `fn/*.csv` :
   - `ecarts.csv`, `comparaison.csv`, `accueil.csv`, `syntheses.csv`, `creances_situation.csv`, `balance.csv`, `lignes_fact.csv`, `budget_totaux.csv` ;
   - même commande, précédée de `set role authenticated; set request.jwt.claims = '{"sub": "de100000-0000-0000-0000-0000000000c1", "role": "authenticated"}';`.
3. Lancer `python3 -I recalcul.py <dossier>` : la sortie standard donne les attendus en JSON, la sortie d'erreur le bilan de la comparaison (attendu ici : `970 identiques, 0 différentes`).

```python
#!/usr/bin/env python3
"""Recalcul indépendant des calculs financiers 2026 — Faso Info Équipement SARL.

Entrées : exports CSV en lecture seule des tables brutes (dossier data/) et,
pour comparaison, des sorties des fonctions appelées en CEO (dossier fn/).
Toutes les sommes en decimal.Decimal, jamais en float.
Usage : python3 recalcul.py <dossier contenant data/ et fn/>
"""
import csv, sys, json, calendar
from decimal import Decimal as D, ROUND_HALF_UP, ROUND_DOWN
from datetime import date, timedelta
from pathlib import Path

BASE = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
ANNEE = 2026
REF = date(2026, 11, 14)           # date de référence = aujourd'hui
SEUIL = D("0.10")                  # seuil_ecart_significatif (brief 4.6)

def lire(nom, dossier="data"):
    with open(BASE / dossier / nom, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))

def dt(s): return date.fromisoformat(s)
def r2(x): return None if x is None else x.quantize(D("0.01"), rounding=ROUND_HALF_UP)
def tr1(x): return x.quantize(D("0.1"), rounding=ROUND_DOWN)   # troncature 1 décimale (4.8 T4)

ent = lire("entreprises.csv")[0]
S0, D0 = D(ent["solde_initial"]), dt(ent["date_solde_initial"])
cats = {c["id"]: c["type"] for c in lire("categories.csv")}
tx = lire("transactions.csv")
for t in tx:
    t["d"] = dt(t["date"]); t["m"] = D(t["montant"])
    t["net"] = t["m"] if t["type"] == "entree" else -t["m"]
budgets = {b["id"]: (int(b["annee"]), int(b["mois"])) for b in lire("budgets_mensuels.csv")}
lcp = [l for l in lire("lignes_charge_prevue.csv") if l["statut"] != "annule"]
lrp_all = lire("lignes_revenu_prevu.csv")
lrp = [l for l in lrp_all if l["statut"] != "annule"]
objectifs = lire("objectifs_ca.csv")
creances = lire("creances.csv")

# --- Règle unique du solde (Solde-Initial-Date.md) : F(t) fin de journée t
def F(t):
    return (S0 + sum((x["net"] for x in tx if D0 < x["d"] <= t), D(0))
               - sum((x["net"] for x in tx if t < x["d"] <= D0), D(0)))

def dernier_jour(a, m): return date(a, m, calendar.monthrange(a, m)[1])
def veille_1er(a, m): return date(a, m, 1) - timedelta(days=1)

def statut_mois(m):
    if (ANNEE, m) < (REF.year, REF.month): return "clos"
    if (ANNEE, m) == (REF.year, REF.month): return "en_cours"
    return "futur"

# --- Réel / prévu par mois (4.6)
reel = {}
for m in range(1, 13):
    tm = [x for x in tx if x["d"].year == ANNEE and x["d"].month == m]
    rev = sum((x["m"] for x in tm if x["type"] == "entree"), D(0))
    fix = sum((x["m"] for x in tm if x["type"] == "sortie" and cats[x["categorie_id"]] == "fixe"), D(0))
    var = sum((x["m"] for x in tm if x["type"] == "sortie" and cats[x["categorie_id"]] == "variable"), D(0))
    reel[m] = dict(rev=rev, fix=fix, var=var, dep=fix + var, res=rev - fix - var, actif=len(tm) > 0)

prevu = {}
for bid, (a, m) in budgets.items():
    if a != ANNEE: continue
    fix = sum((D(l["montant"]) for l in lcp if l["budget_mensuel_id"] == bid and cats[l["categorie_id"]] == "fixe"), D(0))
    var = sum((D(l["montant"]) for l in lcp if l["budget_mensuel_id"] == bid and cats[l["categorie_id"]] == "variable"), D(0))
    rev = sum((D(l["montant_estime"]) for l in lrp if l["budget_mensuel_id"] == bid), D(0))
    prevu[m] = dict(rev=rev, fix=fix, var=var, dep=fix + var, res=rev - fix - var)

def pct(ecart, p):  # écart % = écart / prévu × 100, si prévu > 0
    return r2(ecart / p * 100) if p is not None and p > 0 else None

ecarts = {}
for m in range(1, 13):
    if m not in prevu and not reel[m]["actif"]: continue
    r, p = reel[m], prevu.get(m)
    sd = F(veille_1er(ANNEE, m))
    row = dict(mois=m, statut_mois=statut_mois(m), solde_debut=sd, solde_fin_reel=sd + r["res"])
    for k, nom in (("rev", "revenus"), ("dep", "depenses"), ("fix", "depenses_fixes"), ("var", "depenses_variables"), ("res", "resultat")):
        row[nom + "_reel"] = r[k]
        row[nom + "_prevu"] = p[k] if p else None
        row[nom + "_ecart"] = r[k] - p[k] if p else None
    for nom in ("revenus", "depenses", "resultat"):
        row[nom + "_ecart_pct"] = pct(row[nom + "_ecart"], row[nom + "_prevu"]) if p else None
    row["solde_fin_prevu"] = sd + p["res"] if p else None
    row["solde_fin_ecart"] = row["solde_fin_reel"] - row["solde_fin_prevu"] if p else None
    clos = row["statut_mois"] == "clos"
    def signif(e, pv): return pv is not None and pv > 0 and abs(e) / pv >= SEUIL
    row["alerte_revenus"] = bool(p and clos and row["revenus_ecart"] < 0 and signif(row["revenus_ecart"], p["rev"]))
    row["alerte_depenses"] = bool(p and clos and row["depenses_ecart"] > 0 and signif(row["depenses_ecart"], p["dep"]))
    row["depense_non_prevue"] = bool(p and p["dep"] == 0 and r["dep"] > 0)
    row["alerte_solde_negatif"] = bool(p and row["statut_mois"] != "clos" and row["solde_fin_prevu"] < 0)
    ecarts[m] = row

# --- Comparaison mensuelle (4.7)
def variation(c, pr, ac, ap):
    if not (ac and ap): return None, None
    v = c - pr
    return v, (r2(v / pr * 100) if pr > 0 else None)

mois_aff = [m for m in range(1, 13) if (ANNEE, m) <= (REF.year, REF.month)]
comp, cum = {}, dict(ca=D(0), dep=D(0), res=D(0))
for m in mois_aff:
    r = reel[m]
    cum = dict(ca=cum["ca"] + r["rev"], dep=cum["dep"] + r["dep"], res=cum["res"] + r["res"])
    row = dict(mois=m, statut_mois=statut_mois(m), a_activite=r["actif"], ca=r["rev"], depenses=r["dep"], resultat=r["res"],
               ca_cumul=cum["ca"], depenses_cumul=cum["dep"], resultat_cumul=cum["res"])
    if m == 1:
        row.update(ca_variation=None, ca_variation_pct=None, depenses_variation=None, depenses_variation_pct=None, resultat_variation=None)
    else:
        q = reel[m - 1]
        row["ca_variation"], row["ca_variation_pct"] = variation(r["rev"], q["rev"], r["actif"], q["actif"])
        row["depenses_variation"], row["depenses_variation_pct"] = variation(r["dep"], q["dep"], r["actif"], q["actif"])
        row["resultat_variation"] = variation(r["res"], q["res"], r["actif"], q["actif"])[0]
    comp[m] = row

# --- Bandeau d'accueil : dernier mois clos vs mois calendaire précédent
mc = REF.month - 1 if REF.month > 1 else 12
mp = mc - 1
r, q = reel[mc], reel[mp]
acc = dict(mois_clos=mc, mois_precedent=mp, ca=r["rev"], depenses=r["dep"], resultat=r["res"],
           ca_precedent=q["rev"], depenses_precedent=q["dep"], resultat_precedent=q["res"])
acc["ca_variation"], acc["ca_variation_pct"] = variation(r["rev"], q["rev"], r["actif"], q["actif"])
acc["depenses_variation"], acc["depenses_variation_pct"] = variation(r["dep"], q["dep"], r["actif"], q["actif"])
acc["resultat_variation"] = variation(r["res"], q["res"], r["actif"], q["actif"])[0]

# --- Synthèses (4.8)
def objectif(tp, mois=None, trim=None):
    for o in objectifs:
        if o["type_periode"] == tp and int(o["annee"]) == ANNEE and (mois is None or o["mois"] == str(mois)) and (trim is None or o["trimestre"] == str(trim)):
            return D(o["montant_cible"])
    return None

def ligne_syn(gran, per, mois, statut):
    ca = sum((reel[m]["rev"] for m in mois), D(0)); dep = sum((reel[m]["dep"] for m in mois), D(0))
    actif = any(reel[m]["actif"] for m in mois)
    obj = objectif("mensuel", mois=per) if gran == "mois" else objectif("trimestriel", trim=per) if gran == "trimestre" else objectif("annuel")
    so = "absent" if obj is None else ("nul" if obj == 0 else "defini")
    taux = verdict = None
    if so == "defini" and actif:
        taux = tr1(ca / obj * 100)
        verdict = ("atteint" if ca >= obj else "manque") if statut == "clos" else "a_date"
    sd = F(veille_1er(ANNEE, mois[0]))   # = ouverture de l'année + cumul (identité de continuité)
    return dict(granularite=gran, periode=per, statut=statut, a_activite=actif, ca=ca, depenses=dep, resultat=ca - dep,
                objectif_ca=obj, statut_objectif=so, taux_realisation=taux, verdict_objectif=verdict,
                solde_debut=sd, solde_fin=sd + (ca - dep))

syn = []
for m in mois_aff:
    syn.append(ligne_syn("mois", m, [m], statut_mois(m)))
for t in range(1, 5):
    ms = [m for m in mois_aff if (m - 1) // 3 + 1 == t]
    if ms: syn.append(ligne_syn("trimestre", t, ms, "clos" if len(ms) == 3 and all(statut_mois(m) == "clos" for m in ms) else "en_cours"))
syn.append(ligne_syn("annee", ANNEE, mois_aff, "clos" if len(mois_aff) == 12 and all(statut_mois(m) == "clos" for m in mois_aff) else "en_cours"))

# --- Créances (4.5), référence = aujourd'hui
cre = {}
for c in creances:
    enc = sum((x["m"] for x in tx if x["creance_id"] == c["id"]), D(0))
    du = D(c["montant_du"]); reste = du - enc; ech = dt(c["echeance"])
    jr = 0 if reste == 0 else max((REF - ech).days, 0)   # payée : 0 (pas de retard sur une créance soldée)
    statut = "paye" if reste == 0 else "en_retard" if ech < REF else "partiellement_paye" if enc > 0 else "en_attente"
    tranche = None if reste == 0 else "non_echue" if jr <= 0 else "1_30" if jr <= 30 else "31_60" if jr <= 60 else "plus_60"
    cre[c["id"]] = dict(client=c["client"], montant_du=du, montant_encaisse=enc, reste_du=reste, statut=statut,
                        jours_retard=jr, tranche=tranche, echeance=ech)
bal = {"total|en_cours": sum((v["reste_du"] for v in cre.values() if v["reste_du"] > 0), D(0))}
for k in ("non_echue", "1_30", "31_60", "plus_60"):
    bal["tranche|" + k] = sum((v["reste_du"] for v in cre.values() if v["tranche"] == k), D(0))
for v in cre.values():
    if v["reste_du"] > 0:
        k = "mois|%04d-%02d" % (v["echeance"].year, v["echeance"].month)
        bal[k] = bal.get(k, D(0)) + v["reste_du"]

# --- Budget : facturation par ligne de CA (Lien-Creance-Revenu-Prevu) et totaux (4.3)
fact = {}
for l in lrp:
    liees = [c for c in creances if c["ligne_revenu_prevu_id"] == l["id"]]
    f = sum((D(c["montant_du"]) for c in liees), D(0))
    a, m = budgets[l["budget_mensuel_id"]]
    fact[l["id"]] = dict(mois=m, source=l["source"], montant_estime=D(l["montant_estime"]), nb_creances=len(liees),
                         montant_facture=f, reste_a_facturer=max(D(l["montant_estime"]) - f, D(0)))
tot = {}
for bid, (a, m) in budgets.items():
    p = prevu[m]
    tot[bid] = dict(mois=m, total_charges_fixes=p["fix"], total_charges_variables=p["var"],
                    total_ca_previsionnel=p["rev"], resultat_previsionnel=p["res"])

# ------------------------------------------------------------------ comparaison avec les fonctions
def norm(v):
    if v is None or v == "": return None
    if isinstance(v, bool): return v
    if isinstance(v, date): return v.isoformat()
    if v in ("t", "f"): return v == "t"
    try: return D(v)
    except Exception: return v
def eq(a, b):
    a, b = norm(a), norm(b)
    if isinstance(a, D) and isinstance(b, D): return a == b
    if isinstance(a, int) and isinstance(b, D): return D(a) == b
    return a == b

ok, ko, details = 0, 0, []
def comparer(label, att, fn):
    global ok, ko
    for k, v in att.items():
        if k not in fn: continue
        if eq(v, fn[k]): ok += 1
        else:
            ko += 1; details.append(f"{label} {k}: attendu={v} fonction={fn[k]}")

fe = {int(r["mois"]): r for r in lire("ecarts.csv", "fn")}
for m, row in ecarts.items(): comparer(f"ecarts[{m}]", row, fe.get(m, {}))
fc = {int(r["mois"]): r for r in lire("comparaison.csv", "fn")}
for m, row in comp.items(): comparer(f"comparaison[{m}]", row, fc.get(m, {}))
comparer("accueil", acc, lire("accueil.csv", "fn")[0])
fs = {(r["granularite"], int(r["periode"])): r for r in lire("syntheses.csv", "fn")}
for row in syn: comparer(f"syntheses[{row['granularite']} {row['periode']}]", row, fs.get((row["granularite"], row["periode"]), {}))
fcs = {r["id"]: r for r in lire("creances_situation.csv", "fn")}
for i, row in cre.items(): comparer(f"creance[{row['client']}]", row, fcs.get(i, {}))
fb = {r["rubrique"] + "|" + r["cle"]: r["montant"] for r in lire("balance.csv", "fn")}
comparer("balance", bal, fb)
extra = set(fb) - set(bal)
if extra: ko += 1; details.append(f"balance: clés en trop côté fonction {extra}")
fl = {r["ligne_revenu_prevu_id"]: r for r in lire("lignes_fact.csv", "fn")}
for i, row in fact.items(): comparer(f"ligne_ca[{row['mois']} {row['source']}]", row, fl.get(i, {}))
ft = {r["budget_mensuel_id"]: r for r in lire("budget_totaux.csv", "fn")}
for i, row in tot.items():
    fr = ft.get(i, {})
    comparer(f"budget_totaux[{row['mois']}]", row, fr)

print(json.dumps(dict(
    ecarts={m: {k: str(v) for k, v in r.items()} for m, r in ecarts.items()},
    comparaison={m: {k: str(v) for k, v in r.items()} for m, r in comp.items()},
    accueil={k: str(v) for k, v in acc.items()},
    syntheses=[{k: str(v) for k, v in r.items()} for r in syn],
    creances={r["client"]: {k: str(v) for k, v in r.items()} for r in cre.values()},
    balance={k: str(v) for k, v in bal.items()},
    lignes_ca=[{k: str(v) for k, v in r.items()} for r in fact.values()],
    budget_totaux=sorted(({k: str(v) for k, v in r.items()} for r in tot.values()), key=lambda r: int(r["mois"])),
), ensure_ascii=False, indent=1))
print(f"\nComparaisons valeur recalculée vs fonction : {ok} identiques, {ko} différentes", file=sys.stderr)
for d_ in details: print("  ECART", d_, file=sys.stderr)
```
