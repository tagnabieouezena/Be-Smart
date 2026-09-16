# Brief Claude Code — Module 4.2 : Paramétrage

*À donner tel quel à Claude Code, depuis `main` (Modules 4.1 et Phase 0 mergés). Branche courte dédiée : `feat/module-4.2-parametrage`.*

## Objectif de ce module (CDC 4.2)

Donner au CEO les écrans de paramétrage de son entreprise, préalables à tout le reste (budget, transactions, KPI en dépendent) :
1. Catégories de charges (fixes/variables) et de revenus, personnalisables par entreprise.
2. Modes de paiement disponibles.
3. Objectifs de chiffre d'affaires par mois/trimestre/année.
4. Solde de caisse initial (déjà en base depuis la Phase 0 — ce module lui donne un écran).

Tout ce module est **réservé au CEO**. Le comptable a un accès en lecture seule aux catégories (pour catégoriser ses saisies plus tard) et aucun accès aux objectifs (donnée stratégique, CDC 3.2).

## Étapes attendues

### 1. Migration — table `categories`

- `id uuid primary key default gen_random_uuid()`, `entreprise_id uuid not null references entreprises(id)`, `libelle text not null`, `type text not null check (type in ('fixe', 'variable', 'revenu'))`, `created_at timestamptz not null default now()`.
- RLS : CEO de l'entreprise → select/insert/update/delete sur ses propres catégories. Comptable de l'entreprise → select uniquement. Isolation multi-tenant stricte comme les tables existantes (via `current_entreprise_id()`).
- Contrainte d'unicité raisonnable : pas deux catégories au même libellé pour le même type dans la même entreprise (`unique (entreprise_id, type, libelle)`).

### 2. Migration — table `objectifs_ca`

- `id uuid primary key default gen_random_uuid()`, `entreprise_id uuid not null references entreprises(id)`, `type_periode text not null check (type_periode in ('mensuel', 'trimestriel', 'annuel'))`, `annee int not null`, `mois int check (mois between 1 and 12)`, `trimestre int check (trimestre between 1 and 4)`, `montant_cible numeric not null check (montant_cible >= 0)`, `created_at timestamptz not null default now()`.
- Contrainte de cohérence : `mois` renseigné seulement si `type_periode = 'mensuel'`, `trimestre` seulement si `'trimestriel'`, aucun des deux si `'annuel'` (`check` combiné).
- Contrainte d'unicité : un seul objectif par `(entreprise_id, type_periode, annee, mois, trimestre)`.
- RLS : **CEO uniquement**, en lecture et en écriture. Le comptable n'a aucune policy sur cette table — un `select` de sa part doit renvoyer zéro ligne, pas une erreur : donnée stratégique, cf. CDC 3.2 et le principe de sécurité incontournable.

### 3. Modes de paiement — décision de conception à valider

Le CDC ne dit pas explicitement que les modes de paiement sont personnalisables par entreprise (contrairement aux catégories). Je pars donc sur une liste fixe pour la V1, pas de table dédiée :
- `check (mode_paiement in ('cash', 'mobile_money', 'virement', 'cheque'))` directement sur la colonne `mode_paiement` des `transactions` (Module 4.4, à venir).
- L'écran de paramétrage affiche cette liste en lecture seule (référence), sans CRUD.

Si tu (Ouezz) veux que Be Smart permette à une entreprise d'ajouter ses propres modes de paiement, dis-le avant que Claude Code implémente le Module 4.4 — ça changerait ce point en une vraie table `modes_paiement` avec RLS, comme `categories`. Pas bloquant pour ce module-ci, juste à trancher avant que `transactions` fige la colonne.

### 4. Écran de paramétrage (CEO uniquement)

- Page `/parametrage` (ou équivalent), trois sections :
  - **Catégories** : liste + création + édition + suppression, par type (fixe/variable/revenu).
  - **Objectifs de CA** : liste + création + édition, par période (mensuel/trimestriel/annuel).
  - **Solde de caisse initial** : affichage et édition du `solde_initial` de l'entreprise (déjà en base, table `entreprises` — pas de nouvelle colonne, juste un formulaire relié à l'`update` déjà permis par la policy CEO existante).
- Modes de paiement : bloc informatif en lecture seule (liste fixe, voir point 3).
- Accès contrôlé côté serveur (vérification du rôle CEO), pas seulement une page cachée dans la nav — même principe que le Module 4.1.

### 5. Tests adversariaux obligatoires

- Un comptable qui tente une écriture sur `categories` (insert/update/delete) est rejeté par RLS.
- Un comptable qui tente de lire `objectifs_ca` reçoit zéro ligne (pas une erreur — comportement normal de RLS sans policy correspondante), à vérifier explicitement dans un test, pas supposé.
- Le CEO de l'entreprise A ne peut ni lire ni modifier les catégories ou objectifs de l'entreprise B.

## Explicitement hors de ce module

- Dette technique notée au Module 4.1 (nettoyage de l'utilisateur Auth orphelin en cas d'échec d'insertion, validation du champ `nom` sur l'invitation comptable) : si tu as le temps de les adresser dans cette même PR, tant mieux, sinon on garde ça pour un brief dédié plus tard — ne pas laisser ça bloquer ce module.
- Toute logique de `transactions` ou de `budgets_mensuels` (Modules 4.3/4.4) — ce module ne fait que poser les réglages qu'ils consommeront.

## Livrable attendu pour revue

PR depuis `feat/module-4.2-parametrage` vers `main`, avec :
- Le SQL des deux nouvelles migrations en clair dans la description.
- La preuve des trois tests adversariaux ci-dessus.
- CI verte (jobs existants + nouveaux tests).
