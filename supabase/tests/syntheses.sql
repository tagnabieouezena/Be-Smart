-- Tests Module 4.8 — Synthèses mensuelle, trimestrielle et annuelle.
-- Voir docs/briefs/Module-4.8-Syntheses.md. Chaque scénario s'exécute en
-- BEGIN … ROLLBACK avec des entreprises dédiées : rien ne persiste. Appels en
-- utilisateur authentifié réel (role authenticated + sub), jamais en
-- service_role. Attendus chiffrés écrits en dur (jsonb : une valeur null doit
-- rester null), recalculés par un modèle de référence indépendant du SQL.

set client_min_messages to notice;

-- ---------------------------------------------------------------------
-- Aides de préparation (exécutées en tant que postgres).
-- ---------------------------------------------------------------------
create function pg_temp.idu(p_ii int, p_suffixe text) returns uuid
language sql immutable as $$
  select ('49' || lpad(p_ii::text, 2, '0') || '0000-0000-0000-0000-0000000000' || p_suffixe)::uuid;
$$;

create function pg_temp.preparer(p_ii int, p_solde numeric, p_date date) returns void
language plpgsql as $$
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, email_change,
    email_change_token_new, recovery_token
  ) values
    ('00000000-0000-0000-0000-000000000000', pg_temp.idu(p_ii, 'c1'), 'authenticated', 'authenticated',
     'ceo-49' || p_ii || '@test.besmart.local', crypt('mot-de-passe-test', gen_salt('bf')),
     now(), '{}', '{}', now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', pg_temp.idu(p_ii, 'c2'), 'authenticated', 'authenticated',
     'comptable-49' || p_ii || '@test.besmart.local', crypt('mot-de-passe-test', gen_salt('bf')),
     now(), '{}', '{}', now(), now(), '', '', '', '');

  insert into public.entreprises (id, nom, secteur, devise, solde_initial, date_solde_initial)
  values (pg_temp.idu(p_ii, '01'), 'Entreprise Synthese ' || p_ii, 'Test', 'FCFA', p_solde, p_date);

  insert into public.utilisateurs (id, nom, email, role, entreprise_id) values
    (pg_temp.idu(p_ii, 'c1'), 'CEO 49' || p_ii, 'ceo-49' || p_ii || '@test.besmart.local', 'ceo', pg_temp.idu(p_ii, '01')),
    (pg_temp.idu(p_ii, 'c2'), 'Comptable 49' || p_ii, 'comptable-49' || p_ii || '@test.besmart.local', 'comptable', pg_temp.idu(p_ii, '01'));

  insert into public.categories (id, entreprise_id, libelle, type) values
    (pg_temp.idu(p_ii, '21'), pg_temp.idu(p_ii, '01'), 'Loyer', 'fixe'),
    (pg_temp.idu(p_ii, '23'), pg_temp.idu(p_ii, '01'), 'Ventes', 'revenu');
end $$;

-- Transaction : p_nature = 'vente' (entrée) ou 'fixe' (sortie).
create function pg_temp.tx(p_ii int, p_date date, p_nature text, p_montant numeric) returns void
language plpgsql as $$
begin
  insert into public.transactions (entreprise_id, date, description, categorie_id, type, montant, mode_paiement, saisi_par)
  values (
    pg_temp.idu(p_ii, '01'), p_date, p_nature || ' ' || p_date,
    case p_nature when 'vente' then pg_temp.idu(p_ii, '23') else pg_temp.idu(p_ii, '21') end,
    case when p_nature = 'vente' then 'entree' else 'sortie' end,
    p_montant, 'cash', pg_temp.idu(p_ii, 'c1')
  );
end $$;

create function pg_temp.objectif(p_ii int, p_type text, p_annee int, p_mois int, p_trimestre int, p_cible numeric) returns void
language plpgsql as $$
begin
  insert into public.objectifs_ca (entreprise_id, type_periode, annee, mois, trimestre, montant_cible)
  values (pg_temp.idu(p_ii, '01'), p_type, p_annee, p_mois, p_trimestre, p_cible);
end $$;

-- Jeu de données Syn1 : décembre 2025, puis 2026 (CA le 10, dépenses le 12), objectifs.
create function pg_temp.jeu_syn1(p_ii int) returns void
language plpgsql as $$
declare
  ca int[] := array[200000, 100000, 0, 0, 300000, 250000, 150000, 80000, 220000, 180000, 260000, 300000];
  dep int[] := array[150000, 180000, 60000, 0, 120000, 100000, 130000, 50000, 140000, 160000, 90000, 200000];
  m int;
begin
  perform pg_temp.tx(p_ii, '2025-12-05', 'vente', 40000);
  perform pg_temp.tx(p_ii, '2025-12-06', 'fixe', 90000);
  for m in 1..12 loop
    if ca[m] > 0 then perform pg_temp.tx(p_ii, make_date(2026, m, 10), 'vente', ca[m]); end if;
    if dep[m] > 0 then perform pg_temp.tx(p_ii, make_date(2026, m, 12), 'fixe', dep[m]); end if;
  end loop;
  perform pg_temp.objectif(p_ii, 'mensuel', 2026, 1, null, 180000);
  perform pg_temp.objectif(p_ii, 'mensuel', 2026, 2, null, 150000);
  perform pg_temp.objectif(p_ii, 'mensuel', 2026, 3, null, 0);
  perform pg_temp.objectif(p_ii, 'mensuel', 2026, 4, null, 100000);
  perform pg_temp.objectif(p_ii, 'mensuel', 2026, 6, null, 250000);
  perform pg_temp.objectif(p_ii, 'trimestriel', 2026, null, 1, 400000);
  perform pg_temp.objectif(p_ii, 'trimestriel', 2026, null, 2, 500000);
  perform pg_temp.objectif(p_ii, 'trimestriel', 2026, null, 4, 800000);
  perform pg_temp.objectif(p_ii, 'annuel', 2026, null, null, 2000000);
