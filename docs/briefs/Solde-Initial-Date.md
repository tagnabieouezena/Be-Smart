# Brief Claude Code — Prérequis du Module 4.8 : solde de caisse initial daté

*Depuis `main` (Modules 4.1 à 4.7 mergés). Branche : `feat/solde-initial-date`. **À implémenter et merger AVANT le Module 4.8**, qui suppose cette règle en place (`docs/briefs/Module-4.8-Syntheses.md`).*

## Pourquoi

Le solde de caisse initial (`entreprises.solde_initial`, Phase 0, éditable au Paramétrage 4.2) **n'a aucune date**. Le Module 4.6 (`ecarts_mensuels`) calcule tous les soldes comme `solde_initial` + résultat net de **toutes** les transactions antérieures à la période, quelle que soit leur date. Conséquence : un CEO qui saisit le solde de caisse **d'aujourd'hui** puis importe l'historique des mois précédents **double-compte** ces mouvements (ils sont déjà dans le solde qu'il vient de saisir). Exemple chiffré du jeu de test ci-dessous : solde saisi 800 000 en octobre, historique de janvier à octobre déjà inclus dedans ; l'ancien calcul affiche 955 000 à la fin d'octobre au lieu de 730 000 (écart de 225 000 = l'historique compté deux fois), et un solde de 800 000 « au 1er janvier ».

Décision d'Ouezz (2026-10-13), **option A** : le solde initial devient **daté**. Aucune donnée n'existe en production : on corrige maintenant, avant que les Modules 4.8, 4.9 et 4.11 ne s'appuient dessus.

## Sémantique retenue

**`date_solde_initial` = la date D à la fin de laquelle `solde_initial` est le solde de caisse.** Le montant saisi est le solde **à la fin de la journée D**, c'est-à-dire **après toutes les transactions datées D**. Les transactions datées D sont donc **incluses dans ce montant** et ne s'y ajoutent jamais.

Pourquoi « fin de journée » plutôt que « début de journée » (choix **décidé par Ouezz le 2026-10-13**, décision n° 1 ci-dessous) :
- c'est l'usage d'un solde nommé par sa date (« solde au 30 septembre » d'un relevé bancaire, « solde au 31 décembre » d'une clôture) : c'est un solde de fin de journée ;
- le cas le plus fréquent est celui d'un CEO qui compte sa caisse **aujourd'hui, après les opérations du jour** : il saisit la date du jour, sans avoir à raisonner sur « demain » ;
- une date future est alors à refuser naturellement (la fin d'une journée à venir ne peut pas être observée).

### Règle unique du solde de caisse

Notations : `D = date_solde_initial`, `S = solde_initial`, `net(transaction) = +montant` pour une entrée, `−montant` pour une sortie. `F(t)` = solde de caisse **à la fin de la journée t**.

- **Pour t ≥ D** : `F(t) = S + Σ net(transactions telles que D < date ≤ t)`, c'est-à-dire de la journée **D+1 à la journée t incluse**.
- **Pour t < D** : `F(t) = S − Σ net(transactions telles que t < date ≤ D)`, c'est-à-dire de la journée **t+1 à la journée D incluse** (on remonte le temps en retirant ce qui s'est passé entre t et D).
- `F(D) = S` (les deux intervalles sont vides).

Intervalles **semi-ouverts à gauche** : la borne basse est exclue, la borne haute incluse. En SQL, avec `d = date_solde_initial` et `t = p_date` :

```sql
S
+ coalesce(sum(case when tx.type = 'entree' then tx.montant else -tx.montant end)
            filter (where tx.date > d and tx.date <= t), 0)
- coalesce(sum(case when tx.type = 'entree' then tx.montant else -tx.montant end)
            filter (where tx.date > t and tx.date <= d), 0)
```

Les deux filtres ne peuvent pas être non vides en même temps (le premier exige `t ≥ d`, le second `t < d`) : **une seule formule**, deux lectures.

