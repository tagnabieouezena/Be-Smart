-- Tests Module 4.6 — Suivi des écarts (Prévu vs Réel).
-- Voir docs/briefs/Module-4.6-Suivi-Ecarts.md, sections 3 (calculs chiffrés)
-- et 4 (adversariaux). Chaque bloc s'exécute en BEGIN … ROLLBACK : rien ne
-- persiste, et les entreprises dédiées ne perturbent ni le seed ni les
-- autres tests. Les appels se font en utilisateur authentifié réel
-- (role authenticated + sub), jamais en service_role.

set client_min_messages to notice;

-- ---------------------------------------------------------------------
-- 0. Propriétés de sécurité de la fonction, de la vue et du seuil.
-- ---------------------------------------------------------------------
begin;

do $$
declare
  v_definer boolean;
  v_config text[];
  v_options text[];
begin
  select prosecdef, proconfig into v_definer, v_config
  from pg_proc where oid = 'public.ecarts_mensuels(int, date)'::regprocedure;

  if v_definer then
    raise exception 'ecarts_mensuels ne doit jamais être security definer';
  end if;

  if not ('search_path=public' = any (coalesce(v_config, '{}'))) then
    raise exception 'ecarts_mensuels doit fixer search_path = public (config : %)', v_config;
  end if;

  select reloptions into v_options from pg_class where oid = 'public.v_budget_mensuel_totaux'::regclass;
  if not ('security_invoker=true' = any (coalesce(v_options, '{}'))) then
    raise exception 'v_budget_mensuel_totaux doit rester security_invoker (options : %)', v_options;
  end if;

  if public.seuil_ecart_significatif() <> 0.10 then
    raise exception 'seuil_ecart_significatif() devrait valoir 0.10';
  end if;

  -- Une fonction Postgres est exécutable par PUBLIC par défaut : aucune
  -- entrée PUBLIC (grantee 0) ni anon ne doit subsister sur les ACL.
  if exists (
    select 1
    from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where p.proname in ('ecarts_mensuels', 'seuil_ecart_significatif')
      and (a.grantee = 0 or a.grantee = 'anon'::regrole)
  ) then
    raise exception 'ACL : ecarts_mensuels / seuil_ecart_significatif exécutables par PUBLIC ou anon';
  end if;

  raise notice 'OK — ecarts_mensuels en security invoker + search_path fixé, vue 4.3 en security_invoker, seuil = 0.10, aucun droit PUBLIC/anon';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 1. Scénario 1 — entreprise dédiée, solde_initial 500 000,
--    ecarts_mensuels(2026, '2026-09-15') appelée en tant que son CEO.
-- ---------------------------------------------------------------------
begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values (
  '00000000-0000-0000-0000-000000000000',
  'e1000000-0000-0000-0000-0000000000c1',
  'authenticated', 'authenticated', 'ceo-e1@test.besmart.local',
  crypt('mot-de-passe-test', gen_salt('bf')),
  now(), '{}', '{}', now(), now(), '', '', '', ''
);

insert into public.entreprises (id, nom, secteur, devise, solde_initial)
values ('e0000000-0000-0000-0000-000000000001', 'Entreprise Ecarts 1', 'Test', 'FCFA', 500000);

insert into public.utilisateurs (id, nom, email, role, entreprise_id)
values ('e1000000-0000-0000-0000-0000000000c1', 'CEO E1', 'ceo-e1@test.besmart.local', 'ceo', 'e0000000-0000-0000-0000-000000000001');

insert into public.categories (id, entreprise_id, libelle, type) values
  ('e2000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001', 'Loyer', 'fixe'),
  ('e2000000-0000-0000-0000-000000000002', 'e0000000-0000-0000-0000-000000000001', 'Salaires', 'fixe'),
  ('e2000000-0000-0000-0000-000000000003', 'e0000000-0000-0000-0000-000000000001', 'Marketing', 'variable'),
  ('e2000000-0000-0000-0000-000000000004', 'e0000000-0000-0000-0000-000000000001', 'Ventes', 'revenu');

