# Brief Claude Code — Module 4.3 : Budget prévisionnel mensuel

*À donner tel quel à Claude Code, depuis `main` (Phase 0, Modules 4.1 et 4.2 mergés). Branche courte dédiée : `feat/module-4.3-budget-previsionnel`.*

## Objectif de ce module (CDC 4.3)

Équivalent numérique des onglets « Prev_[Mois]_[Année] » de l'Excel (CDC 2.1) : pour chaque mois, le CEO saisit les charges fixes prévues, les charges variables prévues et le CA prévisionnel, avec calcul automatique des totaux et du résultat prévisionnel. Réservé au CEO en écriture ; le comptable en a une lecture seule dès maintenant (il en aura besoin pour le rapprochement au Module 4.4 — CDC 4.4).

## Étapes attendues

### 1. Migration — table `budgets_mensuels`

- `id uuid primary key default gen_random_uuid()`, `entreprise_id uuid not null references entreprises(id)`, `mois int not null check (mois between 1 and 12)`, `annee int not null`, `statut text not null default 'brouillon' check (statut in ('brouillon', 'valide'))`, `created_at timestamptz not null default now()`.
- `unique (entreprise_id, mois, annee)` — un seul budget par entreprise et par mois.
- RLS : CEO → select/insert/update sur son entreprise. Comptable → select uniquement (lecture seule, pour rapprochement à venir). GRANT `service_role` posés dès la création (leçon des Modules 4.1/4.2).

### 2. Migration — table `lignes_charge_prevue`

- `id`, `budget_mensuel_id uuid not null references budgets_mensuels(id) on delete cascade`, `entreprise_id uuid not null references entreprises(id)` (dénormalisé volontairement, comme sur toutes les autres tables métier — RLS simple et directe, pas de policy avec sous-requête vers `budgets_mensuels`), `categorie_id uuid not null references categories(id)`, `designation text not null`, `montant numeric not null check (montant >= 0)`, `statut text not null default 'a_faire' check (statut in ('a_faire', 'planifie', 'realise', 'annule'))`, `created_at timestamptz not null default now()`.
- **Deux gardes-fous à implémenter par trigger** (une contrainte `check`/`foreign key` seule ne peut pas exprimer ça) :
  - `entreprise_id` de la ligne doit être identique à celui du `budget_mensuel_id` référencé ET à celui de `categorie_id` référencée. Sans ça, une erreur applicative pourrait attacher une ligne à une catégorie d'une autre entreprise — RLS empêcherait un utilisateur de le *voir* après coup si l'entreprise ne correspond pas à la sienne, mais pas de le créer dans un premier temps si la vérification n'est pas explicite.
  - Le `categorie_id` référencé doit avoir `type in ('fixe', 'variable')` — jamais `'revenu'`. Une charge prévue ne peut pas être rattachée à une catégorie de revenu.
- RLS : CEO → select/insert/update/delete sur son entreprise. Comptable → select uniquement.

### 3. Migration — table `lignes_revenu_prevu`

- `id`, `budget_mensuel_id uuid not null references budgets_mensuels(id) on delete cascade`, `entreprise_id uuid not null references entreprises(id)` (dénormalisé, même raison), `source text not null` (texte libre, fidèle à l'Excel — CDC 2.1 ne catégorise pas les sources de revenu, contrairement aux charges), `montant_estime numeric not null check (montant_estime >= 0)`, `echeance date`, `statut text not null default 'en_attente' check (statut in ('ok', 'en_attente', 'annule'))`, `created_at timestamptz not null default now()`.
- Même garde-fou trigger : `entreprise_id` de la ligne = celui du `budget_mensuel_id` référencé.
- RLS : CEO → select/insert/update/delete sur son entreprise. Comptable → select uniquement.

### 4. Vue des totaux (calcul automatique, CDC 4.3)

- `v_budget_mensuel_totaux` : par `budget_mensuel_id`, calcule le total des charges fixes (SUM des lignes dont la catégorie est de type `fixe`), le total des charges variables (type `variable`), le total du CA prévisionnel (SUM `lignes_revenu_prevu.montant_estime`), et le résultat prévisionnel (CA total − charges fixes − charges variables). Tous les montants en `numeric`, jamais de cast en float.
- RLS/accès : même règle que `budgets_mensuels` — CEO et comptable en lecture, scopé à leur entreprise.

### 5. Duplication des charges récurrentes (CDC 4.3)

- Fonction/RPC `dupliquer_charges_fixes_mois_precedent(p_budget_mensuel_id uuid)` : copie dans le budget cible toutes les `lignes_charge_prevue` de type `fixe` du budget du mois précédent (même entreprise), avec le même `categorie_id`/`designation`/`montant`, mais `statut` réinitialisé à `'a_faire'`.
- Pas besoin de `security definer` : la fonction s'exécute avec les droits de l'appelant, donc les policies RLS existantes (CEO uniquement en écriture) s'appliquent naturellement. Vérifie explicitement que `p_budget_mensuel_id` appartient bien à l'entreprise de l'appelant avant toute copie (lever une exception claire sinon).
- Comportement si le mois précédent n'a pas de budget ou pas de charges fixes : ne rien faire, renvoyer un compte de lignes copiées (0 si rien à dupliquer), pas une erreur.

### 6. Écran (CEO)

- Sélecteur mois/année (créer un budget s'il n'existe pas encore pour le mois choisi).
- Bloc charges fixes prévues, bloc charges variables prévues (les deux via `lignes_charge_prevue`, filtrées par le `type` de la catégorie liée), bloc CA prévisionnel (`lignes_revenu_prevu`) — CRUD complet, catégorie choisie parmi celles définies au Module 4.2.
- Bouton « Dupliquer les charges fixes du mois précédent » → appelle la RPC du point 5.
- Affichage des totaux (depuis la vue) et du résultat prévisionnel.
- Action « Valider le budget » → passe `statut` à `'valide'` (pas de verrouillage des lignes après validation dans cette V1 — sobriété fonctionnelle, à réévaluer plus tard si besoin).
- Contrôle CEO côté serveur, même principe que les modules précédents.

### 7. Tests adversariaux obligatoires

- Un comptable ne peut ni créer, modifier, ni supprimer un budget ou une ligne (RLS), mais lit bien celles de sa propre entreprise (témoin positif, pas de faux positif).
- Le CEO de l'entreprise A ne voit/modifie rien des budgets ou lignes de l'entreprise B.
- Tentative d'attacher une catégorie de type `revenu` à une `ligne_charge_prevue` → rejetée par le trigger.
- Tentative d'attacher (via un id connu, en base) une catégorie d'une autre entreprise à une ligne → rejetée par le trigger, pas seulement invisible via RLS.

## Explicitement hors de ce module

- Verrouillage des lignes après validation du budget — non demandé par le CDC, à ne pas ajouter sans validation explicite.
- Tout calcul d'écart Prévu/Réel (Module 4.6) ou de saisie de transactions réelles (Module 4.4) — ce module ne construit que le prévisionnel.
- Dette technique notée aux Modules 4.1/4.2 (utilisateur Auth orphelin, validation du champ `nom`) — reste dans le suivi, pas dans le scope de ce module sauf si tu as le temps de l'adresser au passage.

## Livrable attendu pour revue

PR depuis `feat/module-4.3-budget-previsionnel` vers `main`, avec :
- Le SQL des migrations en clair dans la description (tables, triggers, vue, RPC de duplication).
- La preuve des quatre tests adversariaux ci-dessus.
- CI verte (jobs existants + nouveaux tests).