end $$;

-- Historique du scénario 6 (solde saisi en octobre) : ordre 1 chronologique, ordre 2 identique.
create function pg_temp.historique_oct(p_ii int) returns void
language plpgsql as $$
begin
  perform pg_temp.tx(p_ii, '2026-01-10', 'vente', 300000);
  perform pg_temp.tx(p_ii, '2026-02-05', 'fixe', 120000);
  perform pg_temp.tx(p_ii, '2026-03-20', 'vente', 90000);
  perform pg_temp.tx(p_ii, '2026-05-15', 'fixe', 60000);
  perform pg_temp.tx(p_ii, '2026-07-01', 'vente', 150000);
  perform pg_temp.tx(p_ii, '2026-09-30', 'fixe', 200000);
  perform pg_temp.tx(p_ii, '2026-10-05', 'vente', 40000);
  perform pg_temp.tx(p_ii, '2026-10-13', 'vente', 25000);
  perform pg_temp.tx(p_ii, '2026-10-20', 'fixe', 70000);
end $$;

-- ---------------------------------------------------------------------
-- 0. Propriétés de sécurité de la fonction.
-- ---------------------------------------------------------------------
begin;

do $$
declare
  v_def boolean;
  v_config text[];
  v_grantees text[];
  v_nom text := 'public.syntheses_periodes(int, date)';
begin
  select prosecdef, proconfig into v_def, v_config from pg_proc where oid = v_nom::regprocedure;
  if v_def then raise exception '% ne doit jamais être security definer', v_nom; end if;
  if not ('search_path=public' = any (coalesce(v_config, '{}'))) then
    raise exception '% doit fixer search_path = public (config : %)', v_nom, v_config;
  end if;
  if (select provolatile from pg_proc where oid = v_nom::regprocedure) <> 's' then
    raise exception '% doit être stable', v_nom;
  end if;

  select array_agg(g order by g) into v_grantees
  from (
    select distinct case a.grantee when 0 then 'PUBLIC' else pg_get_userbyid(a.grantee)::text end as g
    from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where p.oid = v_nom::regprocedure and a.privilege_type = 'EXECUTE'
  ) q;
  if v_grantees is distinct from array['authenticated', 'postgres', 'service_role'] then
    raise exception 'ACL de % : droits EXECUTE = % (attendu : authenticated, postgres, service_role, jamais PUBLIC ni anon)', v_nom, v_grantees;
  end if;
  if has_function_privilege('anon', v_nom::regprocedure, 'execute') then raise exception 'ACL : anon peut exécuter %', v_nom; end if;
  if not has_function_privilege('authenticated', v_nom::regprocedure, 'execute') then raise exception 'ACL : authenticated ne peut pas exécuter %', v_nom; end if;

  -- Aucun nouvel index : ceux qui servent la fonction existent déjà.
  if not exists (select 1 from pg_class where relname = 'transactions_date_idx')
     or not exists (select 1 from pg_class where relname = 'objectifs_ca_unique_periode_idx') then
    raise exception 'index transactions_date_idx ou objectifs_ca_unique_periode_idx introuvable';
  end if;

  raise notice 'OK — syntheses_periodes en security invoker, stable, search_path fixé, ACL sans PUBLIC ni anon, authenticated autorisé ; index existants présents';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 1. Scénario 1 — année complète 2026, syntheses_periodes(2026, '2027-01-15').
--    Syn1 : solde 100 000 à la fin du 30/11/2025 ; objectifs à trois niveaux.
-- ---------------------------------------------------------------------
begin;

select pg_temp.preparer(21, 100000, '2025-11-30');
select pg_temp.jeu_syn1(21);

