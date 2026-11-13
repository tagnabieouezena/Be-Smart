# Brief Claude Code — Module 4.9 : Cashflow prévisionnel

*Depuis `main` (Modules 4.1 à 4.8 mergés, solde de caisse initial daté mergé). **Décisions D1 à D9 et choix T1 à T9 décidés par Ouezz le 2026-11-12.** **Ce brief suppose le prérequis « Lien créance ↔ revenu prévu » (`docs/briefs/Lien-Creance-Revenu-Prevu.md`, décision D4) mergé avant toute implémentation.** Branche : `feat/module-4.9-cashflow`.*

## Objectif (CDC 4.9)

> « - Projection du solde de trésorerie sur les prochains mois/trimestres à partir des budgets prévisionnels saisis.
> - Simulateur simple : "si je reporte cette dépense / si ce paiement client arrive en retard, quel impact sur ma trésorerie ?" »

Ancien onglet Excel (CDC 2.4) : « Même logique que la synthèse mensuelle, mais sur la base des montants prévisionnels (et non réels), pour anticiper le solde de trésorerie futur trimestre par trimestre. »

**Accès réservé au CEO** (indicateurs stratégiques, CDC 3.2). Le comptable et la supervision Be Smart n'y ont aucun accès.

Module en **lecture seule** : aucune nouvelle table, aucune écriture, aucune policy nouvelle (le seul changement de schéma est le prérequis ci-dessous). **Une simulation ne modifie JAMAIS les données réelles ni le budget** : elle n'est pas stockée et la fonction qui la calcule ne peut pas écrire (voir « Simulateur »).

## Ce qui existe déjà et doit être réutilisé (rien n'est recalculé)

