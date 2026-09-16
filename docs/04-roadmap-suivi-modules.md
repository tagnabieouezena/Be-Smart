# Be Smart Pilotage — Roadmap & Suivi des modules

*Version markdown du suivi.*

## Phase 0 — Fondations ✅ mergée dans `main` (PR #1, commit `0c3c0d4`)
- [x] Infra multi-tenant (`entreprises`, `utilisateurs`, RLS, `current_entreprise_id()`, `current_role_utilisateur()`)
- [x] Init Supabase CLI local (`supabase init`, `supabase start` via Docker) — compte prod unique, zéro service payant
- [x] Script de seed versionné (`supabase/seed.sql`) — deux entreprises de test + CEO/comptable de chacune + compte supervision Be Smart
- [x] Vues de supervision Be Smart lecture seule (`v_entreprises_supervision`, `v_utilisateurs_supervision`)
- [x] Job CI de test (typecheck, lint, build, `supabase start`/`db reset`, test d'isolation adversarial) — CI verte
- [ ] Job CI de promotion vers prod (`supabase db push` sur merge `main`) — volontairement pas encore fait, à ajouter quand une première fonctionnalité réelle sera prête à être déployée

## Phase 1 — Module 4.2 en cours
- [x] Module 4.1 — Authentification et gestion des comptes (CEO, comptable, super-admin Be Smart) ✅ mergée dans `main` (PR #2, commit `6a0e26b`)
  - Dette technique mineure, non bloquante, à traiter lors d'un prochain passage sur ce module : utilisateur Auth orphelin si l'insert `utilisateurs` échoue après un `inviteUserByEmail` réussi (pas de risque RLS, juste un résidu) ; champ `nom` du comptable invité non validé/assaini (sans conséquence tant qu'il n'est qu'affiché).
- [ ] Module 4.2 — Paramétrage (catégories, modes de paiement, objectifs CA, solde initial) — brief à venir

## Phase 2 — Cœur du pilotage
- [ ] Module 4.3 — Budget prévisionnel mensuel
- [ ] Module 4.4 — Journal des transactions réelles (saisie comptable)
- [ ] Module 4.6 — Suivi des écarts (Prévu vs Réel)

## Phase 3 — Créances et vision consolidée
- [ ] Module 4.5 — Suivi des créances clients
- [ ] Module 4.7 — Comparaison mensuelle CA/Dépenses/Résultat net
- [ ] Module 4.8 — Synthèses mensuelle, trimestrielle, annuelle
- [ ] Module 4.9 — Cashflow prévisionnel

## Phase 4 — Tableau de bord et alertes
- [ ] Module 4.10 — Répartition des dépenses par catégorie
- [ ] Module 4.11 — Tableau de bord KPI
- [ ] Module 4.12 — Notifications et rappels

## Phase 5 — Finalisation V1
- [ ] Module 4.13 — Export et rapports (PDF, CSV/Excel) — bibliothèque PDF encore à trancher
- [ ] Couche PWA offline (Serwist, Dexie, Background Sync)
- [ ] Audit de sécurité multi-tenant complet (équivalent du 6-phase audit Air Ajjar), incluant la vérification que le pipeline local→CI→prod n'expose jamais les identifiants prod
- [ ] Premier job CI de promotion vers prod (`supabase db push`)

## Hors périmètre V1 (CDC 4.14 — ne pas construire maintenant)
Facturation intégrée, API Mobile Money, comptabilité SYSCOHADA, app mobile native, dettes fournisseurs, profil Lecteur, comparaison année sur année.