set local role authenticated;
set local request.jwt.claims = '{"sub": "49210000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
declare
  v_obtenu jsonb;
  v_attendu jsonb := '[{"granularite": "mois", "periode": 1, "statut": "clos", "a_activite": true, "ca": 200000, "depenses": 150000, "resultat": 50000, "objectif_ca": 180000, "statut_objectif": "defini", "taux_realisation": 111.1, "verdict_objectif": "atteint", "solde_debut": 50000, "solde_fin": 100000}, {"granularite": "mois", "periode": 2, "statut": "clos", "a_activite": true, "ca": 100000, "depenses": 180000, "resultat": -80000, "objectif_ca": 150000, "statut_objectif": "defini", "taux_realisation": 66.6, "verdict_objectif": "manque", "solde_debut": 100000, "solde_fin": 20000}, {"granularite": "mois", "periode": 3, "statut": "clos", "a_activite": true, "ca": 0, "depenses": 60000, "resultat": -60000, "objectif_ca": 0, "statut_objectif": "nul", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 20000, "solde_fin": -40000}, {"granularite": "mois", "periode": 4, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": 100000, "statut_objectif": "defini", "taux_realisation": null, "verdict_objectif": null, "solde_debut": -40000, "solde_fin": -40000}, {"granularite": "mois", "periode": 5, "statut": "clos", "a_activite": true, "ca": 300000, "depenses": 120000, "resultat": 180000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": -40000, "solde_fin": 140000}, {"granularite": "mois", "periode": 6, "statut": "clos", "a_activite": true, "ca": 250000, "depenses": 100000, "resultat": 150000, "objectif_ca": 250000, "statut_objectif": "defini", "taux_realisation": 100, "verdict_objectif": "atteint", "solde_debut": 140000, "solde_fin": 290000}, {"granularite": "mois", "periode": 7, "statut": "clos", "a_activite": true, "ca": 150000, "depenses": 130000, "resultat": 20000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 290000, "solde_fin": 310000}, {"granularite": "mois", "periode": 8, "statut": "clos", "a_activite": true, "ca": 80000, "depenses": 50000, "resultat": 30000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 310000, "solde_fin": 340000}, {"granularite": "mois", "periode": 9, "statut": "clos", "a_activite": true, "ca": 220000, "depenses": 140000, "resultat": 80000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 340000, "solde_fin": 420000}, {"granularite": "mois", "periode": 10, "statut": "clos", "a_activite": true, "ca": 180000, "depenses": 160000, "resultat": 20000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 420000, "solde_fin": 440000}, {"granularite": "mois", "periode": 11, "statut": "clos", "a_activite": true, "ca": 260000, "depenses": 90000, "resultat": 170000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 440000, "solde_fin": 610000}, {"granularite": "mois", "periode": 12, "statut": "clos", "a_activite": true, "ca": 300000, "depenses": 200000, "resultat": 100000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 610000, "solde_fin": 710000}, {"granularite": "trimestre", "periode": 1, "statut": "clos", "a_activite": true, "ca": 300000, "depenses": 390000, "resultat": -90000, "objectif_ca": 400000, "statut_objectif": "defini", "taux_realisation": 75, "verdict_objectif": "manque", "solde_debut": 50000, "solde_fin": -40000}, {"granularite": "trimestre", "periode": 2, "statut": "clos", "a_activite": true, "ca": 550000, "depenses": 220000, "resultat": 330000, "objectif_ca": 500000, "statut_objectif": "defini", "taux_realisation": 110, "verdict_objectif": "atteint", "solde_debut": -40000, "solde_fin": 290000}, {"granularite": "trimestre", "periode": 3, "statut": "clos", "a_activite": true, "ca": 450000, "depenses": 320000, "resultat": 130000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 290000, "solde_fin": 420000}, {"granularite": "trimestre", "periode": 4, "statut": "clos", "a_activite": true, "ca": 740000, "depenses": 450000, "resultat": 290000, "objectif_ca": 800000, "statut_objectif": "defini", "taux_realisation": 92.5, "verdict_objectif": "manque", "solde_debut": 420000, "solde_fin": 710000}, {"granularite": "annee", "periode": 2026, "statut": "clos", "a_activite": true, "ca": 2040000, "depenses": 1380000, "resultat": 660000, "objectif_ca": 2000000, "statut_objectif": "defini", "taux_realisation": 102, "verdict_objectif": "atteint", "solde_debut": 50000, "solde_fin": 710000}]'::jsonb;
begin
  select jsonb_agg(to_jsonb(x) order by case x.granularite when 'mois' then 1 when 'trimestre' then 2 else 3 end, x.periode)
  into v_obtenu from public.syntheses_periodes(2026, '2027-01-15') x;
  if v_obtenu is distinct from v_attendu then
    raise exception 'SCENARIO 1 : obtenu = % ; attendu = %', v_obtenu, v_attendu;
  end if;
  raise notice 'OK — scénario 1 : les 17 lignes (12 mois, 4 trimestres, année) correspondent aux attendus (objectifs atteints 111,1 / 100,0 / 110,0 / 102,0 %%, manqués 66,6 / 75,0 / 92,5 %%, objectif à 0, absent, mois vide, solde −40 000 en mars)';
end $$;

-- Cohérences : sommes, identités, continuité, égalité avec 4.7, 4.6 et solde_caisse_a.
do $$
declare
  r record;