- **Le point de départ** : `solde_caisse_a(date)` (solde à la fin d'une journée, règle unique du solde daté).
- **Le prévu** : la vue `v_budget_mensuel_totaux` (4.3, lignes `annule` exclues) : `total_charges_fixes`, `total_charges_variables` par `(entreprise, annee, mois)`. Une seule règle du prévu dans tout le produit.
- **Le CA prévu restant à facturer** : la vue `v_lignes_revenu_facturation` (prérequis) : `reste_a_facturer` par ligne de CA non annulée = `max(montant_estime − montant facturé des créances liées, 0)`. Le 4.9 la somme par mois, il ne recalcule pas la consommation.
- **Les créances** : `creances_situation(p_date_reference)` (4.5) : `reste_du`, `echeance`, `jours_retard`, `tranche`. Le reste dû n'est jamais recalculé ici.
- **Le réel du mois en cours** : voir « Mois en cours ». Seule lecture nouvelle du réel, justifiée là.
- Côté application : `lib/format.ts`, `exigerRole()`, la barre du CEO, le conteneur de tableau défilant, le composant SVG du 4.7 (graphique).

## Définitions

- **Date de référence** `p_date_reference` (défaut `current_date`) : « aujourd'hui » de la projection. **Mois en cours** = mois de cette date. Les tests la fixent.
- **Horizon** : 12 mois, du mois en cours inclus au 11ᵉ mois suivant (décision D2). Le tableau affiche toujours 12 lignes de mois et les trimestres civils qui les contiennent.
- **Mois projeté** : un mois est projeté si, **et seulement si**, son budget existe **et** tous les mois qui le précèdent dans l'horizon sont projetés (décision D3). La projection s'arrête donc au premier mois sans budget : ce mois et les suivants ont `projete = faux` et des valeurs `null` (aucun chiffre inventé, comme au 4.6 et au 4.8). Si le mois en cours n'a pas de budget, **rien n'est projeté**.
- **Solde de départ** = `solde_caisse_a(p_date_reference)` : solde réel à la **fin de la journée de référence** (décision D1). Solde de début du mois en cours = solde de départ ; solde de début d'un mois suivant = solde de fin du mois précédent ; `solde_fin = solde_debut + résultat`.
- **Résultat d'un mois projeté** = encaissements − dépenses (définis ci-dessous). Pour le mois en cours, ce sont les flux **restant à réaliser** après la date de référence.

### Dépenses d'un mois projeté

- **Mois suivant** : `total_charges_fixes + total_charges_variables` du budget (vue 4.3), diminué/augmenté des reports de la simulation.
- **Mois en cours** : `max(prévu − réel à date, 0)` où « réel à date » = somme des sorties du mois dont `date <= p_date_reference`. Un budget déjà dépassé ne produit pas de dépense négative.

### Encaissements d'un mois projeté (décision D4)

Deux sources, additionnées sans double comptage :

1. **Encaissements du budget** = somme des `reste_a_facturer` des lignes de CA du mois (`v_lignes_revenu_facturation`, prérequis) : chaque ligne est **consommée** par le montant facturé de ses créances liées, plafonnée à 0 **par ligne** ; lignes `annule` exclues. Mois en cours : `max(reste à facturer du mois − (CA réel à date − paiements de créances reçus ce mois à date), 0)`, où CA réel à date = somme des entrées du mois dont `date <= p_date_reference`. Les paiements de créances (`transactions.creance_id`) sont retirés du réel parce que leur créance a déjà consommé sa ligne (ou n'est pas budgétée) : ils ne doivent pas consommer une seconde fois le budget de ventes.
2. **Encaissements des créances** = reste dû des créances **attendues** ce mois-là. Une créance est **attendue** si son reste dû est > 0 et si elle n'est pas dans la tranche `plus_60` (plus de 60 jours de retard : douteuse, exclue de la projection, décision D5). Sa **date d'encaissement attendue** = `greatest(echeance, p_date_reference)` (une créance en retard est attendue aujourd'hui), décalée du retard simulé s'il y en a un. Une créance attendue hors du premier mois non projeté ou au-delà de l'horizon n'apparaît dans aucune ligne.
   - Toute créance attendue compte pour son reste dû, **liée ou non**. Une créance liée a déjà retiré son montant dû de sa ligne (point 1) : la facture **déplace** sa part du budget vers la créance, avec sa vraie échéance et ses paiements reçus, sans double comptage ni perte. Quand la facture couvre la ligne, cela revient à remplacer la ligne par la créance ; une facture partielle laisse le reste de la ligne attendu (scénario 7). Si la créance est soldée ou exclue (`plus_60`), la ligne consommée ne réapparaît pas.
   - Une créance **non liée** ne consomme aucune ligne : elle s'ajoute aux encaissements du budget (le CEO n'a pas dit que le budget la couvrait). Le risque de double comptage dans ce cas est assumé et signalé à l'écran (« N créances ne sont rattachées à aucune ligne du budget »).
   - Une créance liée à une ligne **annulée** (lien inerte, voir le prérequis) se comporte comme une créance non liée.

### Trimestres

Trimestre civil (T1 = janvier à mars…). Un trimestre est affiché s'il contient au moins un mois de l'horizon. Ses flux sont la **somme** de ses mois projetés ; `solde_debut` = début de son premier mois projeté, `solde_fin` = fin de son dernier mois projeté ; `nb_mois_projetes` dit combien de ses mois le sont (3 = complet ; moins = partiel, mention « partiel » à l'écran) ; sans mois projeté, tout est `null`. Le trimestre en cours est « à venir » (flux restant à réaliser).

### Alerte de solde projeté négatif (décision D7)

`solde_negatif` = `solde_fin < 0` (strictement : un solde exactement nul n'alerte pas), par mois et par trimestre. Ce bandeau applique le CDC §4.6 (« alertes visuelles en cas de solde de caisse prévisionnel négatif ») ; il ne contredit pas le 4.8, dont la règle « sans bandeau » vise un solde **constaté**. L'écran affiche en haut un bandeau « Solde de caisse projeté négatif dès {mois année} : {montant} » **en texte et en icône**, jamais la couleur seule, avec le vrai signe moins. Le module 4.9 **n'envoie aucune notification** : le Module 4.12 lira simplement `cashflow_previsionnel()` (lignes `solde_negatif`, premier mois concerné) ; aucun objet SQL de plus.

## Simulateur (décision D6)

**Non stocké en V1.** Aucune table, aucun brouillon, aucune écriture : la simulation vit dans les paramètres de l'appel (et dans l'URL de la page, sans donnée sensible : des identifiants et des nombres). Le résultat est la projection de base **et** la projection simulée côte à côte.

Deux opérations, et seulement elles :

1. **Reporter une dépense** : `{ligne_charge_id, montant, vers_annee, vers_mois}`. La ligne est une ligne de charge prévue (4.3) ; `montant` ≤ montant de la ligne (report partiel autorisé) ; le montant quitte le mois du budget de la ligne et s'ajoute au mois cible. Refusé si la ligne est `annule` ou `realise`, si le mois du budget de la ligne est avant le mois en cours, si le mois cible n'est pas un **mois projeté** ou est identique au mois d'origine.
2. **Retarder un paiement client** : `{creance_id, jours}` avec `jours` > 0. La date d'encaissement attendue est décalée de `jours`. Refusé si la créance n'est pas attendue (soldée ou `plus_60`). Une date décalée hors des mois projetés fait **sortir** le montant de la projection (cas « il arrivera trop tard »).

Hors périmètre du simulateur : modifier un montant, ajouter un flux libre, avancer une dépense, simuler un CA plus faible, enchaîner plusieurs scénarios enregistrés. Plusieurs reports et plusieurs retards dans le même appel sont permis (tableaux).

Toute erreur de simulation est une **exception explicite** (donnée invalide, id introuvable) — mais seulement après la restriction au CEO : un autre appelant obtient zéro ligne, sans erreur. Un id d'une autre entreprise produit la **même** erreur qu'un id inexistant (aucune fuite d'existence).

## Étapes attendues

### 0. Prérequis (brief séparé, validé puis mergé avant le 4.9)

`docs/briefs/Lien-Creance-Revenu-Prevu.md`, en résumé :

- `creances.ligne_revenu_prevu_id uuid null references lignes_revenu_prevu(id) on delete set null` : le lien est **porté par la créance** et choisi par le **comptable** dans le formulaire de créance ; une créance vise au plus une ligne, une ligne peut recevoir **plusieurs** créances ;
- trigger `BEFORE INSERT OR UPDATE` : la ligne appartient à la même entreprise que la créance (même message qu'un id inexistant, testé aussi sans RLS) et n'est pas `annule` au moment du lien ;
- vue `v_lignes_revenu_facturation` (`security_invoker`) : montant facturé et `reste_a_facturer` par ligne, **seule règle de consommation**, lue par le 4.9 ;
- aucune nouvelle policy ; `v_budget_mensuel_totaux` n'est pas modifiée.

### 1. Fonction SQL `cashflow_previsionnel(p_date_reference date default current_date, p_depenses_reportees jsonb default '[]', p_creances_retardees jsonb default '[]')`

Une seule fonction pour le tableau de base et la simulation (choix technique T1). Retourne une ligne par mois (12) et par trimestre affiché :

| Colonne | Contenu |
|---|---|
| `granularite` | `mois` ou `trimestre` |
| `annee`, `periode` | année ; 1–12 (mois) ou 1–4 (trimestre) |
| `statut` | `en_cours` (mois en cours et son trimestre) ou `futur` |
| `projete` | mois : projeté ; trimestre : au moins un mois projeté |
| `nb_mois_projetes` | mois : 0 ou 1 ; trimestre : 0 à 3 |
| `encaissements_budget`, `encaissements_creances`, `encaissements` | `numeric`, `null` si non projeté |
| `depenses`, `resultat` | `numeric` |
| `solde_debut`, `solde_fin` | `numeric` |
| `solde_negatif` | `boolean` (`null` si non projeté) |
| `encaissements_simule`, `depenses_simule`, `resultat_simule`, `solde_debut_simule`, `solde_fin_simule`, `solde_negatif_simule` | idem, avec la simulation appliquée (égaux à la base si les deux tableaux sont vides) |
| `ecart_solde_fin` | `solde_fin_simule − solde_fin` |

Règles de sécurité (identiques au 4.7 et au 4.8) :
- `security invoker`, `set search_path = public`, `stable` ; **jamais** `security definer` ;
- la requête part de la CTE `ent` (`current_entreprise_id()` **et** `current_role_utilisateur() = 'ceo'`) : zéro ligne, pas d'erreur, pour tout autre appelant, **avant** toute validation de la simulation ;
- plpgsql autorisé pour la validation des paramètres (les `raise exception` ne sont atteints que par le CEO) ; le corps ne contient ni `insert`, ni `update`, ni `delete`, ni `perform` d'une fonction qui écrit ;
- naît **sans droit d'exécution** : `revoke all … from public`, `revoke execute … from anon`, `grant execute … to authenticated` ; ACL réelles verrouillées par assertion dans le test (`service_role` reçoit EXECUTE par les privilèges par défaut, comme les fonctions du 4.6 à 4.8) ;
- tous les montants en `numeric`, aucun cast en float ;
- **leçon du 4.8** : la restriction au CEO est répétée à plusieurs niveaux (`solde_caisse_a`, `creances_situation`, RLS) ; le test assère donc **aussi** que le corps de la fonction contient `current_role_utilisateur() = 'ceo'`.

Index : `transactions_date_idx (entreprise_id, date)` sert le réel du mois en cours, l'index de `creances (entreprise_id, echeance)` les créances ; à confirmer dans la PR, aucun index nouveau attendu.

### 2. Écran `/cashflow` (CEO)

- **Tableau groupé par trimestre**, comme l'onglet Excel et le 4.8 : pour chaque trimestre ses mois puis « Total T… (à venir / partiel) ». Colonnes : Période, Encaissements (dont budget, dont créances), Dépenses, Résultat, Solde de caisse au début, Solde de caisse à la fin. Mois non projeté : « Budget non saisi » et valeurs « — ». Lien « Saisir le budget » vers `/budget` si le mois en cours n'est pas projeté.
- **Bandeau d'alerte** de solde négatif (voir plus haut) ; ligne « N créances ne sont rattachées à aucune ligne du budget » ; ligne « Créances de plus de 60 jours non comptées : X FCFA » lue dans `creances_balance_agee` (tranche `plus_60`, 4.5), pas recalculée.
- **Simulateur** sous le tableau : deux petits formulaires (« Reporter une dépense » : ligne de charge, montant, mois cible ; « Paiement client en retard » : créance, nombre de jours) ; bouton « Simuler » (paramètres dans l'URL) et « Annuler la simulation ». En simulation : bandeau **« Simulation — rien n'est enregistré »**, colonnes Solde simulé et Écart à côté du solde de base, graphique à deux courbes (base en trait plein, simulation en tirets, étiquetées en texte).
- Graphique de l'évolution du solde de fin projeté, composant SVG du 4.7 réutilisé (choix T6), sans dépendance.
- Ligne d'explication : « Projection à partir du solde de caisse d'aujourd'hui et des budgets saisis. Elle s'arrête au premier mois sans budget. »
- Mobile : le tableau défile **dans son conteneur**, jamais sur la page (`scrollWidth = clientWidth`) ; `th scope="col"` / `scope="row"`.
- Formatage : `lib/format.ts` ; **aucun calcul** côté TypeScript (ni somme, ni solde, ni écart, ni alerte).
- `exigerRole(["ceo"], "/cashflow")` : 404 pour le comptable et la supervision ; lien « Cashflow » dans la barre du **CEO uniquement** (après « Synthèses ») ; `/cashflow` ajouté aux pages autorisées du CEO (`lib/redirection.ts`).

## Jeu de test chiffré (obligatoire)

Chaque scénario s'exécute dans `BEGIN … ROLLBACK`, avec une **entreprise dédiée**, en tant que son CEO authentifié ; attendus écrits en dur (jsonb, `null` doit rester `null`). **Tous les attendus ci-dessous ont été recalculés par un modèle de référence indépendant du SQL** (script Python écrit à partir des seules règles de ce brief) ; l'implémentation SQL doit les retrouver, et toute divergence est à analyser avant de toucher aux attendus.

### Scénario 1 — entreprise `Cash1`, `cashflow_previsionnel('2026-03-15')`

Solde de caisse **100 000 à la fin du 31 décembre 2025**. Transactions réelles (entrées / sorties) :

| Date | Entrée | Sortie | Note |
|---|---|---|---|
| 2026-01-10 | 340 000 | | ventes |
| 2026-01-15 | | 250 000 | |
| 2026-01-28 | 60 000 | | paiement soldant la créance Epsilon |
| 2026-02-12 | 100 000 | | acompte sur la créance Beta |
| 2026-02-20 | 200 000 | | ventes |
| 2026-02-25 | | 280 000 | |
| 2026-03-05 | 120 000 | | ventes |
| 2026-03-08 | | 90 000 | |
| 2026-03-15 | 50 000 | | paiement partiel sur la créance Gamma (jour de référence) |

**Solde de départ = 350 000** (100 000 + 150 000 + 20 000 + 80 000).

Créances : **Alpha** 200 000, échéance 2026-04-20, rien payé (liée à une ligne du budget d'avril) ; **Beta** 500 000, échéance 2026-05-10, 100 000 payés, reste 400 000 (liée au budget de mai) ; **Gamma** 150 000, échéance 2026-02-28, 50 000 payés, reste 100 000, 15 jours de retard (non liée) ; **Delta** 80 000, échéance 2025-12-01, rien payé, **104 jours de retard → `plus_60`, exclue** (non liée) ; **Epsilon** 60 000, soldée ; **Zeta** 40 000, échéance 2026-04-05, rien payé (non liée).

Budgets (lignes `annule` : la vue les exclut) :

| Mois | CA prévisionnel (lignes) | Charges fixes | Charges variables |
|---|---|---|---|
| Mars | Ventes 300 000 | Loyer 100 000 + Salaires 100 000 | Matières 80 000 |
| Avril | Ventes 250 000 ; **Client Alpha 200 000 (liée)** ; Vente annulée 30 000 (`annule`) | Loyer 100 000 + Salaires 100 000 | Matières 100 000 ; Charge annulée 70 000 (`annule`) |
| Mai | Ventes 200 000 ; **Client Beta 400 000 (liée)** | Loyer 100 000 + Salaires 100 000 | Matières 150 000 |
| Juin | Ventes 100 000 | Loyer 100 000 + Salaires 100 000 | **Achat stock 900 000** (`planifie`) |
| Juillet | Ventes 300 000 | Loyer 100 000 + Salaires 100 000 | Matières 100 000 |
| Août et suivants | **aucun budget** | | |

Attendus, mois (montants en FCFA ; colonnes simulées = base) :

| Mois | Statut | Projeté | Enc. budget | Enc. créances | Encaissements | Dépenses | Résultat | Solde début | Solde fin | Négatif |
|---|---|---|---|---|---|---|---|---|---|---|
| 2026-03 | en_cours | oui | 180 000 | 100 000 | 280 000 | 190 000 | 90 000 | 350 000 | 440 000 | non |
| 2026-04 | futur | oui | 250 000 | 240 000 | 490 000 | 300 000 | 190 000 | 440 000 | 630 000 | non |
| 2026-05 | futur | oui | 200 000 | 400 000 | 600 000 | 350 000 | 250 000 | 630 000 | 880 000 | non |
| 2026-06 | futur | oui | 100 000 | 0 | 100 000 | 1 100 000 | −1 000 000 | 880 000 | **−120 000** | **oui** |
| 2026-07 | futur | oui | 300 000 | 0 | 300 000 | 300 000 | 0 | −120 000 | −120 000 | oui |
| 2026-08 à 2027-02 (7 lignes) | futur | non | `null` | `null` | `null` | `null` | `null` | `null` | `null` | `null` |

Détail à vérifier : mars — budget de ventes 300 000 moins le réel hors créance (170 000 − 50 000 = 120 000) = **180 000** restant ; Gamma attendue le 15 mars (**100 000**) ; dépenses 280 000 − 90 000 = **190 000**. Avril — budget 250 000 (la ligne « Client Alpha » est entièrement consommée : 200 000 − 200 000 = 0) ; créances Alpha 200 000 + **Zeta 40 000 (non liée : s'ajoute)** ; lignes annulées absentes ; dépenses 300 000. Mai — la ligne « Client Beta » (400 000) est consommée par le montant facturé de Beta (500 000), plafonnée à 0 ; Beta compte pour son reste dû **400 000** (non 500 000 : l'acompte de février est déjà au réel). Delta **n'apparaît nulle part** (`plus_60`). Epsilon n'apparaît nulle part (soldée).

Trimestres (5 lignes, T1 2026 à T1 2027) :

| Trimestre | Projeté | Mois projetés | Encaissements | Dépenses | Résultat | Solde début | Solde fin | Négatif |
|---|---|---|---|---|---|---|---|---|
| T1 2026 | oui | 1 | 280 000 | 190 000 | 90 000 | 350 000 | 440 000 | non |
| T2 2026 | oui | 3 | 1 190 000 | 1 750 000 | −560 000 | 440 000 | −120 000 | oui |
| T3 2026 | oui | 1 (partiel) | 300 000 | 300 000 | 0 | −120 000 | −120 000 | oui |
| T4 2026 | non | 0 | `null` | `null` | `null` | `null` | `null` | `null` |
| T1 2027 | non | 0 | `null` | `null` | `null` | `null` | `null` | `null` |

**Cohérences** : `solde_fin = solde_debut + résultat` sur chaque ligne projetée ; continuité mois → mois (4 paires) et trimestre → trimestre ; somme des mois = trimestre ; premier solde = `solde_caisse_a('2026-03-15')` = 350 000 ; **jamais** d'encaissement créance sur un mois sans budget ; le solde de départ (350 000) n'est **pas** le solde de fin de février (270 000) : la différence, 80 000, est le réel de mars à la date de référence (D1).

### Scénario 2 — simulations sur `Cash1` (mêmes données)

Le tableau de base du scénario 1 est **inchangé** à chaque appel (le test le relit après chaque simulation). Lignes qui changent :

| Simulation | Mois | Enc. simulés | Dép. simulées | Résultat simulé | Solde fin simulé | Écart solde fin | Négatif simulé |
|---|---|---|---|---|---|---|---|
| **S2a** — reporter 400 000 d'« Achat stock » de juin à juillet | 2026-06 | 100 000 | 700 000 | −600 000 | 280 000 | +400 000 | non |
| | 2026-07 | 300 000 | 700 000 | −400 000 | −120 000 | 0 | oui |
| **S2b** — Beta payée avec 45 jours de retard (attendue le 2026-06-24) | 2026-05 | 200 000 | 350 000 | −150 000 | 480 000 | −400 000 | non |
| | 2026-06 | 500 000 | 1 100 000 | −600 000 | −120 000 | 0 | oui |
| **S2c** — Beta payée avec 100 jours de retard (attendue le 2026-08-18, hors projection) | 2026-05 | 200 000 | 350 000 | −150 000 | 480 000 | −400 000 | non |
| | 2026-06 | 100 000 | 1 100 000 | −1 000 000 | **−520 000** | −400 000 | oui |
| | 2026-07 | 300 000 | 300 000 | 0 | −520 000 | −400 000 | oui |
| **S2d** — S2b + report de 900 000 d'« Achat stock » à juillet | 2026-06 | 500 000 | 200 000 | +300 000 | 780 000 | +900 000 | non |
| | 2026-07 | 300 000 | 1 200 000 | −900 000 | −120 000 | 0 | oui |

Ce que le scénario prouve : un report ne **crée ni ne détruit** de dépense (S2a : les dépenses de juin et juillet cumulées restent 1 400 000, soit 700 000 + 700 000 contre 1 100 000 + 300 000 en base) ; un retard de paiement **conserve** l'encaissement tant qu'il reste dans la projection (S2b : le solde de fin juin est identique à la base) et le **retire** quand il en sort (S2c) ; le premier mois négatif passe de juin (base) à juillet (S2a, S2d) ; la simulation vide (deux `[]`) redonne exactement la base ; les trimestres simulés sont les sommes des mois simulés (S2b : T2 fin −120 000 ; S2c : T2 fin −520 000).

### Scénario 3 — simulations refusées (`Cash1`, exceptions explicites, toutes en CEO)

Retarder Delta (`plus_60`) ; retarder Epsilon (soldée) ; reporter « Charge annulée » (`annule`) ; reporter 900 001 d'« Achat stock » (plus que la ligne) ; reporter vers août (mois non projeté) ; reporter vers le même mois ; reporter une ligne du budget d'un mois passé ; `jours` ≤ 0 ; montant ≤ 0 ; JSON mal formé ; un `creance_id` / `ligne_charge_id` **d'une autre entreprise** et un id inexistant : **même message d'erreur**.

### Scénario 4 — mois en cours sans budget, entreprise vide

(a) `Cash2` : solde 250 000 au 2025-12-31, aucune transaction, **budgets d'avril et mai seulement**, référence `2026-03-20` : les 12 mois ont `projete = faux` et toutes valeurs `null` (le mois en cours n'a pas de budget ⇒ rien n'est projeté, **même si avril en a un**), 5 trimestres, aucun solde. (b) `Cash3` : aucun budget, aucune créance, aucune transaction : 12 lignes non projetées, aucune erreur ; une simulation (deux tableaux vides) donne le même résultat.

### Scénario 5 — année charnière et transaction future (`Cash4`, `cashflow_previsionnel('2026-11-20')`)

Solde 1 000 000 à la fin du 2026-11-10 ; sortie 100 000 le 2026-11-15 ; entrée 20 000 le 2026-11-20 ; **sortie de 40 000 le 2026-11-25 (postérieure à la date de référence)**. Aucune créance. Budgets : novembre CA 500 000 / fixes 300 000 / variables 100 000 ; décembre 400 000 / 300 000 / 200 000 ; janvier 2027 300 000 / 300 000 / 100 000 ; février 2027 absent.

| Mois | Enc. | Dépenses | Résultat | Solde début | Solde fin |
|---|---|---|---|---|---|
| 2026-11 | 480 000 | 300 000 | 180 000 | **920 000** | 1 100 000 |
| 2026-12 | 400 000 | 500 000 | −100 000 | 1 100 000 | 1 000 000 |
| 2027-01 | 300 000 | 400 000 | −100 000 | 1 000 000 | 900 000 |
| 2027-02 à 2027-10 | non projeté | | | | |

Trimestres : T4 2026 (2 mois) 880 000 / 800 000 / 80 000, 920 000 → 1 000 000 ; T1 2027 (1 mois, partiel) 300 000 / 400 000 / −100 000, 1 000 000 → 900 000 ; T2, T3, T4 2027 non projetés (5 lignes de trimestre). Prouve : continuité **à travers le changement d'année** ; solde de départ à la fin de la **journée** de référence (920 000 = 1 000 000 − 100 000 + 20 000) ; la sortie du 25 novembre **n'est ni dans le solde de départ ni dans le réel à date** (donc ne consomme pas le budget de novembre : dépenses restantes 400 000 − 100 000 = 300 000).

### Scénario 6 — liens et bords (`Cash5`, `cashflow_previsionnel('2026-06-10')`)

Solde 100 000 à la fin du 2026-05-31 ; entrée de 50 000 le 2026-06-05, paiement **soldant** la créance P1 (50 000, échéance 2026-06-30). Créance P2 : 70 000, échéance 2026-03-15, rien payé (**`plus_60`**). Budgets : juin — Ventes 100 000, **P1 50 000 (liée, `ok`)**, charges fixes 150 000 ; juillet — Ventes 100 000, **P2 70 000 (liée)**, charges fixes 200 000. Solde de départ **150 000**.

| Mois | Enc. budget | Enc. créances | Dépenses | Résultat | Solde début | Solde fin | Négatif |
|---|---|---|---|---|---|---|---|
| 2026-06 | 100 000 | 0 | 150 000 | −50 000 | 150 000 | 100 000 | non |
| 2026-07 | 100 000 | 0 | 200 000 | −100 000 | 100 000 | **0** | **non** |

Prouve : ligne liée à une créance **soldée** → entièrement consommée (50 000 − 50 000), rien n'est ajouté (le paiement de P1 n'a pas consommé le budget de ventes de juin : 100 000 intacts) ; ligne liée à une créance `plus_60` → consommée aussi, P2 exclue ; **solde exactement nul = pas d'alerte** (strict).

### Scénario 7 — factures partielles, dépassement, lien inerte (`Cash6`, `cashflow_previsionnel('2026-09-10')`)

Solde 500 000 à la fin du 2026-08-31 ; vente comptant de 80 000 le 2026-09-05 (sans créance). Solde de départ **580 000**. Budgets :

| Mois | CA prévisionnel (lignes) | Charges |
|---|---|---|
| Septembre | **Ventes 400 000**, liée à K1 (150 000, échéance 2026-09-25) et K2 (100 000, échéance **2026-10-15**) | 300 000 |
| Octobre | **Contrat Gamma 200 000**, liée à K3 (250 000, échéance 2026-10-31 : dépassement) ; Ventes 300 000 (non liée) ; **Vente annulée 100 000 (`annule`)**, liée à K4 (60 000, échéance 2026-10-20 : lien inerte) | 400 000 |
| Novembre et suivants | **aucun budget** | |

Aucune créance payée.

| Mois | Enc. budget | Enc. créances | Encaissements | Dépenses | Résultat | Solde début | Solde fin | Négatif |
|---|---|---|---|---|---|---|---|---|
| 2026-09 | 70 000 | 150 000 | 220 000 | 300 000 | −80 000 | 580 000 | 500 000 | non |
| 2026-10 | 300 000 | 410 000 | 710 000 | 400 000 | 310 000 | 500 000 | 810 000 | non |
| 2026-11 à 2027-08 | non projeté | | | | | | | |

Détail : septembre — reste à facturer de « Ventes » 400 000 − 250 000 = 150 000, moins le réel hors créance 80 000 = **70 000** ; K1 150 000. Octobre — « Contrat Gamma » 200 000 − 250 000 → 0 (plafond par ligne), « Ventes » 300 000, ligne annulée absente : **300 000** ; créances K2 100 000 (sa ligne est en septembre, elle arrive à son échéance) + K3 250 000 + K4 60 000 (lien inerte : compte comme non liée) = **410 000**.

Trimestres (5 lignes) : T3 2026 (1 mois, partiel) 220 000 / 300 000 / −80 000, 580 000 → 500 000 ; T4 2026 (1 mois, partiel) 710 000 / 400 000 / 310 000, 500 000 → 810 000 ; T1, T2, T3 2027 non projetés.

Simulation **S7** — K2 payée avec 20 jours de retard (attendue le 2026-11-04, hors projection) : octobre encaissements 610 000, résultat 210 000, solde fin **710 000** (écart −100 000) ; septembre inchangé.

Prouve : une facture **partielle** laisse le reste de sa ligne attendu (l'ancienne règle « la ligne liée est remplacée » donnerait septembre 0 / 150 000 → solde fin 430 000, puis 740 000 en octobre) ; le plafond s'applique **par ligne** (un plafond par mois donnerait 500 000 − 250 000 = 250 000 en octobre au lieu de 300 000) ; une créance liée à une ligne d'un autre mois arrive à **sa** date ; un lien vers une ligne annulée est inerte.

## Tests adversariaux (obligatoires, en utilisateur authentifié réel, jamais en `service_role`)

1. Le **comptable** appelle `cashflow_previsionnel` : zéro ligne, alors qu'il lit les créances et le budget ; avec des tableaux de simulation invalides : **toujours zéro ligne, aucune erreur**.
2. La **supervision Be Smart** (claim `super_admin`) : zéro ligne.
3. **Isolation A / B** : A et B ont chacun budgets, créances et soldes distincts ; chaque CEO ne voit que les siens ; une simulation de A visant une ligne ou une créance de B échoue avec **le même message** qu'un id inexistant.
4. **`anon`** : permission refusée.
5. **ACL réelles** de la fonction assertées (aucun droit pour `public` ni `anon`, `authenticated` autorisé) ; `security invoker`, `stable`, `search_path` fixé ; l'audit d'isolation reste vert.
6. **La simulation ne modifie rien** : empreinte (`md5` des lignes triées) de `transactions`, `budgets_mensuels`, `lignes_charge_prevue`, `lignes_revenu_prevu`, `creances`, `entreprises` relevée **avant et après** chaque simulation des scénarios 2 et 3 (réussies et refusées) : identique ; et la fonction s'exécute dans une transaction `READ ONLY` sans erreur.
7. **Contrôles négatifs** (le test doit échouer si on retire la règle ; à vérifier en local en modifiant temporairement la fonction, puis en la restaurant ; à consigner dans la PR) :
   - restriction au CEO (assertion sur le corps de la fonction **et** test de comportement) ;
   - solde de départ par `solde_caisse_a(p_date_reference)` (et non le solde du dernier mois clos) ;
   - `max(… , 0)` du mois en cours (dépenses et encaissements) ;
   - arrêt de la projection au premier mois sans budget ;
   - exclusion des lignes `annule` (règle de la vue) ;
   - consommation des lignes par `v_lignes_revenu_facturation` (retrait → double comptage d'Alpha et de Beta ; remplacement total de la ligne → scénario 7 septembre à 0 au lieu de 70 000 ; plafond par mois → octobre à 250 000 au lieu de 300 000) ;
   - exclusion des créances `plus_60` et des créances soldées ;
   - retrait des paiements de créances du réel du mois en cours (sinon le budget de ventes de mars passe de 180 000 à 130 000) ;
   - ignorance des transactions postérieures à la date de référence (scénario 5) ;
   - alerte stricte `< 0` (scénario 6) ;
   - conservation d'un retard (S2b) et sortie de projection (S2c).

## Cas limites à couvrir

- Mois en cours sans budget alors que les suivants en ont : rien n'est projeté (scénario 4a).
- Budget du mois en cours **déjà dépassé par le réel** : dépenses restantes 0, jamais négatives ; encaissements restants 0.
- Créance dont le reste dû change entre deux appels (paiement concurrent) : la fonction lit un instantané ; aucune écriture, aucun verrou.
- Une créance attendue le jour de référence compte dans le mois en cours ; une créance échue le dernier jour du mois en cours aussi.
- Plusieurs reports sur la même ligne : leur somme ne peut pas dépasser le montant de la ligne (exception).
- Une ligne de CA liée et `annule` : ignorée (la vue l'exclut), la créance reste attendue et compte comme **non liée** (scénario 7, K4).
- Une ligne de CA facturée au-delà de son montant : reste à facturer 0, jamais négatif, sans effet sur les autres lignes du mois (scénario 7, K3).
- Entreprise dont la date du solde est **postérieure** à la date de référence : `solde_caisse_a` remonte le temps (règle du prérequis daté) ; le tableau est identique dans son principe.

## Hors de ce module

- Notifications de solde négatif et de retard : Module 4.12 (qui lira cette fonction).
- Tableau de bord KPI (« cash disponible estimé ») : Module 4.11 (reprend la fonction).
- Export PDF/CSV de la projection : Module 4.13.
- Simulations enregistrées, comparées ou partagées ; scénarios « et si le CA baisse de 10 % » ; seuil de trésorerie minimale ; probabilité de paiement par client.
- Dettes fournisseurs (hors V1, CDC 4.14) : les dépenses prévues sont celles du budget, supposées payées dans leur mois.
- Modification du Suivi des écarts (4.6) : son « solde prévu repart du réel constaté » reste tel quel ; la chaîne 100 % prévisionnelle est ici, et seulement ici.

## Livrable attendu pour revue

PR depuis `feat/module-4.9-cashflow` vers `main` (le prérequis « Lien créance ↔ revenu prévu » mergé avant) avec :
- le SQL complet de la migration en clair (fonction, GRANT, éventuel index) et les ACL réelles ;
- le résultat réel de chaque scénario comparé aux attendus ci-dessus ;
- la preuve des tests adversariaux et des contrôles négatifs (chaque essai noté, y compris ceux qui ne produisent pas d'échec direct) ;
- une description de l'écran et les captures bureau et mobile ;
- une étape CI pour le test SQL, `/cashflow` dans la matrice de `acces_pages.mjs` (lien de barre du CEO seulement) et les tests unitaires de formatage ;
- CI verte. La migration attend l'approbation explicite d'Ouezz avant merge.

---

## Décisions produit (décidées, Ouezz, 2026-11-12)

*Toutes retenues selon ma recommandation ; les alternatives restent notées pour mémoire.*

**D1 — Point de départ de la projection.** *Décidé : le solde réel à la fin de la journée d'aujourd'hui (`solde_caisse_a(date de référence)`), et le mois en cours projeté sur son « reste à réaliser ».* Raison : c'est le solde que le CEO a réellement en caisse ; partir de la fin du dernier mois clos ignorerait les flux déjà constatés ce mois-ci (ou obligerait à projeter tout le mois en doublon avec le réel). Alternative : fin du dernier mois clos, plus simple mais fausse dès le 2 du mois.

**D2 — Horizon.** *Décidé : 12 mois glissants (mois en cours + 11), avec regroupement en trimestres civils.* Le CDC dit « prochains mois/trimestres » sans borne ; la projection s'arrête de toute façon au premier mois sans budget (D3), donc un horizon large ne coûte rien. Alternative : 6 mois, ou un sélecteur 3/6/12.

**D3 — Mois futur sans budget.** *Décidé : la projection s'arrête au premier mois sans budget (valeurs « — », jamais 0), et si le mois en cours n'a pas de budget, rien n'est projeté.* Raison : un mois sans budget compté à 0 de dépenses donnerait un solde faussement optimiste ; même principe que le 4.6 (« prévu `null` ») et le 4.8 (« le module n'invente aucun chiffre »). Alternatives écartées : reconduire le dernier budget, ou compter 0.

**D4 — Créances et CA prévisionnel du budget (double comptage).** *Décidé : lien explicite « créance ↔ ligne de CA prévisionnel » (prérequis `docs/briefs/Lien-Creance-Revenu-Prevu.md`) : la ligne liée est consommée par le montant facturé de ses créances, qui comptent pour leur reste dû ; une créance non liée s'ajoute au budget.* Précision apportée par le prérequis (sa décision P2, à valider avec lui) : « consommée » plutôt que « remplacée », pour qu'une facture partielle laisse le reste de la ligne attendu ; les scénarios 1 à 6 sont identiques sous les deux formulations, le scénario 7 les distingue. Raison : c'est la seule règle exacte, et elle garde le simulateur honnête. Alternatives écartées : (A) « le plus grand de CA budget et créances » — sans migration et prudent, mais **un retard de paiement peut alors augmenter les encaissements** (le maximum d'un mois baisse quand la créance part, et celui du mois d'arrivée monte : la somme des encaissements n'est plus conservée) : le simulateur serait faux ; (C) « budget + créances toujours additionnés » — sans migration et conservatif pour le simulateur, mais double comptage garanti dès que le CEO budgète une facture (CEO à qui on demanderait de ne budgéter que les ventes comptant). 

**D5 — Créances en retard.** *Décidé : attendues aujourd'hui (mois en cours) tant que le retard est ≤ 60 jours ; au-delà (tranche `plus_60`) exclues de la projection et affichées à part.* Raison : prudence de trésorerie, tranche déjà définie au 4.5. Alternatives : toutes comptées (optimiste), ou un délai de grâce paramétrable (V2).

**D6 — Simulateur.** *Décidé : non stocké en V1, deux opérations seulement (reporter une dépense du budget, retarder un paiement client), calcul par une fonction `stable` qui ne peut pas écrire.* Raison : « une simulation ne modifie jamais le réel » est garanti par construction, sans table ni policy supplémentaires ; le CEO peut garder une simulation en copiant l'URL. Alternative : scénarios enregistrés (table `simulations` avec sa propre RLS, lecture seule vers le reste) : module à part si le besoin se confirme.

**D7 — Alerte de solde projeté négatif.** *Décidé : alerte stricte `< 0`, bandeau dans l'écran du 4.9, aucune notification ici ; le 4.12 lira la fonction.* Pas de seuil de trésorerie minimale en V1. Le bandeau applique le CDC §4.6 (« alertes visuelles en cas de solde de caisse prévisionnel négatif ») : il ne contredit donc pas le 4.8, dont la règle « solde négatif sans bandeau » porte sur un solde **constaté**.

**D8 — Transactions datées dans le futur.** *Décidé : la projection les ignore (ni dans le solde de départ, ni dans le réel à date), et on interdit les dates futures au Journal (4.4) dans un petit module ultérieur.* Rien ne les interdit aujourd'hui (aucune règle dans les migrations du 4.4) : l'interdiction est inscrite comme dette dans la roadmap (petit module ultérieur). Alternative : les compter comme flux connus du mois (plus juste, plus complexe, jamais testé).

**D9 — Dépenses déjà réalisées ou annulées.** *Décidé : une ligne `realise` ou `annule` ne peut pas être reportée dans le simulateur.* Raison : l'argent est déjà sorti (la dépense est dans le réel), ou la ligne n'existe plus dans le prévu.

## Choix techniques (décidés, Ouezz, 2026-11-12)

- **T1 — Une seule fonction `cashflow_previsionnel`** (base + simulation + mois + trimestres) plutôt que plusieurs : une ACL, un jeu de lignes, continuité et conservation prouvées dans la même sortie.
- **T2 — Réutilisation, pas de recalcul** : `solde_caisse_a`, `v_budget_mensuel_totaux` (charges), `v_lignes_revenu_facturation` (CA restant à facturer, prérequis), `creances_situation`, `creances_balance_agee`. Seule nouvelle lecture du réel : les entrées/sorties du mois en cours `<= date de référence` et la part payée sur créances (`transactions.creance_id`) ; recoupées par test avec `ecarts_mensuels` et `solde_caisse_a` quand aucune transaction n'est postérieure à la date de référence.
- **T3 — plpgsql pour la validation de la simulation**, après la restriction au CEO (un non-CEO n'atteint jamais un `raise exception`) ; le reste en SQL. Fonction `stable` : PostgreSQL interdit toute écriture dans une fonction stable, preuve supplémentaire de l'étanchéité du simulateur.
- **T4 — Simulation passée en jsonb** (`[{"ligne_charge_id": …, "montant": …, "vers_annee": …, "vers_mois": …}]` et `[{"creance_id": …, "jours": …}]`) : aucune table, aucun état serveur ; l'écran encode les mêmes paramètres dans l'URL.
- **T5 — Soldes par somme cumulative des résultats mensuels** (comme au 4.8), un seul appel à `solde_caisse_a`.
- **T6 — Graphique du solde projeté** en réutilisant le composant SVG du 4.7 (deux courbes en simulation) : le brief du 4.8 avait écarté tout graphique, mais la projection d'un solde se lit d'abord en courbe. Retenu.
- **T7 — Aucune nouvelle table, aucune nouvelle policy** ; l'étanchéité du simulateur est prouvée par empreintes avant/après et par une exécution en transaction `READ ONLY`.
- **T8 — Prérequis en brief séparé** (`Lien-Creance-Revenu-Prevu`, comme `Solde-Initial-Date`) : un schéma modifié (colonne, trigger, vue) mergé et validé avant la fonction, pour qu'aucune migration ne cumule deux sujets.
- **T9 — Tests** : même style que le 4.7 et le 4.8 (jsonb attendus écrits en dur, `BEGIN … ROLLBACK`, utilisateurs authentifiés réels, contrôles négatifs consignés dans la PR, assertion sur le corps de la fonction pour la restriction au CEO), étape CI dédiée, `/cashflow` dans `acces_pages.mjs`.