**Début et fin de période.** Une période qui commence le jour `s` a pour solde de début `F(s − 1 jour)` ; une période qui finit le jour `e` a pour solde de fin `F(e)`. Le solde de début d'un mois est donc `F(dernier jour du mois précédent)`.

**Identité de continuité** (la propriété qui garantit « fin d'une période = début de la suivante »). Pour `t1 ≤ t2`, quelle que soit la position de D : `F(t2) − F(t1) = Σ net(transactions telles que t1 < date ≤ t2)`. Trois cas : D ≤ t1 (les deux termes ajoutent des tranches de la même suite) ; t2 < D (les deux retranchent, la différence est la tranche entre t1 et t2) ; t1 < D ≤ t2 (la partie après D s'ajoute, la partie avant D se retranche en signe opposé, et les deux recollent en D). Le solde de fin de période = solde de début + résultat net de la période, **toujours**, y compris pour une période qui contient D.

**Aucun solde n'est stocké** : tous les soldes sont recalculés à chaque lecture à partir de `S`, `D` et des transactions. Il n'y a donc **aucun double comptage quel que soit l'ordre de saisie** (solde saisi avant ou après l'import de l'historique), et modifier `S` ou `D` met à jour d'un coup tous les soldes affichés, sans migration de données.

## Étapes attendues

### 1. Migration