begin
  select
    (select sum(ca) from public.syntheses_periodes(2026, '2027-01-15') where granularite = 'mois') as m_ca,
    (select sum(ca) from public.syntheses_periodes(2026, '2027-01-15') where granularite = 'trimestre') as t_ca,
    (select ca from public.syntheses_periodes(2026, '2027-01-15') where granularite = 'annee') as a_ca,
    (select sum(depenses) from public.syntheses_periodes(2026, '2027-01-15') where granularite = 'mois') as m_dep,
    (select depenses from public.syntheses_periodes(2026, '2027-01-15') where granularite = 'annee') as a_dep,
    (select ca_cumul from public.comparaison_mensuelle(2026, '2027-01-15') where mois = 12) as cumul_ca
  into r;
  if r.m_ca <> 2040000 or r.t_ca <> 2040000 or r.a_ca <> 2040000 or r.cumul_ca <> 2040000 then
    raise exception 'SOMMES CA : mois=% trimestres=% année=% ca_cumul 4.7=%', r.m_ca, r.t_ca, r.a_ca, r.cumul_ca;
  end if;
  if r.m_dep <> 1380000 or r.a_dep <> 1380000 then
    raise exception 'SOMMES DEPENSES : mois=% année=%', r.m_dep, r.a_dep;
  end if;

  -- Identité solde_fin = solde_debut + résultat sur chacune des 17 lignes.
  if exists (select 1 from public.syntheses_periodes(2026, '2027-01-15') where solde_fin <> solde_debut + resultat) then
    raise exception 'IDENTITE solde_fin = solde_debut + résultat rompue';
  end if;

  -- Continuité mois -> mois (11 paires) et trimestre -> trimestre (3 paires).
  if exists (
    select 1 from (
      select solde_fin, lead(solde_debut) over (order by periode) as suivant
      from public.syntheses_periodes(2026, '2027-01-15') where granularite = 'mois'
    ) x where suivant is not null and suivant <> solde_fin
  ) then raise exception 'CONTINUITE mois -> mois rompue'; end if;
  if exists (
    select 1 from (
      select solde_fin, lead(solde_debut) over (order by periode) as suivant
      from public.syntheses_periodes(2026, '2027-01-15') where granularite = 'trimestre'
    ) x where suivant is not null and suivant <> solde_fin
  ) then raise exception 'CONTINUITE trimestre -> trimestre rompue'; end if;
  -- L'année commence en janvier et finit en décembre, comme le premier / dernier trimestre et mois.
  if (select solde_fin from public.syntheses_periodes(2026, '2027-01-15') where granularite = 'annee')
       is distinct from (select solde_fin from public.syntheses_periodes(2026, '2027-01-15') where granularite = 'trimestre' and periode = 4)
     or (select solde_debut from public.syntheses_periodes(2026, '2027-01-15') where granularite = 'annee')
       is distinct from (select solde_debut from public.syntheses_periodes(2026, '2027-01-15') where granularite = 'mois' and periode = 1) then
    raise exception 'ANNEE : bornes de solde incohérentes avec T4 / janvier';
  end if;

  -- Réel identique à comparaison_mensuelle (4.7), mois par mois.
  if exists (
    select 1 from public.syntheses_periodes(2026, '2027-01-15') s
    join public.comparaison_mensuelle(2026, '2027-01-15') c on c.mois = s.periode
    where s.granularite = 'mois'
      and (s.ca is distinct from c.ca or s.depenses is distinct from c.depenses or s.resultat is distinct from c.resultat or s.a_activite is distinct from c.a_activite)
  ) then raise exception 'INCOHERENCE avec comparaison_mensuelle (4.7)'; end if;

  -- Soldes identiques à solde_caisse_a aux deux bornes de chaque mois.
  if exists (
    select 1 from public.syntheses_periodes(2026, '2027-01-15') s
    where s.granularite = 'mois'
      and (s.solde_debut is distinct from public.solde_caisse_a(make_date(2026, s.periode, 1) - 1)
        or s.solde_fin is distinct from public.solde_caisse_a((make_date(2026, s.periode, 1) + interval '1 month' - interval '1 day')::date))
  ) then raise exception 'INCOHERENCE avec solde_caisse_a aux bornes des mois'; end if;

  -- Soldes identiques à ecarts_mensuels (4.6) pour les mois actifs.
  if exists (
    select 1 from public.syntheses_periodes(2026, '2027-01-15') s
    join public.ecarts_mensuels(2026, '2027-01-15') e on e.mois = s.periode
    where s.granularite = 'mois' and (s.solde_debut is distinct from e.solde_debut or s.solde_fin is distinct from e.solde_fin_reel)
  ) then raise exception 'INCOHERENCE avec ecarts_mensuels (4.6)'; end if;
  if (select count(*) from public.syntheses_periodes(2026, '2027-01-15') s join public.ecarts_mensuels(2026, '2027-01-15') e on e.mois = s.periode where s.granularite = 'mois') < 11 then
    raise exception 'COMPARAISON VIDE avec ecarts_mensuels';
  end if;

  raise notice 'OK — cohérences : CA 2 040 000 = somme des mois = somme des trimestres = ca_cumul (4.7) ; dépenses 1 380 000 ; solde_fin = solde_debut + résultat sur 17 lignes ; continuité mois (11 paires) et trimestres ; égalité avec comparaison_mensuelle, solde_caisse_a aux bornes et ecarts_mensuels';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 2. Scénario 2 — année en cours « à date » : syntheses_periodes(2026, '2026-08-20').
-- ---------------------------------------------------------------------
begin;

select pg_temp.preparer(21, 100000, '2025-11-30');
select pg_temp.jeu_syn1(21);

set local role authenticated;
set local request.jwt.claims = '{"sub": "49210000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
declare
  v_obtenu jsonb;
  v_attendu jsonb := '[{"granularite": "mois", "periode": 1, "statut": "clos", "a_activite": true, "ca": 200000, "depenses": 150000, "resultat": 50000, "objectif_ca": 180000, "statut_objectif": "defini", "taux_realisation": 111.1, "verdict_objectif": "atteint", "solde_debut": 50000, "solde_fin": 100000}, {"granularite": "mois", "periode": 2, "statut": "clos", "a_activite": true, "ca": 100000, "depenses": 180000, "resultat": -80000, "objectif_ca": 150000, "statut_objectif": "defini", "taux_realisation": 66.6, "verdict_objectif": "manque", "solde_debut": 100000, "solde_fin": 20000}, {"granularite": "mois", "periode": 3, "statut": "clos", "a_activite": true, "ca": 0, "depenses": 60000, "resultat": -60000, "objectif_ca": 0, "statut_objectif": "nul", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 20000, "solde_fin": -40000}, {"granularite": "mois", "periode": 4, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": 100000, "statut_objectif": "defini", "taux_realisation": null, "verdict_objectif": null, "solde_debut": -40000, "solde_fin": -40000}, {"granularite": "mois", "periode": 5, "statut": "clos", "a_activite": true, "ca": 300000, "depenses": 120000, "resultat": 180000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": -40000, "solde_fin": 140000}, {"granularite": "mois", "periode": 6, "statut": "clos", "a_activite": true, "ca": 250000, "depenses": 100000, "resultat": 150000, "objectif_ca": 250000, "statut_objectif": "defini", "taux_realisation": 100, "verdict_objectif": "atteint", "solde_debut": 140000, "solde_fin": 290000}, {"granularite": "mois", "periode": 7, "statut": "clos", "a_activite": true, "ca": 150000, "depenses": 130000, "resultat": 20000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 290000, "solde_fin": 310000}, {"granularite": "mois", "periode": 8, "statut": "en_cours", "a_activite": true, "ca": 80000, "depenses": 50000, "resultat": 30000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 310000, "solde_fin": 340000}, {"granularite": "trimestre", "periode": 1, "statut": "clos", "a_activite": true, "ca": 300000, "depenses": 390000, "resultat": -90000, "objectif_ca": 400000, "statut_objectif": "defini", "taux_realisation": 75, "verdict_objectif": "manque", "solde_debut": 50000, "solde_fin": -40000}, {"granularite": "trimestre", "periode": 2, "statut": "clos", "a_activite": true, "ca": 550000, "depenses": 220000, "resultat": 330000, "objectif_ca": 500000, "statut_objectif": "defini", "taux_realisation": 110, "verdict_objectif": "atteint", "solde_debut": -40000, "solde_fin": 290000}, {"granularite": "trimestre", "periode": 3, "statut": "en_cours", "a_activite": true, "ca": 230000, "depenses": 180000, "resultat": 50000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 290000, "solde_fin": 340000}, {"granularite": "annee", "periode": 2026, "statut": "en_cours", "a_activite": true, "ca": 1080000, "depenses": 790000, "resultat": 290000, "objectif_ca": 2000000, "statut_objectif": "defini", "taux_realisation": 54, "verdict_objectif": "a_date", "solde_debut": 50000, "solde_fin": 340000}]'::jsonb;