insert into public.budgets_mensuels (id, entreprise_id, mois, annee) values
  ('e4000000-0000-0000-0000-000000000007', 'e0000000-0000-0000-0000-000000000001', 7, 2026),
  ('e4000000-0000-0000-0000-000000000008', 'e0000000-0000-0000-0000-000000000001', 8, 2026),
  ('e4000000-0000-0000-0000-000000000009', 'e0000000-0000-0000-0000-000000000001', 9, 2026);

-- Juillet : loyer 100 000 + salaires 200 000 (fixes), marketing 50 000 et
-- une ligne annulée de 30 000 (variables) ; revenus 400 000 + une ligne
-- annulée de 100 000.
insert into public.lignes_charge_prevue (budget_mensuel_id, entreprise_id, categorie_id, designation, montant, statut) values
  ('e4000000-0000-0000-0000-000000000007', 'e0000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'Loyer', 100000, 'a_faire'),
  ('e4000000-0000-0000-0000-000000000007', 'e0000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000002', 'Salaires', 200000, 'a_faire'),
  ('e4000000-0000-0000-0000-000000000007', 'e0000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000003', 'Marketing', 50000, 'a_faire'),
  ('e4000000-0000-0000-0000-000000000007', 'e0000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000003', 'Campagne annulée', 30000, 'annule');

insert into public.lignes_revenu_prevu (budget_mensuel_id, entreprise_id, source, montant_estime, statut) values
  ('e4000000-0000-0000-0000-000000000007', 'e0000000-0000-0000-0000-000000000001', 'Ventes', 400000, 'en_attente'),
  ('e4000000-0000-0000-0000-000000000007', 'e0000000-0000-0000-0000-000000000001', 'Vente annulée', 100000, 'annule');

-- Août : charges fixes 300 000, revenus 250 000.
insert into public.lignes_charge_prevue (budget_mensuel_id, entreprise_id, categorie_id, designation, montant) values
  ('e4000000-0000-0000-0000-000000000008', 'e0000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000002', 'Charges fixes août', 300000);
insert into public.lignes_revenu_prevu (budget_mensuel_id, entreprise_id, source, montant_estime) values
  ('e4000000-0000-0000-0000-000000000008', 'e0000000-0000-0000-0000-000000000001', 'Ventes', 250000);

-- Septembre : fixes 300 000, variables 400 000, revenus 200 000.
insert into public.lignes_charge_prevue (budget_mensuel_id, entreprise_id, categorie_id, designation, montant) values
  ('e4000000-0000-0000-0000-000000000009', 'e0000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000002', 'Charges fixes sept.', 300000),
  ('e4000000-0000-0000-0000-000000000009', 'e0000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000003', 'Charges variables sept.', 400000);
insert into public.lignes_revenu_prevu (budget_mensuel_id, entreprise_id, source, montant_estime) values
  ('e4000000-0000-0000-0000-000000000009', 'e0000000-0000-0000-0000-000000000001', 'Ventes', 200000);

-- Transactions (saisies hors contexte JWT, saisi_par explicite).
insert into public.transactions (entreprise_id, date, description, categorie_id, type, montant, mode_paiement, saisi_par) values
  ('e0000000-0000-0000-0000-000000000001', '2026-07-05', 'Encaissement juillet', 'e2000000-0000-0000-0000-000000000004', 'entree', 300000, 'cash', 'e1000000-0000-0000-0000-0000000000c1'),
  ('e0000000-0000-0000-0000-000000000001', '2026-07-06', 'Loyer', 'e2000000-0000-0000-0000-000000000001', 'sortie', 100000, 'virement', 'e1000000-0000-0000-0000-0000000000c1'),
  ('e0000000-0000-0000-0000-000000000001', '2026-07-07', 'Salaires', 'e2000000-0000-0000-0000-000000000002', 'sortie', 200000, 'virement', 'e1000000-0000-0000-0000-0000000000c1'),
  ('e0000000-0000-0000-0000-000000000001', '2026-07-08', 'Marketing', 'e2000000-0000-0000-0000-000000000003', 'sortie', 70000, 'mobile_money', 'e1000000-0000-0000-0000-0000000000c1'),
  ('e0000000-0000-0000-0000-000000000001', '2026-08-05', 'Encaissement août', 'e2000000-0000-0000-0000-000000000004', 'entree', 250000, 'cash', 'e1000000-0000-0000-0000-0000000000c1'),
  ('e0000000-0000-0000-0000-000000000001', '2026-08-06', 'Charges août', 'e2000000-0000-0000-0000-000000000002', 'sortie', 300000, 'virement', 'e1000000-0000-0000-0000-0000000000c1'),
  ('e0000000-0000-0000-0000-000000000001', '2026-09-03', 'Achat septembre', 'e2000000-0000-0000-0000-000000000003', 'sortie', 100000, 'cash', 'e1000000-0000-0000-0000-0000000000c1');

set local role authenticated;
set local request.jwt.claims = '{"sub": "e1000000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

-- 1a. Juillet (clos) — attendus du brief.
do $$
declare
  r record;
  v_labels text[] := array[
    'revenus prévu', 'revenus réel', 'revenus écart', 'revenus écart %',
    'dépenses prévu', 'dépenses réel', 'dépenses écart', 'dépenses écart %',
    'dépenses fixes prévu', 'dépenses fixes réel', 'dépenses variables prévu', 'dépenses variables réel',
    'résultat prévu', 'résultat réel', 'résultat écart',
    'solde début', 'solde fin prévu', 'solde fin réel'
  ];
  v_attendus numeric[] := array[
    400000, 300000, -100000, -25.00,
    350000, 370000, 20000, 5.71,
    300000, 300000, 50000, 70000,
    50000, -70000, -120000,
    500000, 550000, 430000
  ];
  v_obtenus numeric[];
  i int;
begin
  select * into r from public.ecarts_mensuels(2026, '2026-09-15') f where f.mois = 7;

  v_obtenus := array[
    r.revenus_prevu, r.revenus_reel, r.revenus_ecart, r.revenus_ecart_pct,
    r.depenses_prevu, r.depenses_reel, r.depenses_ecart, r.depenses_ecart_pct,
    r.depenses_fixes_prevu, r.depenses_fixes_reel, r.depenses_variables_prevu, r.depenses_variables_reel,
    r.resultat_prevu, r.resultat_reel, r.resultat_ecart,
    r.solde_debut, r.solde_fin_prevu, r.solde_fin_reel
  ];

  for i in 1 .. array_length(v_labels, 1) loop
    if v_obtenus[i] is distinct from v_attendus[i] then
      raise exception 'JUILLET %  : attendu %, obtenu %', v_labels[i], v_attendus[i], v_obtenus[i];
    end if;
    raise notice 'JUILLET % : attendu % | obtenu %', v_labels[i], v_attendus[i], v_obtenus[i];
  end loop;

  if r.statut_mois <> 'clos' then
    raise exception 'JUILLET statut_mois : attendu clos, obtenu %', r.statut_mois;
  end if;
  if not r.alerte_revenus then
    raise exception 'JUILLET alerte_revenus : attendu true (-25 %% défavorable, mois clos)';
  end if;
  if r.alerte_depenses then
    raise exception 'JUILLET alerte_depenses : attendu false (+5,71 %% sous le seuil de 10 %%)';
  end if;
  if r.depense_non_prevue or r.alerte_solde_negatif then
    raise exception 'JUILLET : ni dépense non prévue ni alerte de solde négatif attendues';
  end if;

  raise notice 'OK — Juillet : revenus/dépenses/résultat/soldes conformes, lignes annulées exclues, alerte revenus oui, alerte dépenses non';
end $$;

-- 1b. Août (clos) — le prévu repart du réel : solde de début 430 000, pas 550 000.
do $$
declare
  r record;
  v_labels text[] := array[
    'revenus prévu', 'revenus réel', 'revenus écart', 'dépenses prévu', 'dépenses réel', 'dépenses écart',
    'résultat écart', 'solde début', 'solde fin prévu', 'solde fin réel', 'solde fin écart'
  ];
  v_attendus numeric[] := array[250000, 250000, 0, 300000, 300000, 0, 0, 430000, 380000, 380000, 0];
  v_obtenus numeric[];
  i int;
begin
  select * into r from public.ecarts_mensuels(2026, '2026-09-15') f where f.mois = 8;

  v_obtenus := array[
    r.revenus_prevu, r.revenus_reel, r.revenus_ecart, r.depenses_prevu, r.depenses_reel, r.depenses_ecart,
    r.resultat_ecart, r.solde_debut, r.solde_fin_prevu, r.solde_fin_reel, r.solde_fin_ecart
  ];

  for i in 1 .. array_length(v_labels, 1) loop
    if v_obtenus[i] is distinct from v_attendus[i] then
      raise exception 'AOUT % : attendu %, obtenu %', v_labels[i], v_attendus[i], v_obtenus[i];
    end if;
    raise notice 'AOUT % : attendu % | obtenu %', v_labels[i], v_attendus[i], v_obtenus[i];
  end loop;

  if r.alerte_revenus or r.alerte_depenses or r.depense_non_prevue or r.alerte_solde_negatif then
    raise exception 'AOUT : aucune alerte attendue';
  end if;

  raise notice 'OK — Août : solde de début 430 000 (et non 550 000), tous les écarts à 0, aucune alerte';
end $$;

-- 1c. Septembre (en cours au 15/09).
do $$
declare
  r record;
  v_labels text[] := array['solde début', 'résultat prévu', 'solde fin prévu', 'revenus réel', 'revenus prévu'];
  v_attendus numeric[] := array[380000, -500000, -120000, 0, 200000];
  v_obtenus numeric[];
  i int;
begin
  select * into r from public.ecarts_mensuels(2026, '2026-09-15') f where f.mois = 9;

  v_obtenus := array[r.solde_debut, r.resultat_prevu, r.solde_fin_prevu, r.revenus_reel, r.revenus_prevu];

  for i in 1 .. array_length(v_labels, 1) loop
    if v_obtenus[i] is distinct from v_attendus[i] then
      raise exception 'SEPTEMBRE % : attendu %, obtenu %', v_labels[i], v_attendus[i], v_obtenus[i];
    end if;
    raise notice 'SEPTEMBRE % : attendu % | obtenu %', v_labels[i], v_attendus[i], v_obtenus[i];
  end loop;

  if r.statut_mois <> 'en_cours' then
    raise exception 'SEPTEMBRE statut_mois : attendu en_cours, obtenu %', r.statut_mois;
  end if;
  if not r.alerte_solde_negatif then
    raise exception 'SEPTEMBRE alerte_solde_negatif : attendu true (solde fin prévu -120 000)';
  end if;
  if r.alerte_revenus then
    raise exception 'SEPTEMBRE alerte_revenus : attendu false (mois non clos, revenus 0 pour 200 000 prévus)';
  end if;

  raise notice 'OK — Septembre : en_cours, solde fin prévu -120 000 => alerte_solde_negatif, pas d''alerte revenus (mois non clos)';
end $$;

-- 1d. Une ligne par mois qui a un budget ou une transaction : ici 7, 8, 9 exactement.
do $$
declare
  v_mois int[];
begin
  select array_agg(f.mois order by f.mois) into v_mois from public.ecarts_mensuels(2026, '2026-09-15') f;
  if v_mois is distinct from array[7, 8, 9] then
    raise exception 'Mois renvoyés : attendu {7,8,9}, obtenu %', v_mois;
  end if;
  raise notice 'OK — seuls les mois avec budget ou transaction sont renvoyés ({7,8,9})';
end $$;

-- 1e. La vue 4.3 exclut bien les lignes annulées (une seule règle dans le produit).
do $$
declare
  r record;
begin
  select * into r from public.v_budget_mensuel_totaux
  where budget_mensuel_id = 'e4000000-0000-0000-0000-000000000007';

  if r.total_charges_fixes <> 300000 or r.total_charges_variables <> 50000 or r.total_ca_previsionnel <> 400000 then
    raise exception 'VUE 4.3 : lignes annulées non exclues (fixes %, variables %, CA %)',
      r.total_charges_fixes, r.total_charges_variables, r.total_ca_previsionnel;
  end if;

  raise notice 'OK — v_budget_mensuel_totaux exclut les lignes annulées (300 000 / 50 000 / 400 000)';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 2. Scénario 2 — autre entreprise dédiée (soldes du scénario 1 intacts) :
--    mois sans budget, et dépense non prévue.
-- ---------------------------------------------------------------------
begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values (
  '00000000-0000-0000-0000-000000000000',
  'e1000000-0000-0000-0000-0000000000d1',
  'authenticated', 'authenticated', 'ceo-e2@test.besmart.local',
  crypt('mot-de-passe-test', gen_salt('bf')),
  now(), '{}', '{}', now(), now(), '', '', '', ''
);

insert into public.entreprises (id, nom, secteur, devise, solde_initial)
values ('e0000000-0000-0000-0000-000000000002', 'Entreprise Ecarts 2', 'Test', 'FCFA', 100000);

insert into public.utilisateurs (id, nom, email, role, entreprise_id)
values ('e1000000-0000-0000-0000-0000000000d1', 'CEO E2', 'ceo-e2@test.besmart.local', 'ceo', 'e0000000-0000-0000-0000-000000000002');

insert into public.categories (id, entreprise_id, libelle, type) values
  ('e2000000-0000-0000-0000-0000000000a1', 'e0000000-0000-0000-0000-000000000002', 'Ventes', 'revenu'),
  ('e2000000-0000-0000-0000-0000000000a2', 'e0000000-0000-0000-0000-000000000002', 'Divers', 'variable');

-- Budget de juillet sans aucune ligne de charge.
insert into public.budgets_mensuels (id, entreprise_id, mois, annee)
values ('e4000000-0000-0000-0000-0000000000a7', 'e0000000-0000-0000-0000-000000000002', 7, 2026);

insert into public.transactions (entreprise_id, date, description, categorie_id, type, montant, mode_paiement, saisi_par) values
  ('e0000000-0000-0000-0000-000000000002', '2025-12-15', 'Vente décembre 2025 sans budget', 'e2000000-0000-0000-0000-0000000000a1', 'entree', 40000, 'cash', 'e1000000-0000-0000-0000-0000000000d1'),
  ('e0000000-0000-0000-0000-000000000002', '2026-06-10', 'Vente juin sans budget', 'e2000000-0000-0000-0000-0000000000a1', 'entree', 50000, 'cash', 'e1000000-0000-0000-0000-0000000000d1'),
  ('e0000000-0000-0000-0000-000000000002', '2026-07-10', 'Dépense non prévue', 'e2000000-0000-0000-0000-0000000000a2', 'sortie', 20000, 'cash', 'e1000000-0000-0000-0000-0000000000d1');

set local role authenticated;
set local request.jwt.claims = '{"sub": "e1000000-0000-0000-0000-0000000000d1", "role": "authenticated"}';

do $$
declare
  r record;
begin
  -- Juin : pas de budget.
  select * into r from public.ecarts_mensuels(2026, '2026-09-15') f where f.mois = 6;

  if r.revenus_reel is distinct from 50000 then
    raise exception 'JUIN revenus réel : attendu 50000, obtenu %', r.revenus_reel;
  end if;
  if r.revenus_prevu is not null or r.revenus_ecart is not null or r.revenus_ecart_pct is not null then
    raise exception 'JUIN : prévu et écart devraient être null (obtenu prévu %, écart %, %)', r.revenus_prevu, r.revenus_ecart, r.revenus_ecart_pct;
  end if;
  if r.a_budget or r.alerte_revenus or r.alerte_depenses or r.depense_non_prevue or r.alerte_solde_negatif then
    raise exception 'JUIN : aucune alerte et a_budget = false attendus';
  end if;
  raise notice 'JUIN : revenus réel attendu 50000 | obtenu %, prévu attendu null | obtenu %, écart attendu null | obtenu %',
    r.revenus_reel, r.revenus_prevu, r.revenus_ecart;

  -- Juillet : budget sans ligne de charge + sortie de 20 000.
  select * into r from public.ecarts_mensuels(2026, '2026-09-15') f where f.mois = 7;

  if not r.depense_non_prevue then
    raise exception 'JUILLET (scénario 2) : depense_non_prevue attendu true';
  end if;
  if r.depenses_ecart_pct is not null then
    raise exception 'JUILLET (scénario 2) : depenses_ecart_pct attendu null, obtenu %', r.depenses_ecart_pct;
  end if;
  if r.depenses_prevu is distinct from 0 or r.depenses_reel is distinct from 20000 then
    raise exception 'JUILLET (scénario 2) : dépenses prévu/réel attendus 0/20000, obtenu %/%', r.depenses_prevu, r.depenses_reel;
  end if;
  if r.alerte_depenses then
    raise exception 'JUILLET (scénario 2) : pas d''alerte de pourcentage attendue quand le prévu est 0';
  end if;
  raise notice 'JUILLET (scénario 2) : depense_non_prevue attendu true | obtenu %, écart %% attendu null | obtenu %',
    r.depense_non_prevue, r.depenses_ecart_pct;

  raise notice 'OK — mois sans budget (prévu/écart null, aucune alerte) et dépense non prévue (indicateur, écart %% null)';
end $$;

-- Historique multi-années : le solde de début cumule TOUT l'historique
-- antérieur au mois (solde_initial 100 000 + entrée de 40 000 du 15/12/2025),
-- pas seulement l'année demandée.
do $$
declare
  r record;
begin
  select * into r from public.ecarts_mensuels(2026, '2026-09-15') f where f.mois = 6;
  if r.solde_debut is distinct from 140000 then
    raise exception 'JUIN 2026 solde_debut : attendu 140000 (100000 + 40000 de décembre 2025), obtenu %', r.solde_debut;
  end if;
  raise notice 'JUIN 2026 solde_debut : attendu 140000 | obtenu %', r.solde_debut;

  select * into r from public.ecarts_mensuels(2025, '2026-09-15') f where f.mois = 12;
  if not found then
    raise exception 'DECEMBRE 2025 : ligne attendue (transaction sans budget)';
  end if;
  if r.revenus_reel is distinct from 40000 then
    raise exception 'DECEMBRE 2025 revenus réel : attendu 40000, obtenu %', r.revenus_reel;
  end if;
  if r.revenus_prevu is not null or r.revenus_ecart is not null then
    raise exception 'DECEMBRE 2025 : prévu et écart attendus null (obtenu prévu %, écart %)', r.revenus_prevu, r.revenus_ecart;
  end if;
  if r.statut_mois <> 'clos' or r.a_budget or r.alerte_revenus then
    raise exception 'DECEMBRE 2025 : clos, sans budget, sans alerte attendus';
  end if;
  if r.solde_debut is distinct from 100000 or r.solde_fin_reel is distinct from 140000 then
    raise exception 'DECEMBRE 2025 soldes : attendu début 100000 / fin réel 140000, obtenu % / %', r.solde_debut, r.solde_fin_reel;
  end if;
  raise notice 'DECEMBRE 2025 : revenus réel attendu 40000 | obtenu %, prévu attendu null | obtenu %, solde début attendu 100000 | obtenu %, solde fin réel attendu 140000 | obtenu %',
    r.revenus_reel, r.revenus_prevu, r.solde_debut, r.solde_fin_reel;

  raise notice 'OK — solde de début cumulé sur tout l''historique antérieur, toutes années confondues (juin 2026 = 140000 ; décembre 2025 : revenus 40000, prévu null)';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 3. Adversarial — le comptable de l'entreprise A appelle la fonction :
--    zéro ligne, alors que transactions et budgets lui sont lisibles.
--    (Le CEO A, lui, obtient bien des lignes : témoin positif.)
-- ---------------------------------------------------------------------
begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "a1000000-0000-0000-0000-0000000000c2", "role": "authenticated"}';