1. **Colonne** : `alter table public.entreprises add column date_solde_initial date not null default date '2000-01-01'`. Commentaire de colonne : solde de caisse initial à la **fin** de cette journée (voir « Sémantique »).
2. **Garde-fou** : trigger `BEFORE INSERT OR UPDATE OF date_solde_initial` sur `entreprises` : si `new.date_solde_initial > current_date`, `raise exception 'La date du solde de caisse ne peut pas être dans le futur.'`. Il ne se déclenche pas sur les autres mises à jour (une date existante qui était valide reste valide). `current_date` est la date du serveur de base (UTC, identique à l'heure de Ouagadougou).
3. **Fonction `solde_caisse_a(p_date date)`** : `numeric`, `stable`, `security invoker`, `set search_path = public`. Renvoie `F(p_date)` de l'entreprise de l'appelant **si l'appelant est le CEO**, **`null` pour tout autre appelant** (comptable, supervision) et pour `p_date` null (fonction scalaire : pas de ligne à retourner). Même CTE de restriction que `ecarts_mensuels` (`id = current_entreprise_id()` et `current_role_utilisateur() = 'ceo'`). Née sans droit d'exécution : `revoke all … from public`, `revoke execute … from anon`, `grant execute … to authenticated` explicite ; ACL réelle verrouillée par assertion.
4. **`ecarts_mensuels`** (4.6) : `create or replace` avec **une seule modification** : le solde de début de l'année `solde_initial + somme des transactions antérieures au 1er janvier` est remplacé par **`solde_caisse_a(31 décembre de l'année précédente)`**. Le cumul à l'intérieur de l'année (somme cumulative des résultats réels des mois précédents) reste tel quel : par l'identité de continuité, il reste exact quelle que soit la position de D. La signature, les colonnes, les alertes, la restriction au CEO et l'ACL ne changent pas. **Une seule règle du solde dans tout le produit : `ecarts_mensuels` appelle `solde_caisse_a`, elle ne la recopie pas.**
5. **Index** : `transactions_date_idx (entreprise_id, date)` sert les deux intervalles de la formule ; à confirmer dans la PR, aucun index à ajouter.
6. **Seed et entreprises existantes** : aucune modification du seed. Valeur par défaut `2000-01-01` pour toutes les entreprises (existantes en local, du seed, des tests, et créées par `creer_entreprise_et_ceo`), **justifiée** : (a) aucune transaction ne peut être antérieure, donc `F(t) = S + Σ(date ≤ t)` : le comportement actuel est reproduit **exactement**, tous les attendus du 4.6 et du 4.7 (et les entreprises de test qui n'ont pas de date) restent vrais sans toucher à un seul test ; (b) `not null` supprime un cas « date absente » et garde la règle unique sans branche supplémentaire ; (c) pour une entreprise qui démarre de zéro, « caisse vide avant la première saisie » est le défaut naturel (solde 0 à l'origine des temps) ; (d) le CEO qui a un vrai solde renseigne **les deux valeurs ensemble** (voir écran).
7. Aucune policy ni droit nouveau : la RLS existante de `entreprises` suffit (lecture par l'entreprise, **modification par le CEO seul**, `with check` identique), à vérifier par test. Les vues de supervision (`v_entreprises_supervision`) listent leurs colonnes explicitement : la nouvelle colonne n'y apparaît pas, à vérifier par test.

### 2. Impact sur le Module 4.6 et le reste

| Élément | Impact |
|---|---|
| `ecarts_mensuels` (4.6) | **Modifiée** (point 4 ci-dessus). C'est la **seule** fonction qui lit `solde_initial`. |
| `comparaison_mensuelle`, `comparaison_accueil` (4.7) | Aucune modification : elles ne lisent que le réel de `ecarts_mensuels` (CA, dépenses, résultat), pas les soldes. Leurs tests sont relancés. |
| `seuil_ecart_significatif`, `variation_mensuelle`, `v_budget_mensuel_totaux`, fonctions du 4.5 | Aucune. |
| Écran `/ecarts` (4.6) | Aucun changement de code : les soldes qu'il affiche viennent de la fonction. |
| Écran `/parametrage` (4.2) | Modifié : montant **et** date (étape 3). |
| `creer_entreprise_et_ceo` | Aucune modification : le défaut s'applique. |
| `docs/03-modele-de-donnees.md`, `docs/04-roadmap-suivi-modules.md` | Mise à jour de la colonne et de la règle du solde. |
| Module 4.8 | Utilise `solde_caisse_a` pour le solde d'ouverture de l'année (voir son brief). |

### 3. Écran `/parametrage` (CEO)

La section « Solde de caisse initial » devient **« Solde de caisse »** et porte deux champs saisis et enregistrés **ensemble** (un seul `update` des deux colonnes, atomique) :
- **Solde de caisse (FCFA)** : nombre, transmis **en chaîne** (pas de `Number()`), négatif accepté ;
- **Date du solde** : `input type="date"`, obligatoire, `max` = aujourd'hui, avec l'aide : « Indiquez le solde de votre caisse à la fin de cette journée, après toutes les opérations du jour. Les transactions de cette date et des dates antérieures ne s'y ajoutent pas : elles sont déjà dans ce solde. L'ordre dans lequel vous saisissez le solde et l'historique n'a aucune importance. »
- Affichage de l'état courant : « Solde de {montant} à la fin du {date en toutes lettres} ». Si la date est celle par défaut (`2000-01-01`, constante unique `DATE_DEBUT_HISTORIQUE` côté application), message : « Aucune date renseignée : toutes les transactions saisies s'ajoutent à ce montant. »
- Le message d'erreur de la base (« La date du solde de caisse ne peut pas être dans le futur. ») est affiché tel quel.
- Aucun calcul de solde côté TypeScript.

## Cas à couvrir

| Cas | Traitement |
|---|---|
| Solde saisi aujourd'hui, **puis** import de janvier à septembre | Les soldes antérieurs à D se calculent en remontant : aucun double comptage (scénario A). |
| Date du solde **au milieu** des transactions | Les deux branches de la règle coexistent dans un même exercice ; les mois qui contiennent D sont corrects (scénario A, octobre). |
| Transactions **datées D** | Incluses dans le solde saisi, jamais rajoutées (scénario A : la transaction du 13 octobre). |
| Solde **négatif** | Accepté (montant négatif, ou solde remonté négatif) ; il se propage tel quel (scénario C). |
| Date **dans le futur** | **Refusée** par la base (trigger), message clair : la fin d'une journée à venir ne s'observe pas. `D = aujourd'hui` est accepté (scénario D). |
| **Modification** du montant, de la date ou des deux | Tous les soldes affichés sont recalculés d'un coup, sans migration ; pas d'historique des modifications en V1 (scénario B, décision n° 4). |
| Date par défaut (`2000-01-01`) | Comportement antérieur à l'identique (scénario E, non-régression). |