begin
  select jsonb_agg(to_jsonb(x) order by case x.granularite when 'mois' then 1 when 'trimestre' then 2 else 3 end, x.periode)
  into v_obtenu from public.syntheses_periodes(2026, '2026-08-20') x;
  if v_obtenu is distinct from v_attendu then
    raise exception 'SCENARIO 2 : obtenu = % ; attendu = %', v_obtenu, v_attendu;
  end if;
  raise notice 'OK — scénario 2 (à date) : T3 et l''année en cours (1 080 000 / 790 000, taux 54,0 %% « a_date », solde de fin 340 000) ; T4 et septembre à décembre absents';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 3. Scénario 3 — continuité entre années, y compris années vides.
-- ---------------------------------------------------------------------
begin;

select pg_temp.preparer(21, 100000, '2025-11-30');
select pg_temp.jeu_syn1(21);

set local role authenticated;
set local request.jwt.claims = '{"sub": "49210000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
declare
  v jsonb;
  v_att_2025 jsonb := '[{"granularite": "mois", "periode": 1, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "mois", "periode": 2, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "mois", "periode": 3, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "mois", "periode": 4, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "mois", "periode": 5, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "mois", "periode": 6, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "mois", "periode": 7, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "mois", "periode": 8, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "mois", "periode": 9, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "mois", "periode": 10, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "mois", "periode": 11, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "mois", "periode": 12, "statut": "clos", "a_activite": true, "ca": 40000, "depenses": 90000, "resultat": -50000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 50000}, {"granularite": "trimestre", "periode": 1, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "trimestre", "periode": 2, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "trimestre", "periode": 3, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "trimestre", "periode": 4, "statut": "clos", "a_activite": true, "ca": 40000, "depenses": 90000, "resultat": -50000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 50000}, {"granularite": "annee", "periode": 2025, "statut": "clos", "a_activite": true, "ca": 40000, "depenses": 90000, "resultat": -50000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 50000}]'::jsonb;
  v_att_2027 jsonb := '[{"granularite": "mois", "periode": 1, "statut": "en_cours", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 710000, "solde_fin": 710000}, {"granularite": "trimestre", "periode": 1, "statut": "en_cours", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 710000, "solde_fin": 710000}, {"granularite": "annee", "periode": 2027, "statut": "en_cours", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 710000, "solde_fin": 710000}]'::jsonb;
  v_att_2024 jsonb := '[{"granularite": "mois", "periode": 1, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "mois", "periode": 2, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "mois", "periode": 3, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "mois", "periode": 4, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "mois", "periode": 5, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "mois", "periode": 6, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "mois", "periode": 7, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "mois", "periode": 8, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "mois", "periode": 9, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "mois", "periode": 10, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "mois", "periode": 11, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "mois", "periode": 12, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "trimestre", "periode": 1, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "trimestre", "periode": 2, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "trimestre", "periode": 3, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "trimestre", "periode": 4, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}, {"granularite": "annee", "periode": 2024, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 100000, "solde_fin": 100000}]'::jsonb;
begin
  select jsonb_agg(to_jsonb(x) order by case x.granularite when 'mois' then 1 when 'trimestre' then 2 else 3 end, x.periode) into v
  from public.syntheses_periodes(2025, '2027-01-15') x;
  if v is distinct from v_att_2025 then raise exception '2025 : obtenu = % ; attendu = %', v, v_att_2025; end if;

  select jsonb_agg(to_jsonb(x) order by case x.granularite when 'mois' then 1 when 'trimestre' then 2 else 3 end, x.periode) into v
  from public.syntheses_periodes(2027, '2027-01-15') x;
  if v is distinct from v_att_2027 then raise exception '2027 : obtenu = % ; attendu = %', v, v_att_2027; end if;

  select jsonb_agg(to_jsonb(x) order by case x.granularite when 'mois' then 1 when 'trimestre' then 2 else 3 end, x.periode) into v
  from public.syntheses_periodes(2024, '2027-01-15') x;
  if v is distinct from v_att_2024 then raise exception '2024 : obtenu = % ; attendu = %', v, v_att_2024; end if;

  if (select count(*) from public.syntheses_periodes(2028, '2027-01-15')) <> 0 then
    raise exception 'ANNEE FUTURE : des lignes ont été renvoyées';
  end if;

  -- Continuité d'une année à l'autre : fin N = début N+1 (y compris année vide).
  if (select solde_fin from public.syntheses_periodes(2024, '2027-01-15') where granularite = 'annee')
       is distinct from (select solde_debut from public.syntheses_periodes(2025, '2027-01-15') where granularite = 'annee')
     or (select solde_fin from public.syntheses_periodes(2025, '2027-01-15') where granularite = 'annee')
       is distinct from (select solde_debut from public.syntheses_periodes(2026, '2027-01-15') where granularite = 'annee')
     or (select solde_fin from public.syntheses_periodes(2026, '2027-01-15') where granularite = 'annee')
       is distinct from (select solde_debut from public.syntheses_periodes(2027, '2027-01-15') where granularite = 'annee')
     or (select solde_fin from public.syntheses_periodes(2025, '2027-01-15') where granularite = 'mois' and periode = 12) <> 50000
     or (select solde_debut from public.syntheses_periodes(2026, '2027-01-15') where granularite = 'mois' and periode = 1) <> 50000 then
    raise exception 'CONTINUITE entre années rompue';
  end if;

  raise notice 'OK — scénario 3 : 2025 (décembre seul, 100 000 → 50 000), 2027 (année sans aucune saisie, report 710 000), 2024 (année vide antérieure, 100 000 partout), 2028 (future : 0 ligne) ; continuité fin 2024 = début 2025, fin 2025 = début 2026 (50 000), fin 2026 = début 2027 (710 000)';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 4. Scénario 4 — bords de l'objectif (Syn2 : 99,9 / 100,0 / objectif à 0).