do $$
declare
  v_lignes int;
  v_transactions int;
  v_budgets int;
begin
  select count(*) into v_lignes from public.ecarts_mensuels(2026, '2026-09-15');
  select count(*) into v_transactions from public.transactions;
  select count(*) into v_budgets from public.budgets_mensuels;

  if v_transactions = 0 or v_budgets = 0 then
    raise exception 'FAUX POSITIF SUSPECT : le comptable A devrait lire transactions (%) et budgets (%) de son entreprise', v_transactions, v_budgets;
  end if;
  if v_lignes <> 0 then
    raise exception 'RESTRICTION CEO ROMPUE : le comptable A obtient % ligne(s) de ecarts_mensuels', v_lignes;
  end if;

  raise notice 'OK — comptable A : 0 ligne d''écarts alors qu''il lit % transaction(s) et % budget(s)', v_transactions, v_budgets;
end $$;

rollback;

begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "a1000000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
declare
  r record;
begin
  select * into r from public.ecarts_mensuels(2026, '2026-09-15') f where f.mois = 9;
  if not found then
    raise exception 'TÉMOIN POSITIF ABSENT : le CEO A devrait obtenir le mois de septembre';
  end if;
  if r.revenus_reel is distinct from 25000 then
    raise exception 'CEO A septembre : revenus réel attendu 25000 (transaction seed A), obtenu %', r.revenus_reel;
  end if;
  raise notice 'OK — témoin positif : le CEO A obtient ses propres écarts (septembre, revenus réel %)', r.revenus_reel;
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 4. Adversarial — le compte de supervision Be Smart : zéro ligne.
-- ---------------------------------------------------------------------
begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "c0000000-0000-0000-0000-000000000001", "role": "authenticated", "app_metadata": {"super_admin": true}}';

