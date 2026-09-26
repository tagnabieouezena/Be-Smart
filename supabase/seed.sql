-- Jeu de données de test, rechargé à chaque `supabase db reset`.
-- Deux entreprises distinctes : sert au fonctionnement courant en local ET
-- au test d'isolation multi-tenant (supabase/tests/isolation_multi_tenant.sql).
-- Jamais exécuté en production (voir CLAUDE.md — développement 100% local).

-- =========================================================================
-- Entreprise A — « Boutique Test SARL »
-- =========================================================================

insert into public.entreprises (id, nom, secteur, devise, solde_initial, created_at)
values (
  'a0000000-0000-0000-0000-000000000001',
  'Boutique Test SARL',
  'Commerce de détail',
  'FCFA',
  500000,
  now()
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values (
  '00000000-0000-0000-0000-000000000000',
  'a1000000-0000-0000-0000-0000000000c1',
  'authenticated', 'authenticated',
  'ceo-a@test.besmart.local',
  crypt('mot-de-passe-test', gen_salt('bf')),
  now(), '{}', '{}', now(), now(), '', '', '', ''
), (
  '00000000-0000-0000-0000-000000000000',
  'a1000000-0000-0000-0000-0000000000c2',
  'authenticated', 'authenticated',
  'comptable-a@test.besmart.local',
  crypt('mot-de-passe-test', gen_salt('bf')),
  now(), '{}', '{}', now(), now(), '', '', '', ''
);

insert into public.utilisateurs (id, nom, email, role, entreprise_id, created_at)
values
  ('a1000000-0000-0000-0000-0000000000c1', 'CEO Boutique Test', 'ceo-a@test.besmart.local', 'ceo', 'a0000000-0000-0000-0000-000000000001', now()),
  ('a1000000-0000-0000-0000-0000000000c2', 'Comptable Boutique Test', 'comptable-a@test.besmart.local', 'comptable', 'a0000000-0000-0000-0000-000000000001', now());

insert into public.categories (id, entreprise_id, libelle, type)
values
  ('a2000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'Loyer', 'fixe'),
  ('a2000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Fournitures', 'variable'),
  ('a2000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'Ventes boutique', 'revenu');

insert into public.objectifs_ca (id, entreprise_id, type_periode, annee, mois, montant_cible)
values ('a3000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'mensuel', 2026, 9, 1000000);

-- Budget d'août (mois précédent) avec une charge fixe, pour tester la RPC
-- de duplication vers le budget de septembre.
insert into public.budgets_mensuels (id, entreprise_id, mois, annee, statut)
values
  ('a4000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 8, 2026, 'valide'),
  ('a4000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 9, 2026, 'brouillon');

insert into public.lignes_charge_prevue (id, budget_mensuel_id, entreprise_id, categorie_id, designation, montant, statut)
values
  ('a5000000-0000-0000-0000-000000000001', 'a4000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', 'Loyer boutique', 150000, 'realise'),
  ('a5000000-0000-0000-0000-000000000002', 'a4000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000002', 'Fournitures diverses', 20000, 'a_faire');

insert into public.lignes_revenu_prevu (id, budget_mensuel_id, entreprise_id, source, montant_estime, statut)
values ('a6000000-0000-0000-0000-000000000001', 'a4000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Ventes du mois', 800000, 'en_attente');

-- =========================================================================
-- Entreprise B — « Atelier Test SARL » (sert uniquement à prouver
-- l'isolation : ne doit jamais être visible depuis l'entreprise A)
-- =========================================================================

insert into public.entreprises (id, nom, secteur, devise, solde_initial, created_at)
values (
  'b0000000-0000-0000-0000-000000000001',
  'Atelier Test SARL',
  'Artisanat',
  'FCFA',
  250000,
  now()
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values (
  '00000000-0000-0000-0000-000000000000',
  'b1000000-0000-0000-0000-0000000000c1',
  'authenticated', 'authenticated',
  'ceo-b@test.besmart.local',
  crypt('mot-de-passe-test', gen_salt('bf')),
  now(), '{}', '{}', now(), now(), '', '', '', ''
);

insert into public.utilisateurs (id, nom, email, role, entreprise_id, created_at)
values
  ('b1000000-0000-0000-0000-0000000000c1', 'CEO Atelier Test', 'ceo-b@test.besmart.local', 'ceo', 'b0000000-0000-0000-0000-000000000001', now());

insert into public.categories (id, entreprise_id, libelle, type)
values ('b2000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'Matières premières', 'variable');

insert into public.objectifs_ca (id, entreprise_id, type_periode, annee, mois, montant_cible)
values ('b3000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'mensuel', 2026, 9, 400000);

insert into public.budgets_mensuels (id, entreprise_id, mois, annee, statut)
values ('b4000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 9, 2026, 'brouillon');

insert into public.lignes_charge_prevue (id, budget_mensuel_id, entreprise_id, categorie_id, designation, montant, statut)
values ('b5000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'Bois et tissus', 60000, 'a_faire');

insert into public.categories (id, entreprise_id, libelle, type)
values ('b2000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000001', 'Ventes atelier', 'revenu');

insert into public.lignes_revenu_prevu (id, budget_mensuel_id, entreprise_id, source, montant_estime, statut)
values ('b6000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'Commande sur mesure', 100000, 'en_attente');

-- =========================================================================
-- Transactions (Module 4.4) — une par entreprise, pour les tests
-- d'isolation. Saisies par le comptable de chaque entreprise.
-- =========================================================================

insert into public.transactions (id, entreprise_id, date, description, categorie_id, type, montant, mode_paiement, saisi_par)
values (
  'a7000000-0000-0000-0000-000000000001',
  'a0000000-0000-0000-0000-000000000001',
  '2026-09-05',
  'Vente comptoir',
  'a2000000-0000-0000-0000-000000000003',
  'entree',
  25000,
  'cash',
  'a1000000-0000-0000-0000-0000000000c2'
);

insert into public.transactions (id, entreprise_id, date, description, categorie_id, type, montant, mode_paiement, saisi_par)
values (
  'b7000000-0000-0000-0000-000000000001',
  'b0000000-0000-0000-0000-000000000001',
  '2026-09-05',
  'Vente atelier',
  'b2000000-0000-0000-0000-000000000002',
  'entree',
  15000,
  'cash',
  'b1000000-0000-0000-0000-0000000000c1'
);

-- =========================================================================
-- Compte de supervision Be Smart (super-admin, claim app_metadata.super_admin)
-- =========================================================================

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values (
  '00000000-0000-0000-0000-000000000000',
  'c0000000-0000-0000-0000-000000000001',
  'authenticated', 'authenticated',
  'supervision@besmart.local',
  crypt('mot-de-passe-test', gen_salt('bf')),
  now(), '{"super_admin": true}', '{}', now(), now(), '', '', '', ''
);

-- =========================================================================
-- Compte Auth "vierge" (aucune ligne `utilisateurs`) — sert au test
-- adversarial de la RPC creer_entreprise_et_ceo (Module 4.1) : premier
-- appel doit réussir, un deuxième appel avec ce même compte doit échouer.
-- =========================================================================

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values (
  '00000000-0000-0000-0000-000000000000',
  'd0000000-0000-0000-0000-0000000000c1',
  'authenticated', 'authenticated',
  'nouveau-ceo@test.besmart.local',
  crypt('mot-de-passe-test', gen_salt('bf')),
  now(), '{}', '{}', now(), now(), '', '', '', ''
);