-- ---------------------------------------------------------------------
begin;

select pg_temp.preparer(22, 0, '2000-01-01');
select pg_temp.tx(22, '2026-01-10', 'vente', 999999);
select pg_temp.tx(22, '2026-02-10', 'vente', 1000000);
select pg_temp.tx(22, '2026-03-10', 'vente', 500000);
select pg_temp.objectif(22, 'mensuel', 2026, 1, null, 1000000);
select pg_temp.objectif(22, 'mensuel', 2026, 2, null, 1000000);
select pg_temp.objectif(22, 'mensuel', 2026, 3, null, 0);
select pg_temp.objectif(22, 'trimestriel', 2026, null, 1, 2499999);

set local role authenticated;
set local request.jwt.claims = '{"sub": "49220000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
declare
  v_obtenu jsonb;
  v_attendu jsonb := '[{"granularite": "mois", "periode": 1, "statut": "clos", "a_activite": true, "ca": 999999, "depenses": 0, "resultat": 999999, "objectif_ca": 1000000, "statut_objectif": "defini", "taux_realisation": 99.9, "verdict_objectif": "manque", "solde_debut": 0, "solde_fin": 999999}, {"granularite": "mois", "periode": 2, "statut": "clos", "a_activite": true, "ca": 1000000, "depenses": 0, "resultat": 1000000, "objectif_ca": 1000000, "statut_objectif": "defini", "taux_realisation": 100, "verdict_objectif": "atteint", "solde_debut": 999999, "solde_fin": 1999999}, {"granularite": "mois", "periode": 3, "statut": "clos", "a_activite": true, "ca": 500000, "depenses": 0, "resultat": 500000, "objectif_ca": 0, "statut_objectif": "nul", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 1999999, "solde_fin": 2499999}, {"granularite": "mois", "periode": 4, "statut": "en_cours", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 2499999, "solde_fin": 2499999}, {"granularite": "trimestre", "periode": 1, "statut": "clos", "a_activite": true, "ca": 2499999, "depenses": 0, "resultat": 2499999, "objectif_ca": 2499999, "statut_objectif": "defini", "taux_realisation": 100, "verdict_objectif": "atteint", "solde_debut": 0, "solde_fin": 2499999}, {"granularite": "trimestre", "periode": 2, "statut": "en_cours", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 2499999, "solde_fin": 2499999}, {"granularite": "annee", "periode": 2026, "statut": "en_cours", "a_activite": true, "ca": 2499999, "depenses": 0, "resultat": 2499999, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 0, "solde_fin": 2499999}]'::jsonb;
begin
  select jsonb_agg(to_jsonb(x) order by case x.granularite when 'mois' then 1 when 'trimestre' then 2 else 3 end, x.periode)
  into v_obtenu from public.syntheses_periodes(2026, '2026-04-15') x;
  if v_obtenu is distinct from v_attendu then
    raise exception 'SCENARIO 4 : obtenu = % ; attendu = %', v_obtenu, v_attendu;
  end if;
  raise notice 'OK — scénario 4 : 999 999 / 1 000 000 = 99,9 %% « manque » (jamais 100,0), 1 000 000 / 1 000 000 = 100,0 %% « atteint », T1 2 499 999 / 2 499 999 = 100,0 %% atteint, objectif à 0 sans taux ni erreur';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 5. Scénario 5 — entreprise sans transaction ni objectif (Syn3).
-- ---------------------------------------------------------------------
begin;

select pg_temp.preparer(23, 250000, '2025-12-31');

set local role authenticated;
set local request.jwt.claims = '{"sub": "49230000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
declare
  v_obtenu jsonb;
  v_attendu jsonb := '[{"granularite": "mois", "periode": 1, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 250000, "solde_fin": 250000}, {"granularite": "mois", "periode": 2, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 250000, "solde_fin": 250000}, {"granularite": "mois", "periode": 3, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 250000, "solde_fin": 250000}, {"granularite": "mois", "periode": 4, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 250000, "solde_fin": 250000}, {"granularite": "mois", "periode": 5, "statut": "en_cours", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 250000, "solde_fin": 250000}, {"granularite": "trimestre", "periode": 1, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 250000, "solde_fin": 250000}, {"granularite": "trimestre", "periode": 2, "statut": "en_cours", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 250000, "solde_fin": 250000}, {"granularite": "annee", "periode": 2026, "statut": "en_cours", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 250000, "solde_fin": 250000}]'::jsonb;
begin
  select jsonb_agg(to_jsonb(x) order by case x.granularite when 'mois' then 1 when 'trimestre' then 2 else 3 end, x.periode)
  into v_obtenu from public.syntheses_periodes(2026, '2026-05-20') x;
  if v_obtenu is distinct from v_attendu then
    raise exception 'SCENARIO 5 : obtenu = % ; attendu = %', v_obtenu, v_attendu;
  end if;
  raise notice 'OK — scénario 5 : entreprise sans donnée, 8 lignes à 0, objectifs absents, taux null, solde 250 000 → 250 000 partout, aucune erreur';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 6. Scénario 6 — solde saisi en octobre, historique de janvier à septembre.
--    Deux ordres de saisie : (1) solde puis transactions ; (2) transactions
--    puis solde. Mêmes sorties, égales aux attendus.
-- ---------------------------------------------------------------------
begin;