do $$
declare
  v_lignes int;
begin
  select count(*) into v_lignes from public.ecarts_mensuels(2026, '2026-09-15');
  if v_lignes <> 0 then
    raise exception 'ISOLATION ROMPUE : la supervision Be Smart obtient % ligne(s) de ecarts_mensuels', v_lignes;
  end if;
  raise notice 'OK — supervision Be Smart : 0 ligne';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 5. Adversarial — le CEO de l'entreprise B : aucune donnée de A ne remonte.
--    B n'a qu'un budget et une entrée de 15 000 en septembre 2026 ; A a
--    une entrée de 25 000 : le total de B doit rester 15 000.
-- ---------------------------------------------------------------------
begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "b1000000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
declare
  v_lignes int;
  v_revenus_total numeric;
  r record;
begin
  select count(*), coalesce(sum(revenus_reel), 0) into v_lignes, v_revenus_total
  from public.ecarts_mensuels(2026, '2026-09-15');

  if v_lignes <> 1 then
    raise exception 'ISOLATION ROMPUE : le CEO B obtient % ligne(s), attendu 1 (septembre)', v_lignes;
  end if;
  if v_revenus_total <> 15000 then
    raise exception 'ISOLATION ROMPUE : revenus réels du CEO B = %, attendu 15000 (aucune donnée de A)', v_revenus_total;
  end if;

  select * into r from public.ecarts_mensuels(2026, '2026-09-15');
  -- Solde de début de B = solde_initial de B (250 000), pas celui de A (500 000).
  if r.solde_debut <> 250000 then
    raise exception 'ISOLATION ROMPUE : solde de début du CEO B = %, attendu 250000', r.solde_debut;
  end if;

  raise notice 'OK — CEO B : 1 ligne, revenus réels 15000, solde de début 250000 — rien de l''entreprise A';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 6. Adversarial — un appel en anon est refusé (permission denied).
-- ---------------------------------------------------------------------
begin;

set local role anon;
set local request.jwt.claims = '{"role": "anon"}';

do $$
begin
  begin
    perform * from public.ecarts_mensuels(2026, '2026-09-15');
    raise exception 'ACCES ANON : ecarts_mensuels a pu être appelée sans authentification';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.seuil_ecart_significatif();
    raise exception 'ACCES ANON : seuil_ecart_significatif a pu être appelée sans authentification';
  exception
    when insufficient_privilege then null;
  end;

  raise notice 'OK — anon : permission denied sur ecarts_mensuels et seuil_ecart_significatif';
end $$;

rollback;
