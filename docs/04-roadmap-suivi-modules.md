# Be Smart Pilotage — Roadmap & Suivi des modules

*Version markdown du suivi.*

## Phase 0 — Fondations
- [ ] Infra multi-tenant (`entreprises`, RLS de base, fonction `current_entreprise_id()`)
- [ ] Init Supabase CLI local (`supabase init`, `supabase start` via Docker) — compte prod unique, zéro service payant
- [ ] Script de seed versionné (`supabase/seed.sql`) recréant une entreprise de test complète à chaque `db reset`
- [ ] Job CI de promotion vers prod (`supabase db push` sur merge `main`, secrets GitHub dédiés) + CI de test (stack Supabase locale éphémère dans le runner)
- [ ] Module 4.1 — Authentification et gestion des comptes (CEO, comptable, super-admin Be Smart)
- [ ] Module 4.2 — Paramétrage (catégories, modes de paiement, objectifs CA, solde initial)

## Phase 1 — Cœur du pilotage
- [ ] Module 4.3 — Budget prévisionnel mensuel
- [ ] Module 4.4 — Journal des transactions réelles (saisie comptable)
- [ ] Module 4.6 — Suivi des écarts (Prévu vs Réel)

## Phase 2 — Créances et vision consolidée
- [ ] Module 4.5 — Suivi des créances clients
- [ ] Module 4.7 — Comparaison mensuelle CA/Dépenses/Résultat net
- [ ] Module 4.8 — Synthèses mensuelle, trimestrielle, annuelle
- [ ] Module 4.9 — Cashflow prévisionnel

## Phase 3 — Tableau de bord et alertes
- [ ] Module 4.10 — Répartition des dépenses par catégorie
- [ ] Module 4.11 — Tableau de bord KPI
- [ ] Module 4.12 — Notifications et rappels

## Phase 4 — Finalisation V1
- [ ] Module 4.13 — Export et rapports (PDF, CSV/Excel)
- [ ] Couche PWA offline (Serwist, Dexie, Background Sync)
- [ ] Audit de sécurité multi-tenant complet (équivalent du 6-phase audit Air Ajjar), incluant la vérification que le pipeline local→CI→prod n'expose jamais les identifiants prod

## Hors périmètre V1 (CDC 4.14 — ne pas construire maintenant)
Facturation intégrée, API Mobile Money, comptabilité SYSCOHADA, app mobile native, dettes fournisseurs, profil Lecteur, comparaison année sur année.