## Jeu de test chiffré (obligatoire)

Chaque scénario s'exécute dans `BEGIN … ROLLBACK`, avec une **entreprise dédiée**, en tant que son CEO authentifié ; attendus chiffrés écrits en dur, recalculés par script.

### Scénario A — solde saisi en octobre, historique de janvier à septembre importé

Entreprise `Sol1` : **`solde_initial = 800 000`, `date_solde_initial = 2026-10-13`**. Transactions :

| Date | Mouvement | Position par rapport à D |
|---|---|---|
| 2026-01-10 | entrée 300 000 | avant |
| 2026-02-05 | sortie 120 000 | avant |
| 2026-03-20 | entrée 90 000 | avant |
| 2026-05-15 | sortie 60 000 | avant |
| 2026-07-01 | entrée 150 000 | avant |
| 2026-09-30 | sortie 200 000 | avant |
| 2026-10-05 | entrée 40 000 | avant |
| 2026-10-13 | entrée 25 000 | **le jour D** (déjà dans les 800 000) |
| 2026-10-20 | sortie 70 000 | après |

`solde_caisse_a(t)` attendu :

| t | F(t) | Lecture |
|---|---|---|
| 2025-12-31 | 575 000 | 800 000 − (300 − 120 + 90 − 60 + 150 − 200 + 40 + 25 = 225 000) |
| 2026-01-31 | 875 000 | + 300 000 |
| 2026-02-28 | 755 000 | − 120 000 |
| 2026-03-31 | 845 000 | + 90 000 |
| 2026-04-30 | 845 000 | mois sans transaction |
| 2026-05-31 | 785 000 | − 60 000 |
| 2026-06-30 | 785 000 | |
| 2026-07-31 | 935 000 | + 150 000 |
| 2026-08-31 | 935 000 | |
| 2026-09-29 | 935 000 | veille de la sortie du 30 |
| 2026-09-30 | 735 000 | − 200 000 |
| 2026-10-05 | 775 000 | 800 000 − (25 000 du jour D) : avant les opérations du 13 |
| 2026-10-12 | 775 000 | |
| 2026-10-13 | **800 000** | **= solde saisi** (F(D) = S) |
| 2026-10-19 | 800 000 | |
| 2026-10-20 | 730 000 | − 70 000 (après D) |
| 2026-10-31 | 730 000 | |

`ecarts_mensuels(2026, '2026-10-20')` (mois actifs ; `solde_debut` = F(veille du 1er), `solde_fin_reel` = F(dernier jour)) :

| Mois | Résultat réel | Solde de début | Solde de fin |
|---|---|---|---|
| Janvier | +300 000 | 575 000 | 875 000 |
| Février | −120 000 | 875 000 | 755 000 |
| Mars | +90 000 | 755 000 | 845 000 |
| Mai | −60 000 | 845 000 | 785 000 |
| Juillet | +150 000 | 785 000 | 935 000 |
| Septembre | −200 000 | 935 000 | 735 000 |
| **Octobre** (contient D) | −5 000 | 735 000 | 730 000 |

Octobre : +40 000 + 25 000 − 70 000 = −5 000 ; 735 000 − 5 000 = 730 000 = `F(2026-10-31)` ✓. **Contraste avec l'ancien calcul** (à documenter dans la PR, non testé) : solde de début de janvier 800 000 au lieu de 575 000, solde de fin d'octobre 955 000 au lieu de 730 000.