select pg_temp.preparer(24, 800000, '2026-10-13');
select pg_temp.historique_oct(24);
select pg_temp.preparer(25, 0, '2000-01-01');
select pg_temp.historique_oct(25);
update public.entreprises set solde_initial = 800000, date_solde_initial = '2026-10-13' where id = pg_temp.idu(25, '01');

set local role authenticated;

do $$
declare
  v_ii int;
  v_obtenu jsonb;
  v_attendu jsonb := '[{"granularite": "mois", "periode": 1, "statut": "clos", "a_activite": true, "ca": 300000, "depenses": 0, "resultat": 300000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 575000, "solde_fin": 875000}, {"granularite": "mois", "periode": 2, "statut": "clos", "a_activite": true, "ca": 0, "depenses": 120000, "resultat": -120000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 875000, "solde_fin": 755000}, {"granularite": "mois", "periode": 3, "statut": "clos", "a_activite": true, "ca": 90000, "depenses": 0, "resultat": 90000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 755000, "solde_fin": 845000}, {"granularite": "mois", "periode": 4, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 845000, "solde_fin": 845000}, {"granularite": "mois", "periode": 5, "statut": "clos", "a_activite": true, "ca": 0, "depenses": 60000, "resultat": -60000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 845000, "solde_fin": 785000}, {"granularite": "mois", "periode": 6, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 785000, "solde_fin": 785000}, {"granularite": "mois", "periode": 7, "statut": "clos", "a_activite": true, "ca": 150000, "depenses": 0, "resultat": 150000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 785000, "solde_fin": 935000}, {"granularite": "mois", "periode": 8, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 935000, "solde_fin": 935000}, {"granularite": "mois", "periode": 9, "statut": "clos", "a_activite": true, "ca": 0, "depenses": 200000, "resultat": -200000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 935000, "solde_fin": 735000}, {"granularite": "mois", "periode": 10, "statut": "en_cours", "a_activite": true, "ca": 65000, "depenses": 70000, "resultat": -5000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 735000, "solde_fin": 730000}, {"granularite": "trimestre", "periode": 1, "statut": "clos", "a_activite": true, "ca": 390000, "depenses": 120000, "resultat": 270000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 575000, "solde_fin": 845000}, {"granularite": "trimestre", "periode": 2, "statut": "clos", "a_activite": true, "ca": 0, "depenses": 60000, "resultat": -60000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 845000, "solde_fin": 785000}, {"granularite": "trimestre", "periode": 3, "statut": "clos", "a_activite": true, "ca": 150000, "depenses": 200000, "resultat": -50000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 785000, "solde_fin": 735000}, {"granularite": "trimestre", "periode": 4, "statut": "en_cours", "a_activite": true, "ca": 65000, "depenses": 70000, "resultat": -5000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 735000, "solde_fin": 730000}, {"granularite": "annee", "periode": 2026, "statut": "en_cours", "a_activite": true, "ca": 605000, "depenses": 450000, "resultat": 155000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 575000, "solde_fin": 730000}]'::jsonb;
begin
  foreach v_ii in array array[24, 25] loop
    perform set_config('request.jwt.claims',
      format('{"sub": "49%s0000-0000-0000-0000-0000000000c1", "role": "authenticated"}', lpad(v_ii::text, 2, '0')), true);

    select jsonb_agg(to_jsonb(x) order by case x.granularite when 'mois' then 1 when 'trimestre' then 2 else 3 end, x.periode)
    into v_obtenu from public.syntheses_periodes(2026, '2026-10-20') x;
    if v_obtenu is distinct from v_attendu then
      raise exception 'SCENARIO 6 (ordre %) : obtenu = % ; attendu = %', v_ii - 23, v_obtenu, v_attendu;
    end if;

    -- Octobre contient la date du solde ; ouverture 575 000 ; fin 730 000.
    if (select solde_debut from public.syntheses_periodes(2026, '2026-10-20') where granularite = 'annee') <> 575000
       or (select solde_fin from public.syntheses_periodes(2026, '2026-10-20') where granularite = 'annee') <> 730000
       or (select solde_debut from public.syntheses_periodes(2026, '2026-10-20') where granularite = 'mois' and periode = 10) <> 735000 then
      raise exception 'SCENARIO 6 (ordre %) : soldes d''ouverture, de début d''octobre ou de fin incorrects', v_ii - 23;
    end if;

    -- Égalité avec ecarts_mensuels pour les mois actifs et avec solde_caisse_a aux bornes.
    if exists (
      select 1 from public.syntheses_periodes(2026, '2026-10-20') s
      join public.ecarts_mensuels(2026, '2026-10-20') e on e.mois = s.periode
      where s.granularite = 'mois' and (s.solde_debut is distinct from e.solde_debut or s.solde_fin is distinct from e.solde_fin_reel)
    ) or exists (
      select 1 from public.syntheses_periodes(2026, '2026-10-20') s
      where s.granularite = 'mois'
        and (s.solde_debut is distinct from public.solde_caisse_a(make_date(2026, s.periode, 1) - 1)
          or s.solde_fin is distinct from public.solde_caisse_a((make_date(2026, s.periode, 1) + interval '1 month' - interval '1 day')::date))
    ) then
      raise exception 'SCENARIO 6 (ordre %) : incohérence avec ecarts_mensuels ou solde_caisse_a', v_ii - 23;
    end if;
  end loop;

  raise notice 'OK — scénario 6 : solde de 800 000 saisi le 13 octobre, historique de janvier à septembre : ouverture 575 000, octobre 735 000 → 730 000, année 575 000 → 730 000 (605 000 / 450 000 / 155 000), mêmes sorties pour les deux ordres de saisie, égales à ecarts_mensuels et à solde_caisse_a';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 7. Adversariaux : comptable, supervision, isolation A / B (objectifs
--    différents), anon.
--    A : objectif de janvier 180 000, CA 200 000 ; B : objectif 777 000, CA 300 000.
-- ---------------------------------------------------------------------
begin;

