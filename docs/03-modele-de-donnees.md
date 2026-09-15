# Be Smart Pilotage — Modèle de données (draft)

*Traduction de la section 6 du CDC en schéma Supabase. Draft de départ à valider/affiner avec Ouezz avant migration — pas encore de SQL final, volontairement, pour garder la revue explicite prévue en ways-of-working.*

## Conventions

- Toute table métier (hors tables globales de référence) porte `entreprise_id uuid not null references entreprises(id)`.
- `created_by` / `updated_by` sur les tables où la traçabilité de saisie est exigée (CDC section 3.3 : qui a saisi quoi, quand).
- RLS activé sur toutes les tables dès leur création — jamais de table métier sans politique.

## Entités principales

### `entreprises`
Nom, secteur, devise par défaut (FCFA), solde de caisse initial, date de création.
→ Accès : CEO (la sienne, lecture/écriture) ; super-admin Be Smart (toutes, **lecture seule** — décision Ouezz, voir ci-dessous).

### `utilisateurs`
Nom, email, rôle (`ceo` | `comptable`), `entreprise_id`.
→ Créé par le CEO pour les comptes comptable. Rattachement strict à une seule entreprise.

### `categories`
Libellé, type (`fixe` | `variable` | `revenu`), `entreprise_id` (personnalisable par entreprise, CDC 4.2).
→ Accès : CEO (écriture), Comptable (lecture, pour catégoriser ses saisies).

### `budgets_mensuels`
Mois, année, `entreprise_id`, statut.
→ Accès : CEO (écriture), Comptable (lecture seule, pour rapprochement CDC 4.4).

### `lignes_charge_prevue`
`budget_mensuel_id`, catégorie, désignation, montant, statut (à faire/planifié/réalisé/annulé).

### `lignes_revenu_prevu`
`budget_mensuel_id`, source, montant estimé, échéance, statut (Ok/en attente/annulé).

### `transactions`
Date, description, catégorie, type (entrée / sortie fixe / sortie variable), montant, mode de paiement, `entreprise_id`, `saisi_par` (utilisateur), justificatif (Storage), notes, lien optionnel vers une `ligne_revenu_prevu` (rapprochement).
→ Accès : Comptable (création + lecture de ses propres saisies), CEO (lecture totale).

### `creances`
Client, montant dû, date de facturation, échéance, statut (en attente / partiellement payé / payé / en retard), montant encaissé, `entreprise_id`.
→ Accès : Comptable (saisie/mise à jour), CEO (vue d'ensemble).
→ Règle métier : quand une créance passe à « payé », génération automatique d'une transaction réelle correspondante (pas de ressaisie, CDC 4.5).

### `objectifs_ca`
Mois/trimestre/année, montant cible, `entreprise_id`.
→ Accès : CEO uniquement (y compris en lecture — objectif = donnée stratégique, CDC 3.2).

## Vues / agrégats (lecture seule, réservés CEO)

- KPI dashboard (CA cumulé, dépenses cumulées, résultat net cumulé, taux de marge nette, cash disponible estimé, % réalisation CA, total créances en cours) — CDC 4.11.
- Synthèse trimestrielle/annuelle — CDC 4.8.
- Cashflow prévisionnel par trimestre — CDC 4.9.
- Comparaison mensuelle CA/dépenses/résultat net avec variation % — CDC 4.7.
- Répartition des dépenses par catégorie — CDC 4.10.

Ces vues doivent explicitement exclure le rôle `comptable` en RLS (ou au niveau de la vue elle-même) — c'est la ligne rouge de la section 3.2 du CDC : « pas d'accès… aux KPI stratégiques globaux ». Elles excluent aussi le super-admin Be Smart (voir ci-dessous) : la supervision ne donne pas accès aux montants détaillés d'une entreprise cliente.

## Rôle super-admin Be Smart — décision Ouezz

Accès de **supervision en lecture seule uniquement**, pas d'accès complet cross-tenant. Concrètement :

- Lecture autorisée : `entreprises` (métadonnées de base : nom, secteur, date de création, statut du compte), `utilisateurs` (liste et rôles, pas les données qu'ils saisissent).
- Aucune lecture des tables financières détaillées (`transactions`, `creances`, `budgets_mensuels`, `lignes_charge_prevue`, `lignes_revenu_prevu`, `objectifs_ca`) ni des vues KPI/synthèses d'une entreprise cliente.
- Aucune écriture cross-tenant : le super-admin ne modifie jamais les données d'une entreprise cliente depuis son espace de supervision.
- Objectif : permettre à Be Smart de gérer ses comptes clients (création, statut, support de premier niveau) sans avoir un accès qui exposerait les données financières de ses clients — cohérent avec le principe de sécurité incontournable du projet.

## Points à trancher avant migration

- Faut-il une table `abonnements` dès la V1 (modèle commercial, CDC section 7) ou est-ce géré hors produit dans un premier temps ?
- Format du justificatif de transaction (photo) : bucket Storage dédié par entreprise, conventions de nommage.
