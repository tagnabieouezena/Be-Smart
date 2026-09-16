# Brief Claude Code — Module 4.4 : Journal des transactions réelles

*À donner tel quel à Claude Code, depuis `main` (Phase 0, Modules 4.1, 4.2, 4.3 mergés). Branche courte dédiée : `feat/module-4.4-journal-transactions`.*

## Objectif de ce module (CDC 4.4)

Équivalent numérique de l'onglet « Transactions » de l'Excel (CDC 2.1), avec les contrôles que l'Excel n'avait pas : saisie rapide des entrées/sorties réelles d'argent par la comptable, traçabilité complète (qui a saisi quoi, quand — CDC 3.3), rapprochement optionnel avec une ligne de CA prévisionnel (CDC 4.4), justificatif photo. Le comptable saisit et lit ses propres saisies ; le CEO lit tout, sans droit d'écriture sur ce module (CDC 3.1/3.2 : la saisie réelle reste un acte de la comptable, le CEO consulte et valide en amont via le budget).

## Étapes attendues

### 1. Migration — table `transactions`

- `id uuid primary key default gen_random_uuid()`, `entreprise_id uuid not null references entreprises(id)`, `date date not null`, `description text not null`, `categorie_id uuid not null references categories(id)`, `type text not null check (type in ('entree', 'sortie'))`, `montant numeric not null check (montant > 0)` (toujours positif — le sens entrée/sortie porte l'information, jamais de montant négatif), `mode_paiement text not null check (mode_paiement in ('cash', 'mobile_money', 'virement', 'cheque'))` (liste fixe, décision Ouezz déjà actée au Module 4.2), `saisi_par uuid not null references utilisateurs(id)`, `notes text`, `ligne_revenu_prevu_id uuid references lignes_revenu_prevu(id)` (nullable — rapprochement optionnel, CDC 4.4), `justificatif_path text` (chemin dans Supabase Storage, nullable — voir point 3), `created_at timestamptz not null default now()`.
- `saisi_par` renseigné côté serveur à partir de la session de l'appelant (jamais transmis par le client) — même principe que `entreprise_id` sur les routes serveur des modules précédents, ici via `default auth.uid()` ou équivalent forcé côté trigger/policy plutôt que confié à l'UI.
- GRANT `service_role` posés dès la création (leçon des Modules 4.1/4.2), même si ce module n'a pas encore de route serveur `service_role` identifiée — pose-les par cohérence et anticipation.
- RLS : Comptable → insert sur son entreprise (avec `saisi_par = auth.uid()` forcé), select sur **l'ensemble des transactions de son entreprise** — décision Ouezz : le CDC 3.2 parle de « ses propres saisies », mais l'accès en lecture est volontairement élargi à toute l'entreprise (comptable et CEO), pour que l'historique et le rapprochement restent cohérents si plusieurs comptables se succèdent. Pas d'update/delete pour personne dans cette V1 (une transaction saisie est un fait constaté — correction = nouvelle transaction, pas de retouche a posteriori ; sobriété fonctionnelle et intégrité comptable). CEO → select uniquement sur son entreprise, aucune écriture.

- **Garde-fou trigger obligatoire** (même pattern que Module 4.3, `BEFORE INSERT`) :
  - `entreprise_id` de la transaction doit être identique à celui de `categorie_id` référencée ET à celui de `ligne_revenu_prevu_id` référencée si elle est renseignée.
  - Cohérence `type` / catégorie : si `type = 'entree'`, la catégorie référencée doit être de `type = 'revenu'` ; si `type = 'sortie'`, la catégorie référencée doit être de `type in ('fixe', 'variable')`. Une transaction ne peut jamais porter un type incohérent avec sa catégorie.

### 2. Rapprochement automatique (CDC 4.4)

- Quand une transaction est créée avec `ligne_revenu_prevu_id` renseigné, un trigger `AFTER INSERT` met à jour le statut de la `ligne_revenu_prevu` correspondante à `'ok'` (le paiement attendu est arrivé). Vérifie que la ligne appartient bien à la même entreprise (déjà garanti par le garde-fou du point 1, mais le trigger de mise à jour doit rester défensif).
- Pas de rapprochement symétrique côté charges dans cette V1 (CDC 4.4 ne le demande que pour le CA prévisionnel) — à ne pas ajouter sans validation explicite.

### 3. Justificatif photo — Supabase Storage

- Bucket `justificatifs`, privé (pas de lecture publique).
- Convention de chemin : `{entreprise_id}/{transaction_id}/{nom_fichier}` — permet des policies Storage RLS simples basées sur le premier segment du chemin.
- Policies Storage : lecture/écriture réservées aux utilisateurs de l'entreprise correspondante (comptable insert, CEO+comptable select), en s'appuyant sur `current_entreprise_id()` comme pour les tables classiques.
- Upload déclenché depuis le formulaire de saisie ; `justificatif_path` renseigné dans la ligne `transactions` après upload réussi. Si l'upload échoue, la transaction reste créable sans justificatif (champ nullable) — ne pas bloquer la saisie sur un problème de connexion (CDC 5.1 : contexte de connexion instable).

### 4. Écran

- Formulaire de saisie rapide (comptable) : date, description, catégorie (filtrée par type selon entrée/sortie choisi), type, montant, mode de paiement, notes optionnelles, upload justificatif optionnel, sélection optionnelle d'une ligne de CA prévisionnel à rapprocher (liste des `lignes_revenu_prevu` en statut `en_attente` du mois en cours pour l'entreprise).
- Liste des transactions (comptable et CEO) : filtres par période, catégorie, responsable (`saisi_par`), mode de paiement (CDC 4.4) — filtrage côté requête, pas seulement côté client, pour rester utilisable avec un historique important (CDC 5.3).
- Affichage de l'auteur et de la date de saisie sur chaque ligne (traçabilité, CDC 3.3).
- Accès contrôlé côté serveur (comptable et CEO seulement, pas de rôle tiers) — même principe que les modules précédents.