select pg_temp.preparer(26, 0, '2000-01-01');
select pg_temp.tx(26, '2026-01-10', 'vente', 200000);
select pg_temp.objectif(26, 'mensuel', 2026, 1, null, 180000);
select pg_temp.preparer(27, 0, '2000-01-01');
select pg_temp.tx(27, '2026-01-10', 'vente', 300000);
select pg_temp.objectif(27, 'mensuel', 2026, 1, null, 777000);

-- 7.1 Le comptable de A : zéro ligne (il lit pourtant les transactions) ; objectifs illisibles.
set local role authenticated;
set local request.jwt.claims = '{"sub": "49260000-0000-0000-0000-0000000000c2", "role": "authenticated"}';

do $$
begin
  if (select count(*) from public.transactions) = 0 then
    raise exception 'TEMOIN : le comptable devrait lire les transactions de son entreprise';
  end if;
  if (select count(*) from public.syntheses_periodes(2026, '2026-03-10')) <> 0 then
    raise exception 'COMPTABLE : syntheses_periodes a renvoyé des lignes';
  end if;
  if (select count(*) from public.objectifs_ca) <> 0 then
    raise exception 'COMPTABLE : objectifs_ca lisible';
  end if;
  raise notice 'OK — comptable : zéro ligne de synthèse (ses transactions restent lisibles), objectifs_ca illisible (zéro ligne)';
end $$;

-- 7.2 Supervision : zéro ligne.
set local request.jwt.claims = '{"sub": "c0000000-0000-0000-0000-000000000001", "role": "authenticated", "app_metadata": {"super_admin": true}}';

do $$
begin
  if (select count(*) from public.syntheses_periodes(2026, '2026-03-10')) <> 0 then
    raise exception 'SUPERVISION : syntheses_periodes a renvoyé des lignes';
  end if;
  raise notice 'OK — supervision Be Smart : zéro ligne de synthèse';
end $$;

-- 7.3 Isolation A / B : chacun ne voit que ses chiffres, ses objectifs et ses soldes.
set local request.jwt.claims = '{"sub": "49260000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
declare
  v_obtenu jsonb;
  v_attendu jsonb := '[{"granularite": "mois", "periode": 1, "statut": "clos", "a_activite": true, "ca": 200000, "depenses": 0, "resultat": 200000, "objectif_ca": 180000, "statut_objectif": "defini", "taux_realisation": 111.1, "verdict_objectif": "atteint", "solde_debut": 0, "solde_fin": 200000}, {"granularite": "mois", "periode": 2, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 200000, "solde_fin": 200000}, {"granularite": "mois", "periode": 3, "statut": "en_cours", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 200000, "solde_fin": 200000}, {"granularite": "trimestre", "periode": 1, "statut": "en_cours", "a_activite": true, "ca": 200000, "depenses": 0, "resultat": 200000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 0, "solde_fin": 200000}, {"granularite": "annee", "periode": 2026, "statut": "en_cours", "a_activite": true, "ca": 200000, "depenses": 0, "resultat": 200000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 0, "solde_fin": 200000}]'::jsonb;
begin
  select jsonb_agg(to_jsonb(x) order by case x.granularite when 'mois' then 1 when 'trimestre' then 2 else 3 end, x.periode)
  into v_obtenu from public.syntheses_periodes(2026, '2026-03-10') x;
  if v_obtenu is distinct from v_attendu then raise exception 'CEO A : obtenu = % ; attendu = %', v_obtenu, v_attendu; end if;
  raise notice 'OK — CEO de A : janvier 200 000 contre un objectif de 180 000 = 111,1 %%, rien de B';
end $$;

set local request.jwt.claims = '{"sub": "49270000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
declare
  v_obtenu jsonb;
  v_attendu jsonb := '[{"granularite": "mois", "periode": 1, "statut": "clos", "a_activite": true, "ca": 300000, "depenses": 0, "resultat": 300000, "objectif_ca": 777000, "statut_objectif": "defini", "taux_realisation": 38.6, "verdict_objectif": "manque", "solde_debut": 0, "solde_fin": 300000}, {"granularite": "mois", "periode": 2, "statut": "clos", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 300000, "solde_fin": 300000}, {"granularite": "mois", "periode": 3, "statut": "en_cours", "a_activite": false, "ca": 0, "depenses": 0, "resultat": 0, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 300000, "solde_fin": 300000}, {"granularite": "trimestre", "periode": 1, "statut": "en_cours", "a_activite": true, "ca": 300000, "depenses": 0, "resultat": 300000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 0, "solde_fin": 300000}, {"granularite": "annee", "periode": 2026, "statut": "en_cours", "a_activite": true, "ca": 300000, "depenses": 0, "resultat": 300000, "objectif_ca": null, "statut_objectif": "absent", "taux_realisation": null, "verdict_objectif": null, "solde_debut": 0, "solde_fin": 300000}]'::jsonb;
begin
  select jsonb_agg(to_jsonb(x) order by case x.granularite when 'mois' then 1 when 'trimestre' then 2 else 3 end, x.periode)
  into v_obtenu from public.syntheses_periodes(2026, '2026-03-10') x;
  if v_obtenu is distinct from v_attendu then raise exception 'CEO B : obtenu = % ; attendu = %', v_obtenu, v_attendu; end if;
  raise notice 'OK — CEO de B : janvier 300 000 contre un objectif de 777 000 = 38,6 %%, rien de A';
end $$;

-- 7.4 anon : appel refusé.
reset role;
set local role anon;

do $$
begin
  begin
    perform * from public.syntheses_periodes(2026, '2026-03-10');
    raise exception 'ANON : syntheses_periodes a été exécutée';
  exception when insufficient_privilege then
    null;
  end;
  raise notice 'OK — anon : permission refusée sur syntheses_periodes';
end $$;

rollback;
