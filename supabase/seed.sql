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
