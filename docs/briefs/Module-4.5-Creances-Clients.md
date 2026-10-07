# Brief Claude Code — Module 4.5 : Suivi des créances clients

*Depuis `main` (Modules 4.1 à 4.4 et 4.6 mergés). Branche : `feat/module-4.5-creances`.*

## Objectif (CDC 4.5)

Suivre l'argent dû par les clients : une créance = un client, un montant dû, une date de facturation, une échéance. Le CDC exige un statut (en attente / partiellement payé / payé / en retard), le montant déjà encaissé, le total des créances en cours, une balance âgée simple, une alerte en cas de dépassement d'échéance, et surtout : **quand le client paie, la créance devient automatiquement une transaction réelle, sans ressaisie.**

Saisie et mise à jour par le comptable ; consultation par le CEO (CDC 4.5, même logique que le 4.4). Aucun accès pour la supervision Be Smart.

## Décisions de conception (actées par Ouezz)

1. **Le statut et le montant encaissé ne sont jamais stockés.** Ils sont calculés à partir des transactions liées à la créance (`transactions.creance_id`). Pas de colonne `statut` ni `montant_encaisse` sur `creances`. Raison : une valeur stockée peut diverger de l'argent réellement reçu ; une valeur calculée, jamais.
2. **Encaisser = insérer une transaction d'entrée liée à la créance.** C'est une seule écriture, donc atomique par nature. Il n'y a aucune mise à jour de la créance ni des transactions (cohérent avec l'interdiction d'update du 4.4). Les paiements partiels sont plusieurs transactions liées à la même créance.
3. **Priorité des statuts**, calculés à une date de référence :
   - `paye` si le reste dû = 0 ;
   - sinon `en_retard` si l'échéance < date de référence ;
   - sinon `partiellement_paye` si le montant encaissé > 0 ;
   - sinon `en_attente`.
   Une créance partiellement payée et échue est donc `en_retard`, avec son montant encaissé affiché à côté.
4. **Balance âgée** : sur le reste dû des créances non soldées, quatre tranches selon le nombre de jours écoulés depuis l'échéance : `non_echue` (≤ 0 jour), `1_30`, `31_60`, `plus_60`.
5. **« Total en cours visible par mois »** : total du reste dû à la date de référence, et ventilation de ce reste par mois d'échéance.
6. **Suppression** d'une créance autorisée au comptable uniquement si aucune transaction n'y est liée (une saisie erronée sans argent reçu). Dès qu'un paiement existe, la suppression est impossible (clé étrangère `on delete restrict`).
7. **Alerte d'échéance dépassée** : uniquement visuelle dans ce module (badge « En retard »). Les notifications relèvent du Module 4.12.

## Étapes attendues

### 1. Migration — table `creances`

- Colonnes :
  - `id uuid primary key default gen_random_uuid()` ;
  - `entreprise_id uuid not null references entreprises(id)` ;
  - `client text not null check (length(trim(client)) > 0)` ;
  - `montant_du numeric not null check (montant_du > 0)` ;
  - `date_facturation date not null` ;
  - `echeance date not null` ;
  - `notes text` ;
  - `saisi_par uuid not null references utilisateurs(id)` ;
  - `created_at timestamptz not null default now()` ;
  - contrainte `check (echeance >= date_facturation)`.
- `saisi_par` est forcé à `auth.uid()` par un trigger `BEFORE INSERT` (même pattern que `transactions` au 4.4 : la valeur est écrasée sauf si `auth.uid()` est NULL, cas du seed et de `service_role`).
- Index sur `creances (entreprise_id, echeance)`.
- GRANT `service_role` posés dès la création.
- RLS :
  - comptable : `select`, `insert`, `update`, `delete` sur son entreprise ;
  - CEO : `select` uniquement ;
  - aucune policy pour les autres rôles.
- Trigger `BEFORE UPDATE` sur `creances` :
  - `entreprise_id` et `saisi_par` sont immuables ;
  - `montant_du` ne peut pas descendre sous le montant déjà encaissé (somme des transactions liées). Sinon : exception explicite.