### 5. Tests adversariaux obligatoires

- Le CEO ne peut ni créer ni modifier ni supprimer de transaction (RLS), mais lit bien celles de son entreprise (témoin positif).
- Le comptable de l'entreprise A ne voit/modifie rien des transactions de l'entreprise B.
- Tentative de créer une transaction `type = 'entree'` liée à une catégorie de type `fixe` ou `variable` → rejetée par le trigger (et inversement pour `sortie` avec une catégorie `revenu`).
- Tentative d'attacher (via un id connu, en base) une catégorie ou une `ligne_revenu_prevu` d'une autre entreprise à une transaction → rejetée par le trigger, pas seulement invisible via RLS.
- Une transaction créée avec `ligne_revenu_prevu_id` renseigné fait bien passer le statut de cette ligne à `'ok'` (preuve du rapprochement automatique).
- Tentative de forger `saisi_par` avec l'id d'un autre utilisateur lors de l'insert → soit rejetée, soit silencieusement écrasée par la valeur serveur (à prouver explicitement, pas supposé).

## Explicitement hors de ce module

- Import/export CSV ou Excel (mentionné au CDC 4.4) — reporté à un brief dédié ultérieur, non bloquant pour le reste de la roadmap ; le journal reste pleinement utilisable sans ça en V1.
- Notification ou résumé au CEO des nouvelles saisies (CDC 3.3) — c'est le Module 4.12 (Notifications et rappels), pas ce module-ci.
- Toute modification ou suppression d'une transaction déjà saisie — pas demandé par le CDC, et risque d'intégrité comptable ; si un besoin de correction émerge en usage réel, on le traitera comme un ajout explicite (ex. transaction d'annulation) plutôt que comme une édition silencieuse.
- Calcul d'écarts Prévu/Réel (Module 4.6) — ce module fournit la donnée réelle, pas la comparaison.
- Module 4.5 (créances clients) : la génération automatique de transaction quand une créance passe à « payé » (CDC 4.5) sera branchée au Module 4.5, pas ici — ce module-ci doit juste prévoir une structure de `transactions` compatible (ce qui est déjà le cas, aucune dépendance à ajouter maintenant).

## Livrable attendu pour revue

PR depuis `feat/module-4.4-journal-transactions` vers `main`, avec :
- Le SQL de la migration en clair dans la description (table, triggers, policies Storage).
- La preuve des six tests adversariaux ci-dessus.
- CI verte (jobs existants + nouveaux tests).