**Ordre de saisie** : le scénario est exécuté trois fois et les trois sorties de `solde_caisse_a` (17 dates) et d'`ecarts_mensuels` sont **identiques** : (1) solde et date saisis d'abord, puis les transactions par ordre chronologique ; (2) toutes les transactions d'abord, solde et date ensuite ; (3) solde saisi, puis octobre, **puis** l'historique de janvier à septembre (le cas du CEO).

### Scénario B — modification du solde ou de sa date (même entreprise)

| Modification | F(2025-12-31) | F(2026-09-30) | F(2026-10-31) |
|---|---|---|---|
| Départ : S = 800 000, D = 2026-10-13 | 575 000 | 735 000 | 730 000 |
| D → **2026-09-30**, S inchangé (800 000) | 640 000 | **800 000** | 795 000 |
| S → **900 000**, D = 2026-10-13 | 675 000 | 835 000 | 830 000 |
| S = **500 000**, D → **2026-06-30** | 290 000 | 450 000 | 445 000 |

Vérifications : D = 2026-09-30 : `F(D) = 800 000` ; D = 2026-06-30 : `F(2026-06-30) = 500 000`. Chaque ligne est obtenue en relisant la fonction **sans rien migrer** après un `update` ; `ecarts_mensuels` suit.

### Scénario C — soldes négatifs

Entreprise `Sol2` : **S = −50 000, D = 2026-03-31**. Transactions : 2026-01-15 entrée 100 000 ; 2026-02-10 sortie 30 000 ; 2026-04-12 entrée 20 000 ; 2026-05-20 sortie 90 000.

| t | F(t) |
|---|---|
| 2025-12-31 | −120 000 |
| 2026-01-31 | −20 000 |
| 2026-02-28 | −50 000 |
| 2026-03-31 | **−50 000** (= S) |
| 2026-04-30 | −30 000 |
| 2026-05-31 | −120 000 |

### Scénario D — bornes de la date

- `update … set date_solde_initial = current_date` : **accepté** ; `current_date + 1` : **refusé**, message « La date du solde de caisse ne peut pas être dans le futur. » ; la ligne n'est pas modifiée.
- Une transaction datée **exactement D** n'est jamais ajoutée (scénario A, 13 octobre) ; datée **D+1** elle l'est ; datée **D−1** elle est retirée en remontant.
- Mise à jour d'une autre colonne (par exemple `nom`) sur une entreprise dont la date est valide : le trigger ne se déclenche pas.

### Scénario E — non-régression

- Une entreprise **sans date explicite** (défaut `2000-01-01`) : `solde_caisse_a(t) = solde_initial + Σ net(date ≤ t)`, et tous les attendus de `suivi_ecarts.sql` (4.6), `comparaison_mensuelle.sql` (4.7) et `creances.sql` sont **inchangés, sans modifier une seule ligne de ces scripts**.
- Une entreprise dont la date est antérieure à toutes ses transactions donne les mêmes soldes qu'avant la migration.

### Scénario F — sécurité (adversarial, en utilisateur authentifié réel)

1. Le **comptable** appelle `solde_caisse_a` : **`null`**, alors qu'il lit les transactions de son entreprise ; il tente `update entreprises set date_solde_initial = …` : **0 ligne modifiée** (RLS), valeur inchangée.
2. Le compte de **supervision** : `null` ; l'écriture est refusée.
3. **Isolation A / B** : le CEO de A ne peut ni lire la valeur de B par la fonction (il obtient la sienne) ni modifier le solde ou la date de B (0 ligne) ; les deux entreprises ont des soldes et des dates différents.
4. **`anon`** : appel refusé (`permission denied`).
5. **ACL** de `solde_caisse_a` (aucun droit pour `public` ni `anon`, `authenticated` autorisé) et de `ecarts_mensuels` (inchangée), assertions verrouillées ; l'audit d'isolation reste vert.
6. `v_entreprises_supervision` n'expose ni `solde_initial` ni `date_solde_initial`.
7. **Contrôles négatifs** (à consigner dans la PR) : le test doit échouer si on retire (a) la restriction au CEO de `solde_caisse_a`, (b) la branche « t < D » (scénario A, mois avant octobre), (c) l'exclusion de la journée D (borne `>` au lieu de `>=`), (d) le trigger de date future, (e) l'appel à `solde_caisse_a` dans `ecarts_mensuels`.