### 2. Migration — lien `transactions.creance_id`

- `alter table transactions add column creance_id uuid references creances(id) on delete restrict` (nullable).
- Étendre le trigger `BEFORE INSERT` existant de `transactions` (ne pas en créer un second qui ferait doublon). Si `creance_id` est renseigné :
  - la créance doit appartenir au même `entreprise_id` que la transaction ;
  - `type` doit valoir `'entree'` ;
  - **verrouiller la ligne de la créance** (`select … for update`) avant de calculer le reste dû, pour qu'aucun paiement concurrent ne puisse passer entre le calcul et l'insert ;
  - `montant` doit être ≤ reste dû (`montant_du` − somme des transactions déjà liées). Sinon : exception explicite (« Le paiement dépasse le reste dû : X FCFA »).
- Une transaction peut porter à la fois `creance_id` et `ligne_revenu_prevu_id`. Aucune logique nouvelle : le rapprochement du 4.4 s'applique tel quel.
- Les encaissements sont des transactions normales : ils remontent automatiquement dans les revenus réels du Module 4.6, sans rien ajouter.

### 3. Fonctions de lecture (calcul du statut et de la balance âgée)

- `creances_situation(p_date_reference date default current_date)` renvoie une ligne par créance de l'entreprise de l'appelant :
  - les champs de la créance ;
  - `montant_encaisse` et `reste_du` ;
  - `statut` (selon la priorité de la décision 3) ;
  - `jours_retard` (0 si non échue) ;
  - `tranche` (`non_echue` / `1_30` / `31_60` / `plus_60`, ou `null` si payée).
- `creances_balance_agee(p_date_reference date default current_date)` renvoie, pour l'entreprise de l'appelant :
  - le total en cours (somme des restes dus non soldés) ;
  - le total par tranche ;
  - la ventilation du reste dû par mois d'échéance.
- Règles communes aux deux fonctions :
  - `security invoker` et `set search_path = public` ;
  - filtre `entreprise_id = current_entreprise_id()` ;
  - accessibles au comptable et au CEO, zéro ligne pour tout autre rôle (dont la supervision) ;
  - `revoke execute … from public`, puis `grant execute` à `authenticated` uniquement ; à vérifier sur les ACL réelles et à verrouiller par assertion, comme au 4.6 ;
  - tous les montants en `numeric`, jamais en float.

### 4. Écran `/creances`

- Liste des créances avec : client, montant dû, encaissé, reste dû, échéance, statut, jours de retard. Badge visuel « En retard » qui ne repose pas sur la couleur seule. Filtre par statut.
- Bloc de synthèse : total en cours, balance âgée (quatre tranches), reste dû par mois d'échéance.
- Comptable :
  - formulaire de création et d'édition (client, montant dû, date de facturation, échéance, notes) ;
  - suppression proposée seulement si rien n'a été encaissé ;
  - bouton **« Enregistrer un paiement »** qui ouvre le formulaire de transaction du 4.4 pré-rempli : type entrée, `creance_id`, montant proposé = reste dû (modifiable à la baisse), description `Encaissement créance — {client}`. La comptable choisit seulement la catégorie de revenu et le mode de paiement. C'est la « transformation automatique sans ressaisie » du CDC.
- CEO : la même vue, en lecture seule (aucun bouton d'écriture, et contrôle côté serveur).
- Contrôle de rôle côté serveur, comme pour les modules précédents. Montants au format FCFA francophone.

### 5. Tests de calcul chiffrés (obligatoires)

Entreprise dédiée dans `BEGIN … ROLLBACK`. Date de référence : `2026-10-15`.

| Créance | Client | Montant dû | Facturation | Échéance | Paiements liés |
|---|---|---|---|---|---|
| C1 | Alpha | 300 000 | 2026-08-01 | 2026-08-31 | 100 000 le 2026-09-10 |
| C2 | Beta | 150 000 | 2026-09-20 | 2026-10-20 | aucun |
| C3 | Gamma | 80 000 | 2026-07-01 | 2026-07-31 | 80 000 le 2026-08-05 |
| C4 | Delta | 50 000 | 2026-06-01 | 2026-06-30 | aucun |
| C5 | Epsilon | 60 000 | 2026-09-01 | 2026-09-30 | aucun |

Attendus de `creances_situation('2026-10-15')` :

| Créance | Encaissé | Reste dû | Statut | Jours de retard | Tranche |
|---|---|---|---|---|---|
| C1 | 100 000 | 200 000 | `en_retard` | 45 | `31_60` |
| C2 | 0 | 150 000 | `en_attente` | 0 | `non_echue` |
| C3 | 80 000 | 0 | `paye` | 0 | `null` |
| C4 | 0 | 50 000 | `en_retard` | 107 | `plus_60` |
| C5 | 0 | 60 000 | `en_retard` | 15 | `1_30` |

Attendus de `creances_balance_agee('2026-10-15')` :
- total en cours = 460 000 ;
- `non_echue` = 150 000 ; `1_30` = 60 000 ; `31_60` = 200 000 ; `plus_60` = 50 000 (somme = 460 000) ;
- par mois d'échéance : juin 2026 = 50 000, août 2026 = 200 000, septembre 2026 = 60 000, octobre 2026 = 150 000.

Cas complémentaires :
- Un paiement de 200 000 sur C1 → accepté, C1 passe à `paye` et sort du total en cours (qui tombe à 260 000).
- Avec la date de référence `2026-10-01`, C1 non soldée (reste 200 000) avant échéance fictive : vérifier qu'une créance partiellement payée **non échue** donne `partiellement_paye`. Créer pour cela C6 : 100 000, échéance 2026-10-31, un paiement de 30 000 → `partiellement_paye`, reste 70 000, tranche `non_echue`.

### 6. Tests adversariaux (obligatoires, en utilisateur authentifié réel, jamais en `service_role`)

1. **Surpaiement** : un paiement de 200 001 sur C1 (reste 200 000) est rejeté.
2. **Paiements concurrents** : deux sessions `psql` distinctes. La session 1 ouvre une transaction et insère un paiement de 150 000 sur C1 sans commiter ; la session 2 tente un paiement de 150 000 sur C1. Attendu : la session 2 attend le verrou, puis est rejetée après le commit de la session 1 (reste insuffisant). Il faut une preuve avec la sortie des deux sessions, pas un raisonnement.
3. Une transaction de type `sortie` liée à une créance est rejetée.
4. Une transaction liée (via un id connu en base) à une créance d'une autre entreprise est rejetée par le trigger, pas seulement rendue invisible par la RLS.
5. Baisser `montant_du` de C1 sous le montant encaissé est rejeté.
6. Supprimer une créance qui a un paiement lié est rejeté ; supprimer C2 (sans paiement) est accepté.
7. Le CEO ne peut ni créer, ni modifier, ni supprimer une créance, mais il lit bien celles de son entreprise (témoin positif).
8. Le comptable et le CEO de l'entreprise B ne voient rien des créances de A, ni par la table, ni par les deux fonctions.
9. La supervision Be Smart obtient zéro ligne sur la table et sur les deux fonctions ; `anon` est refusé.
10. Forger `saisi_par` à l'insert d'une créance : la valeur est écrasée par l'appelant réel (relue en base).

## Hors de ce module

- Dettes fournisseurs (CDC 4.14).
- Notifications et rappels d'échéance (Module 4.12) : ici, l'alerte est seulement visuelle.
- Total des créances dans le tableau de bord KPI (Module 4.11).
- Facturation, devis, relances automatiques.
- Avoir ou annulation d'une créance partiellement payée : non demandé par le CDC. À traiter plus tard si un besoin réel apparaît.

## Livrable attendu pour revue

PR depuis `feat/module-4.5-creances` vers `main`, avec :
- le SQL complet en clair dans la description (table, colonne `creance_id`, triggers, fonctions, policies, GRANT) ;
- l'obtenu vs attendu des tests chiffrés, créance par créance ;
- la preuve des 10 tests adversariaux, dont la sortie des deux sessions du test de concurrence ;
- CI verte.