## Hors de ce module

- Historique ou journal des modifications du solde initial (CDC 3.3 traite la traçabilité des transactions, pas des réglages) : non prévu en V1.
- Rapprochement de caisse, pointage bancaire, plusieurs comptes de caisse : hors périmètre V1.
- Soldes prévisionnels (cashflow, 4.9) : le solde prévu repart du solde réel (décision du 4.6), inchangé.

## Livrable attendu pour revue

PR depuis `feat/solde-initial-date` vers `main`, avec : le SQL complet de la migration en clair dans la description (colonne, trigger, fonction, `create or replace ecarts_mensuels`) et les ACL réelles ; le résultat réel de chaque scénario comparé aux attendus ; la preuve des tests adversariaux et des contrôles négatifs ; les captures du formulaire de Paramétrage ; les tests existants du 4.6 et du 4.7 inchangés et verts ; CI verte. **La migration attend l'approbation explicite d'Ouezz avant merge.**

## Décisions

### Décisions produit (décidées, Ouezz, 2026-10-13)

- **Le solde initial est daté (option A)**, avant que d'autres modules ne s'appuient dessus (aucune donnée en production).
1. **Sémantique « fin de journée »** : `solde_initial` est le solde à la **fin** du jour D (opérations de D comprises). *(Alternative écartée : début de journée.)*
2. **Valeur par défaut `2000-01-01`** pour toutes les entreprises (existantes, du seed, créées à l'inscription) : reproduit exactement le comportement actuel ; l'écran affiche « **Aucune date renseignée** » tant que le CEO ne l'a pas fixée. *(Alternative écartée : date de création de l'entreprise.)*
3. **Date future refusée.** Une date du jour est acceptée.
4. **Modifier le montant ou la date recalcule tout l'historique affiché**, sans trace des anciennes valeurs : **pas d'historique des modifications en V1**.
5. **Lecture de `solde_initial` et de sa date par le comptable** (RLS de lecture de l'entreprise, préexistante) : **on ne change rien en V1.** Le comptable lit aussi toutes les transactions et peut déjà reconstituer la caisse ; restreindre ces deux colonnes dépasserait ce module.

### Choix techniques proposés

- **Une fonction scalaire `solde_caisse_a(date)`**, appelée par `ecarts_mensuels` et par le Module 4.8 : une seule écriture de la règle, testée à un seul endroit.
- **Formule à deux filtres sur un seul balayage** (une lecture de `transactions` par appel, index `transactions_date_idx`), plutôt que deux branches `if` : impossible d'oublier un cas, et la continuité se prouve par identité.
- **Aucun solde stocké** (ni colonne dérivée, ni table de soldes) : l'ordre de saisie n'a aucune influence et la modification est sans migration ; coût : un calcul par lecture, négligeable (une somme indexée).
- **`ecarts_mensuels` modifiée a minima** (une seule CTE) : le cumul interne à l'année est conservé parce que l'identité de continuité le garantit exact ; moins de risque de régression sur un module mergé.
- **Trigger plutôt que `check`** pour la date future : un `check` avec `current_date` est non immutable et serait réévalué à des moments inattendus (restauration) ; le trigger ne se déclenche que quand la date change.
- **Constante `DATE_DEBUT_HISTORIQUE` unique côté application** pour reconnaître le défaut dans l'affichage ; la valeur de référence vit dans la migration.
