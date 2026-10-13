-- Tests Module 4.7 — Comparaison mensuelle CA encaissé / Dépenses / Résultat net.
-- Voir docs/briefs/Module-4.7-Comparaison-Mensuelle.md, sections 5 (jeu de test
-- chiffré) et 6 (adversariaux). Chaque scénario s'exécute en BEGIN … ROLLBACK :
-- rien ne persiste, et les entreprises dédiées ne perturbent ni le seed ni les
-- autres tests. Les appels se font en utilisateur authentifié réel
-- (role authenticated + sub), jamais en service_role.
--
-- Les résultats sont comparés à des attendus chiffrés écrits en dur (jsonb) :
-- les nombres jsonb se comparent par valeur (100 = 100.00), les null restent
-- des null (aucune variation ne doit être 0 par défaut).

set client_min_messages to notice;

-- ---------------------------------------------------------------------
-- Aides de préparation (exécutées en tant que postgres, avant tout
-- « set role ») : identifiants déterministes et insertion des transactions.
-- ---------------------------------------------------------------------
create function pg_temp.idu(p_ii int, p_suffixe text) returns uuid
language sql immutable as $$
  select ('47' || lpad(p_ii::text, 2, '0') || '0000-0000-0000-0000-0000000000' || p_suffixe)::uuid;
$$;

-- Entreprise dédiée : un CEO (c1), un comptable (c2), trois catégories
-- (21 fixe, 22 variable, 23 revenu).
create function pg_temp.preparer(p_ii int) returns void
language plpgsql as $$
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, email_change,
    email_change_token_new, recovery_token
  ) values
    ('00000000-0000-0000-0000-000000000000', pg_temp.idu(p_ii, 'c1'), 'authenticated', 'authenticated',
     'ceo-47' || p_ii || '@test.besmart.local', crypt('mot-de-passe-test', gen_salt('bf')),
     now(), '{}', '{}', now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', pg_temp.idu(p_ii, 'c2'), 'authenticated', 'authenticated',
     'comptable-47' || p_ii || '@test.besmart.local', crypt('mot-de-passe-test', gen_salt('bf')),
     now(), '{}', '{}', now(), now(), '', '', '', '');

  insert into public.entreprises (id, nom, secteur, devise, solde_initial)
  values (pg_temp.idu(p_ii, '01'), 'Entreprise Comparaison ' || p_ii, 'Test', 'FCFA', 0);

  insert into public.utilisateurs (id, nom, email, role, entreprise_id) values
    (pg_temp.idu(p_ii, 'c1'), 'CEO 47' || p_ii, 'ceo-47' || p_ii || '@test.besmart.local', 'ceo', pg_temp.idu(p_ii, '01')),
    (pg_temp.idu(p_ii, 'c2'), 'Comptable 47' || p_ii, 'comptable-47' || p_ii || '@test.besmart.local', 'comptable', pg_temp.idu(p_ii, '01'));

  insert into public.categories (id, entreprise_id, libelle, type) values
    (pg_temp.idu(p_ii, '21'), pg_temp.idu(p_ii, '01'), 'Loyer', 'fixe'),
    (pg_temp.idu(p_ii, '22'), pg_temp.idu(p_ii, '01'), 'Marketing', 'variable'),
    (pg_temp.idu(p_ii, '23'), pg_temp.idu(p_ii, '01'), 'Ventes', 'revenu');
end $$;

-- Transaction : p_nature = 'vente' (entrée), 'fixe' ou 'variable' (sorties).
create function pg_temp.tx(p_ii int, p_date date, p_nature text, p_montant numeric) returns void
language plpgsql as $$
begin
  insert into public.transactions (entreprise_id, date, description, categorie_id, type, montant, mode_paiement, saisi_par)
  values (
    pg_temp.idu(p_ii, '01'), p_date, p_nature || ' ' || p_date,
    case p_nature when 'vente' then pg_temp.idu(p_ii, '23') when 'fixe' then pg_temp.idu(p_ii, '21') else pg_temp.idu(p_ii, '22') end,
    case when p_nature = 'vente' then 'entree' else 'sortie' end,
    p_montant, 'cash', pg_temp.idu(p_ii, 'c1')
  );
end $$;

-- ---------------------------------------------------------------------
-- 0. Propriétés de sécurité des trois fonctions.
-- ---------------------------------------------------------------------
begin;

do $$
declare
  v_nom text;
  v_def boolean;
  v_config text[];
  v_volatilite "char";
  v_grantees text[];
begin
  foreach v_nom in array array[
    'public.variation_mensuelle(numeric, numeric, boolean, boolean)',
    'public.comparaison_mensuelle(int, date)',
    'public.comparaison_accueil(date)'
  ] loop
    select prosecdef, proconfig, provolatile into v_def, v_config, v_volatilite
    from pg_proc where oid = v_nom::regprocedure;

    if v_def then
      raise exception '% ne doit jamais être security definer', v_nom;
    end if;
    if not ('search_path=public' = any (coalesce(v_config, '{}'))) then
      raise exception '% doit fixer search_path = public (config : %)', v_nom, v_config;
    end if;

    -- ACL : jamais PUBLIC ni anon ; authenticated peut exécuter ; le reste de
    -- l'ACL est celui des fonctions du produit (propriétaire postgres et rôle
    -- service_role, accordé par les privilèges par défaut de Supabase).
    select array_agg(g order by g) into v_grantees
    from (
      select distinct case a.grantee when 0 then 'PUBLIC' else pg_get_userbyid(a.grantee)::text end as g
      from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      where p.oid = v_nom::regprocedure and a.privilege_type = 'EXECUTE'
    ) q;

    if v_grantees is distinct from array['authenticated', 'postgres', 'service_role'] then
      raise exception 'ACL de % : droits EXECUTE = % (attendu : authenticated, postgres, service_role, jamais PUBLIC ni anon)', v_nom, v_grantees;
    end if;
    if has_function_privilege('anon', v_nom::regprocedure, 'execute') then
      raise exception 'ACL : anon peut exécuter %', v_nom;
    end if;
    if not has_function_privilege('authenticated', v_nom::regprocedure, 'execute') then
      raise exception 'ACL : authenticated ne peut pas exécuter %', v_nom;
    end if;
  end loop;

  if (select provolatile from pg_proc where oid = 'public.variation_mensuelle(numeric, numeric, boolean, boolean)'::regprocedure) <> 'i' then
    raise exception 'variation_mensuelle doit être immutable (fonction pure)';
  end if;
  if not exists (select 1 from pg_class c where c.relname = 'transactions_date_idx') then
    raise exception 'index transactions (entreprise_id, date) introuvable';
  end if;

  raise notice 'OK — 3 fonctions en security invoker, search_path fixé, variation_mensuelle immutable, ACL : ni PUBLIC ni anon, authenticated autorisé ; index transactions_date_idx présent';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 0 bis. variation_mensuelle (fonction pure) : règles 2, 3 et 4 isolées.
-- ---------------------------------------------------------------------
begin;

do $$
declare
  r record;
begin
  -- règle 4 : cas général (20 000 / 60 000 = 33,33 %).
  select * into r from public.variation_mensuelle(80000, 60000, true, true);
  if r.variation <> 20000 or r.variation_pct <> 33.33 then
    raise exception 'REGLE 4 : variation=% pct=% (attendu 20000 / 33.33)', r.variation, r.variation_pct;
  end if;
  -- baisse : le pourcentage est négatif.
  select * into r from public.variation_mensuelle(0, 300000, true, true);
  if r.variation <> -300000 or r.variation_pct <> -100.00 then
    raise exception 'BAISSE : variation=% pct=%', r.variation, r.variation_pct;
  end if;
  -- règle 3 : précédent à 0 avec activité : FCFA calculé, % null.
  select * into r from public.variation_mensuelle(90000, 0, true, true);
  if r.variation <> 90000 or r.variation_pct is not null then
    raise exception 'REGLE 3 : variation=% pct=% (attendu 90000 / null)', r.variation, r.variation_pct;
  end if;
  -- règle 2, côté mois courant sans activité.
  select * into r from public.variation_mensuelle(0, 200000, false, true);
  if r.variation is not null or r.variation_pct is not null then
    raise exception 'REGLE 2 (courant vide) : variation=% pct=%', r.variation, r.variation_pct;
  end if;
  -- règle 2, côté mois précédent sans activité.
  select * into r from public.variation_mensuelle(300000, 0, true, false);
  if r.variation is not null or r.variation_pct is not null then
    raise exception 'REGLE 2 (précédent vide) : variation=% pct=%', r.variation, r.variation_pct;
  end if;
  -- règle 1 : pas de mois précédent (a_precedent null) : tout est null.
  select * into r from public.variation_mensuelle(200000, null, true, null);
  if r.variation is not null or r.variation_pct is not null then
    raise exception 'REGLE 1 (aucun mois précédent) : variation=% pct=%', r.variation, r.variation_pct;
  end if;
  -- précédent négatif (résultat) : pas de pourcentage.
  select * into r from public.variation_mensuelle(10000, -60000, true, true);
  if r.variation <> 70000 or r.variation_pct is not null then
    raise exception 'PRECEDENT NEGATIF : variation=% pct=%', r.variation, r.variation_pct;
  end if;

  raise notice 'OK — variation_mensuelle : règles 1 à 4 (+33,33 / −100,00 / %% null si précédent à 0 / null si un mois est vide)';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 1. Scénario des cinq mois (brief §5) — comparaison_mensuelle(2026,
--    '2026-05-20') en tant que CEO d'une entreprise dédiée.
--    Janvier 200 000 / 100 000 fixe + 50 000 variable ;
--    février : aucune transaction (une créance Alpha de 100 000 existe) ;
--    mars : vente 200 000 + paiement de la créance Alpha 100 000 (UNE seule
--    transaction liée), fixe 80 000, variable 40 000 ;
--    avril : sortie 60 000 ; mai : entrée 90 000, sortie 80 000.
-- ---------------------------------------------------------------------
begin;

select pg_temp.preparer(1);
select pg_temp.tx(1, '2026-01-10', 'vente', 200000);
select pg_temp.tx(1, '2026-01-12', 'fixe', 100000);
select pg_temp.tx(1, '2026-01-15', 'variable', 50000);
select pg_temp.tx(1, '2026-03-05', 'vente', 200000);
select pg_temp.tx(1, '2026-03-06', 'fixe', 80000);
select pg_temp.tx(1, '2026-03-07', 'variable', 40000);
select pg_temp.tx(1, '2026-04-08', 'fixe', 60000);
select pg_temp.tx(1, '2026-05-04', 'vente', 90000);
select pg_temp.tx(1, '2026-05-06', 'variable', 80000);

-- Créance Alpha : facturée en février, échéance fin mars. Son paiement est une
-- transaction d'entrée liée ; la créance elle-même n'est jamais comptée.
insert into public.creances (id, entreprise_id, client, montant_du, date_facturation, echeance, saisi_par)
values (pg_temp.idu(1, 'a1'), pg_temp.idu(1, '01'), 'Alpha', 100000, '2026-02-05', '2026-03-31', pg_temp.idu(1, 'c1'));
insert into public.transactions (entreprise_id, date, description, categorie_id, type, montant, mode_paiement, saisi_par, creance_id)
values (pg_temp.idu(1, '01'), '2026-03-10', 'Paiement Alpha', pg_temp.idu(1, '23'), 'entree', 100000, 'virement', pg_temp.idu(1, 'c1'), pg_temp.idu(1, 'a1'));

set local role authenticated;
set local request.jwt.claims = '{"sub": "47010000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
declare
  v_obtenu jsonb;
  v_attendu jsonb := '[
    {"mois":1,"statut_mois":"clos","a_activite":true,"ca":200000,"depenses":150000,"resultat":50000,
     "ca_variation":null,"ca_variation_pct":null,"depenses_variation":null,"depenses_variation_pct":null,"resultat_variation":null,
     "ca_cumul":200000,"depenses_cumul":150000,"resultat_cumul":50000},
    {"mois":2,"statut_mois":"clos","a_activite":false,"ca":0,"depenses":0,"resultat":0,
     "ca_variation":null,"ca_variation_pct":null,"depenses_variation":null,"depenses_variation_pct":null,"resultat_variation":null,
     "ca_cumul":200000,"depenses_cumul":150000,"resultat_cumul":50000},
    {"mois":3,"statut_mois":"clos","a_activite":true,"ca":300000,"depenses":120000,"resultat":180000,
     "ca_variation":null,"ca_variation_pct":null,"depenses_variation":null,"depenses_variation_pct":null,"resultat_variation":null,
     "ca_cumul":500000,"depenses_cumul":270000,"resultat_cumul":230000},
    {"mois":4,"statut_mois":"clos","a_activite":true,"ca":0,"depenses":60000,"resultat":-60000,
     "ca_variation":-300000,"ca_variation_pct":-100.00,"depenses_variation":-60000,"depenses_variation_pct":-50.00,"resultat_variation":-240000,
     "ca_cumul":500000,"depenses_cumul":330000,"resultat_cumul":170000},
    {"mois":5,"statut_mois":"en_cours","a_activite":true,"ca":90000,"depenses":80000,"resultat":10000,
     "ca_variation":90000,"ca_variation_pct":null,"depenses_variation":20000,"depenses_variation_pct":33.33,"resultat_variation":70000,
     "ca_cumul":590000,"depenses_cumul":410000,"resultat_cumul":180000}
  ]'::jsonb;
begin
  select jsonb_agg(to_jsonb(x) order by x.mois) into v_obtenu
  from public.comparaison_mensuelle(2026, '2026-05-20') x;

  if v_obtenu is distinct from v_attendu then
    raise exception 'CINQ MOIS : obtenu = % ; attendu = %', v_obtenu, v_attendu;
  end if;

  raise notice 'OK — cinq mois : les 5 lignes (montants, variations, %% null/arrondis, cumuls, statuts) correspondent aux attendus du brief';
end $$;

-- Totaux exacts (numeric) : 590 000 / 410 000 / 180 000 ; résultat = CA − dépenses.
do $$
declare
  r record;
begin
  select sum(ca) as ca, sum(depenses) as dep, sum(resultat) as res into r
  from public.comparaison_mensuelle(2026, '2026-05-20');
  if r.ca <> 590000 or r.dep <> 410000 or r.res <> 180000 or r.res <> r.ca - r.dep then
    raise exception 'TOTAUX : ca=% dep=% res=%', r.ca, r.dep, r.res;
  end if;
  -- la dernière ligne porte le « Total année à date ».
  select ca_cumul, depenses_cumul, resultat_cumul into r
  from public.comparaison_mensuelle(2026, '2026-05-20') order by mois desc limit 1;
  if r.ca_cumul <> 590000 or r.depenses_cumul <> 410000 or r.resultat_cumul <> 180000 then
    raise exception 'TOTAL ANNEE A DATE : % / % / %', r.ca_cumul, r.depenses_cumul, r.resultat_cumul;
  end if;
  raise notice 'OK — totaux 590 000 / 410 000 / 180 000 (= 590 000 − 410 000) ; la dernière ligne porte les cumuls';
end $$;

-- Pas de double comptage : une seule transaction liée à la créance ; le CA de
-- février vaut 0 alors que la créance existe.
do $$
begin
  if (select count(*) from public.transactions where creance_id is not null) <> 1 then
    raise exception 'DOUBLE COMPTAGE : plus d''une transaction liée à la créance';
  end if;
  if (select ca from public.comparaison_mensuelle(2026, '2026-05-20') where mois = 2) <> 0 then
    raise exception 'CREANCE COMPTEE A SA FACTURATION : le CA de février n''est pas nul';
  end if;
  raise notice 'OK — créance payée : une seule transaction, CA de février = 0 (créance non comptée à la facturation), CA de mars = 300 000 (200 000 + paiement 100 000)';
end $$;

-- Cohérence avec le Module 4.6 : mêmes montants que ecarts_mensuels.
do $$
declare
  v_ecart int;
begin
  select count(*) into v_ecart
  from public.comparaison_mensuelle(2026, '2026-05-20') c
  join public.ecarts_mensuels(2026, '2026-05-20') e on e.mois = c.mois
  where c.ca is distinct from e.revenus_reel
     or c.depenses is distinct from e.depenses_reel
     or c.resultat is distinct from e.resultat_reel;
  if v_ecart <> 0 then
    raise exception 'INCOHERENCE avec ecarts_mensuels sur % mois', v_ecart;
  end if;
  if (select count(*) from public.comparaison_mensuelle(2026, '2026-05-20') c join public.ecarts_mensuels(2026, '2026-05-20') e on e.mois = c.mois) < 4 then
    raise exception 'COMPARAISON VIDE : trop peu de mois en commun avec ecarts_mensuels';
  end if;
  raise notice 'OK — ca / depenses / resultat identiques à revenus_reel / depenses_reel / resultat_reel de ecarts_mensuels (4.6)';
end $$;

-- Années passée et future.
do $$
begin
  if (select count(*) from public.comparaison_mensuelle(2027, '2026-05-20')) <> 0 then
    raise exception 'ANNEE FUTURE : des lignes ont été renvoyées';
  end if;
  if (select count(*) from public.comparaison_mensuelle(2025, '2026-05-20')) <> 12
     or exists (select 1 from public.comparaison_mensuelle(2025, '2026-05-20') where statut_mois <> 'clos') then
    raise exception 'ANNEE PASSEE : 12 lignes toutes clos attendues';
  end if;
  raise notice 'OK — année future : 0 ligne ; année passée : 12 lignes, toutes clos';
end $$;

-- Bandeau en mai : avril comparé à mars, identique à la ligne d'avril du tableau annuel.
do $$
declare
  v_obtenu jsonb;
  v_attendu jsonb := '{"annee_clos":2026,"mois_clos":4,"annee_precedent":2026,"mois_precedent":3,
    "ca":0,"depenses":60000,"resultat":-60000,"ca_precedent":300000,"depenses_precedent":120000,"resultat_precedent":180000,
    "a_activite":true,"a_activite_precedent":true,
    "ca_variation":-300000,"ca_variation_pct":-100.00,"depenses_variation":-60000,"depenses_variation_pct":-50.00,"resultat_variation":-240000}'::jsonb;
  v_ligne_avril record;
  r record;
begin
  select to_jsonb(x) into v_obtenu from public.comparaison_accueil('2026-05-20') x;
  if v_obtenu is distinct from v_attendu then
    raise exception 'BANDEAU MAI : obtenu = % ; attendu = %', v_obtenu, v_attendu;
  end if;

  -- cohérence bandeau / tableau annuel (les deux mois dans la même année).
  select * into v_ligne_avril from public.comparaison_mensuelle(2026, '2026-05-20') where mois = 4;
  select * into r from public.comparaison_accueil('2026-05-20');
  if r.ca is distinct from v_ligne_avril.ca or r.depenses is distinct from v_ligne_avril.depenses or r.resultat is distinct from v_ligne_avril.resultat
     or r.ca_variation is distinct from v_ligne_avril.ca_variation or r.ca_variation_pct is distinct from v_ligne_avril.ca_variation_pct
     or r.depenses_variation is distinct from v_ligne_avril.depenses_variation or r.depenses_variation_pct is distinct from v_ligne_avril.depenses_variation_pct
     or r.resultat_variation is distinct from v_ligne_avril.resultat_variation then
    raise exception 'INCOHERENCE bandeau / tableau annuel pour avril';
  end if;
  raise notice 'OK — bandeau de mai : avril contre mars = ligne d''avril du tableau annuel (−300 000 / −100,00 %%, −60 000 / −50,00 %%, −240 000)';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 2. Scénario 1 du bandeau — date de référence en janvier (2027-01-15).
--    Novembre 2026 : entrée 400 000, sortie 150 000 ; décembre : entrée
--    500 000, sortie 120 000 ; janvier 2027 (en cours) : entrée 10 000 ;
--    octobre : aucune transaction.
-- ---------------------------------------------------------------------
begin;

select pg_temp.preparer(2);
select pg_temp.tx(2, '2026-11-05', 'vente', 400000);
select pg_temp.tx(2, '2026-11-06', 'fixe', 150000);
select pg_temp.tx(2, '2026-12-05', 'vente', 500000);
select pg_temp.tx(2, '2026-12-06', 'fixe', 120000);
select pg_temp.tx(2, '2027-01-08', 'vente', 10000);

set local role authenticated;
set local request.jwt.claims = '{"sub": "47020000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
declare
  v_obtenu jsonb;
  v_attendu jsonb := '{"annee_clos":2026,"mois_clos":12,"annee_precedent":2026,"mois_precedent":11,
    "ca":500000,"depenses":120000,"resultat":380000,"ca_precedent":400000,"depenses_precedent":150000,"resultat_precedent":250000,
    "a_activite":true,"a_activite_precedent":true,
    "ca_variation":100000,"ca_variation_pct":25.00,"depenses_variation":-30000,"depenses_variation_pct":-20.00,"resultat_variation":130000}'::jsonb;
  v_annuel jsonb;
  v_att_annuel jsonb := '[
    {"mois":10,"statut_mois":"clos","a_activite":false,"ca":0,"depenses":0,"resultat":0,
     "ca_variation":null,"ca_variation_pct":null,"depenses_variation":null,"depenses_variation_pct":null,"resultat_variation":null,
     "ca_cumul":0,"depenses_cumul":0,"resultat_cumul":0},
    {"mois":11,"statut_mois":"clos","a_activite":true,"ca":400000,"depenses":150000,"resultat":250000,
     "ca_variation":null,"ca_variation_pct":null,"depenses_variation":null,"depenses_variation_pct":null,"resultat_variation":null,
     "ca_cumul":400000,"depenses_cumul":150000,"resultat_cumul":250000},
    {"mois":12,"statut_mois":"clos","a_activite":true,"ca":500000,"depenses":120000,"resultat":380000,
     "ca_variation":100000,"ca_variation_pct":25.00,"depenses_variation":-30000,"depenses_variation_pct":-20.00,"resultat_variation":130000,
     "ca_cumul":900000,"depenses_cumul":270000,"resultat_cumul":630000}
  ]'::jsonb;
  v_janvier jsonb;
  v_att_janvier jsonb := '[
    {"mois":1,"statut_mois":"en_cours","a_activite":true,"ca":10000,"depenses":0,"resultat":10000,
     "ca_variation":null,"ca_variation_pct":null,"depenses_variation":null,"depenses_variation_pct":null,"resultat_variation":null,
     "ca_cumul":10000,"depenses_cumul":0,"resultat_cumul":10000}
  ]'::jsonb;
begin
  select to_jsonb(x) into v_obtenu from public.comparaison_accueil('2027-01-15') x;
  if v_obtenu is distinct from v_attendu then
    raise exception 'BANDEAU JANVIER : obtenu = % ; attendu = %', v_obtenu, v_attendu;
  end if;

  -- Tableau 2026 à la date de janvier 2027 : 12 lignes toutes clos ; octobre à novembre et décembre.
  if (select count(*) from public.comparaison_mensuelle(2026, '2027-01-15')) <> 12
     or exists (select 1 from public.comparaison_mensuelle(2026, '2027-01-15') where statut_mois <> 'clos') then
    raise exception 'TABLEAU 2026 : 12 lignes toutes clos attendues';
  end if;
  select jsonb_agg(to_jsonb(x) order by x.mois) into v_annuel
  from public.comparaison_mensuelle(2026, '2027-01-15') x where x.mois >= 10;
  if v_annuel is distinct from v_att_annuel then
    raise exception 'TABLEAU 2026 (oct. à déc.) : obtenu = % ; attendu = %', v_annuel, v_att_annuel;
  end if;

  -- Le bandeau (décembre) est identique à la ligne de décembre du tableau annuel.
  if (select ca_variation from public.comparaison_mensuelle(2026, '2027-01-15') where mois = 12)
       is distinct from (select ca_variation from public.comparaison_accueil('2027-01-15')) then
    raise exception 'INCOHERENCE bandeau / tableau annuel pour décembre';
  end if;

  -- Contre-preuve : janvier 2027 seul, en cours, sans variation (l'entrée de 10 000 n'est pas dans le bandeau).
  select jsonb_agg(to_jsonb(x) order by x.mois) into v_janvier from public.comparaison_mensuelle(2027, '2027-01-15') x;
  if v_janvier is distinct from v_att_janvier then
    raise exception 'JANVIER 2027 : obtenu = % ; attendu = %', v_janvier, v_att_janvier;
  end if;

  raise notice 'OK — bandeau de janvier : décembre 2026 contre novembre (+100 000 / +25,00 %%, −30 000 / −20,00 %%, +130 000) ; novembre sans variation (octobre vide) ; janvier 2027 seul et en cours';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 3. Scénario 2 du bandeau — février 2027 (2027-02-10), deux années.
--    Décembre 2026 : 300 000 / 200 000 ; janvier 2027 : 450 000 / 180 000 ;
--    février 2027 (en cours) : entrée 5 000.
-- ---------------------------------------------------------------------
begin;

select pg_temp.preparer(3);
select pg_temp.tx(3, '2026-12-05', 'vente', 300000);
select pg_temp.tx(3, '2026-12-06', 'fixe', 200000);
select pg_temp.tx(3, '2027-01-05', 'vente', 450000);
select pg_temp.tx(3, '2027-01-06', 'fixe', 180000);
select pg_temp.tx(3, '2027-02-04', 'vente', 5000);

set local role authenticated;
set local request.jwt.claims = '{"sub": "47030000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
declare
  v_obtenu jsonb;
  v_attendu jsonb := '{"annee_clos":2027,"mois_clos":1,"annee_precedent":2026,"mois_precedent":12,
    "ca":450000,"depenses":180000,"resultat":270000,"ca_precedent":300000,"depenses_precedent":200000,"resultat_precedent":100000,
    "a_activite":true,"a_activite_precedent":true,
    "ca_variation":150000,"ca_variation_pct":50.00,"depenses_variation":-20000,"depenses_variation_pct":-10.00,"resultat_variation":170000}'::jsonb;
  v_annuel jsonb;
  v_att_annuel jsonb := '[
    {"mois":1,"statut_mois":"clos","a_activite":true,"ca":450000,"depenses":180000,"resultat":270000,
     "ca_variation":null,"ca_variation_pct":null,"depenses_variation":null,"depenses_variation_pct":null,"resultat_variation":null,
     "ca_cumul":450000,"depenses_cumul":180000,"resultat_cumul":270000},
    {"mois":2,"statut_mois":"en_cours","a_activite":true,"ca":5000,"depenses":0,"resultat":5000,
     "ca_variation":-445000,"ca_variation_pct":-98.89,"depenses_variation":-180000,"depenses_variation_pct":-100.00,"resultat_variation":-265000,
     "ca_cumul":455000,"depenses_cumul":180000,"resultat_cumul":275000}
  ]'::jsonb;
begin
  select to_jsonb(x) into v_obtenu from public.comparaison_accueil('2027-02-10') x;
  if v_obtenu is distinct from v_attendu then
    raise exception 'BANDEAU FEVRIER : obtenu = % ; attendu = %', v_obtenu, v_attendu;
  end if;

  -- Le tableau annuel ne change pas : janvier 2027 reste sans variation.
  select jsonb_agg(to_jsonb(x) order by x.mois) into v_annuel from public.comparaison_mensuelle(2027, '2027-02-10') x;
  if v_annuel is distinct from v_att_annuel then
    raise exception 'TABLEAU 2027 : obtenu = % ; attendu = %', v_annuel, v_att_annuel;
  end if;

  raise notice 'OK — bandeau de février : janvier 2027 contre décembre 2026 (+150 000 / +50,00 %%, −20 000 / −10,00 %%, +170 000) ; tableau annuel 2027 : janvier sans variation, février −445 000 / −98,89 %%';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 4. Scénario 3 du bandeau — « décembre vide » (2027-02-10) : seul janvier
--    2027 a des transactions ; la règle 2 s'applique à cheval sur deux années.
-- ---------------------------------------------------------------------
begin;

select pg_temp.preparer(4);
select pg_temp.tx(4, '2027-01-05', 'vente', 450000);
select pg_temp.tx(4, '2027-01-06', 'fixe', 180000);

set local role authenticated;
set local request.jwt.claims = '{"sub": "47040000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
declare
  v_obtenu jsonb;
  v_attendu jsonb := '{"annee_clos":2027,"mois_clos":1,"annee_precedent":2026,"mois_precedent":12,
    "ca":450000,"depenses":180000,"resultat":270000,"ca_precedent":0,"depenses_precedent":0,"resultat_precedent":0,
    "a_activite":true,"a_activite_precedent":false,
    "ca_variation":null,"ca_variation_pct":null,"depenses_variation":null,"depenses_variation_pct":null,"resultat_variation":null}'::jsonb;
begin
  select to_jsonb(x) into v_obtenu from public.comparaison_accueil('2027-02-10') x;
  if v_obtenu is distinct from v_attendu then
    raise exception 'DECEMBRE VIDE : obtenu = % ; attendu = %', v_obtenu, v_attendu;
  end if;
  raise notice 'OK — décembre vide : janvier 2027 = 450 000 / 180 000 / 270 000, toutes les variations null (pas de comparaison)';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 5. Entreprise SANS aucune transaction : mois jusqu'à la date de
--    référence, tous à 0, a_activite faux, variations null dès janvier ;
--    bandeau : une ligne à 0 sans variation. Aucune division par zéro.
-- ---------------------------------------------------------------------
begin;

select pg_temp.preparer(5);

set local role authenticated;
set local request.jwt.claims = '{"sub": "47050000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
declare
  v_obtenu jsonb;
  v_attendu jsonb;
  v_ligne jsonb := '{"statut_mois":"clos","a_activite":false,"ca":0,"depenses":0,"resultat":0,
     "ca_variation":null,"ca_variation_pct":null,"depenses_variation":null,"depenses_variation_pct":null,"resultat_variation":null,
     "ca_cumul":0,"depenses_cumul":0,"resultat_cumul":0}'::jsonb;
  v_bandeau jsonb;
begin
  select jsonb_agg(v_ligne || jsonb_build_object('mois', m) order by m) into v_attendu from generate_series(1, 5) m;
  v_attendu := jsonb_set(v_attendu, '{4,statut_mois}', '"en_cours"');

  select jsonb_agg(to_jsonb(x) order by x.mois) into v_obtenu from public.comparaison_mensuelle(2026, '2026-05-20') x;
  if v_obtenu is distinct from v_attendu then
    raise exception 'SANS TRANSACTION : obtenu = % ; attendu = %', v_obtenu, v_attendu;
  end if;

  select to_jsonb(x) into v_bandeau from public.comparaison_accueil('2026-05-20') x;
  if v_bandeau is distinct from '{"annee_clos":2026,"mois_clos":4,"annee_precedent":2026,"mois_precedent":3,
    "ca":0,"depenses":0,"resultat":0,"ca_precedent":0,"depenses_precedent":0,"resultat_precedent":0,
    "a_activite":false,"a_activite_precedent":false,
    "ca_variation":null,"ca_variation_pct":null,"depenses_variation":null,"depenses_variation_pct":null,"resultat_variation":null}'::jsonb then
    raise exception 'BANDEAU SANS TRANSACTION : obtenu = %', v_bandeau;
  end if;

  raise notice 'OK — entreprise sans transaction : 5 mois à 0, a_activite faux, variations null dès janvier ; bandeau à 0 sans variation ; aucune division par zéro';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 6. Adversariaux : deux entreprises avec leurs propres transactions
--    (A : 1 000 / 400, B : 9 000 / 4 000, janvier 2026), utilisateurs
--    authentifiés réels.
-- ---------------------------------------------------------------------
begin;

select pg_temp.preparer(6);
select pg_temp.preparer(7);
select pg_temp.tx(6, '2026-01-10', 'vente', 1000);
select pg_temp.tx(6, '2026-01-12', 'fixe', 400);
select pg_temp.tx(7, '2026-01-10', 'vente', 9000);
select pg_temp.tx(7, '2026-01-12', 'fixe', 4000);

-- 6.1 Le comptable de A : zéro ligne sur les deux fonctions, alors que ses
--     transactions lui sont lisibles (la restriction vient des fonctions).
set local role authenticated;
set local request.jwt.claims = '{"sub": "47060000-0000-0000-0000-0000000000c2", "role": "authenticated"}';

do $$
begin
  if (select count(*) from public.transactions) = 0 then
    raise exception 'TEMOIN : le comptable devrait lire les transactions de son entreprise';
  end if;
  if (select count(*) from public.comparaison_mensuelle(2026, '2026-03-10')) <> 0 then
    raise exception 'COMPTABLE : comparaison_mensuelle a renvoyé des lignes';
  end if;
  if (select count(*) from public.comparaison_accueil('2026-03-10')) <> 0 then
    raise exception 'COMPTABLE : comparaison_accueil a renvoyé une ligne';
  end if;
  raise notice 'OK — comptable : zéro ligne sur les deux fonctions (ses transactions restent lisibles par RLS)';
end $$;

-- 6.2 Supervision Be Smart (claim super_admin) : zéro ligne.
set local request.jwt.claims = '{"sub": "c0000000-0000-0000-0000-000000000001", "role": "authenticated", "app_metadata": {"super_admin": true}}';

do $$
begin
  if (select count(*) from public.comparaison_mensuelle(2026, '2026-03-10')) <> 0
     or (select count(*) from public.comparaison_accueil('2026-03-10')) <> 0 then
    raise exception 'SUPERVISION : des lignes ont été renvoyées';
  end if;
  raise notice 'OK — supervision Be Smart : zéro ligne sur les deux fonctions';
end $$;

-- 6.3 CEO de A : uniquement ses chiffres (1 000 / 400), jamais ceux de B.
set local request.jwt.claims = '{"sub": "47060000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
declare
  r record;
begin
  select * into r from public.comparaison_mensuelle(2026, '2026-03-10') where mois = 1;
  if r.ca <> 1000 or r.depenses <> 400 or r.resultat <> 600 or r.ca_cumul <> 1000 then
    raise exception 'CEO A : ca=% dep=% res=% (attendu 1000 / 400 / 600)', r.ca, r.depenses, r.resultat;
  end if;
  select * into r from public.comparaison_accueil('2026-02-10');
  if r.ca <> 1000 or r.depenses <> 400 or r.resultat <> 600 then
    raise exception 'CEO A (bandeau de février) : ca=% dep=% res=%', r.ca, r.depenses, r.resultat;
  end if;
  raise notice 'OK — CEO de A : 1 000 / 400 / 600, rien de B (tableau et bandeau)';
end $$;

-- 6.4 CEO de B : uniquement ses chiffres (9 000 / 4 000).
set local request.jwt.claims = '{"sub": "47070000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
declare
  r record;
begin
  select * into r from public.comparaison_mensuelle(2026, '2026-03-10') where mois = 1;
  if r.ca <> 9000 or r.depenses <> 4000 or r.resultat <> 5000 or r.ca_cumul <> 9000 then
    raise exception 'CEO B : ca=% dep=% res=% (attendu 9000 / 4000 / 5000)', r.ca, r.depenses, r.resultat;
  end if;
  select * into r from public.comparaison_accueil('2026-02-10');
  if r.ca <> 9000 or r.depenses <> 4000 or r.resultat <> 5000 then
    raise exception 'CEO B (bandeau de février) : ca=% dep=% res=%', r.ca, r.depenses, r.resultat;
  end if;
  raise notice 'OK — CEO de B : 9 000 / 4 000 / 5 000, rien de A (tableau et bandeau)';
end $$;

-- 6.5 anon : appel refusé sur les deux fonctions (et sur la fonction pure).
reset role;
set local role anon;

do $$
declare
  v_nom text;
begin
  foreach v_nom in array array['comparaison_mensuelle', 'comparaison_accueil', 'variation_mensuelle'] loop
    begin
      if v_nom = 'comparaison_mensuelle' then
        perform * from public.comparaison_mensuelle(2026, '2026-03-10');
      elsif v_nom = 'comparaison_accueil' then
        perform * from public.comparaison_accueil('2026-03-10');
      else
        perform * from public.variation_mensuelle(1, 1, true, true);
      end if;
      raise exception 'ANON : % a été exécutée', v_nom;
    exception
      when insufficient_privilege then
        null;
    end;
  end loop;
  raise notice 'OK — anon : permission refusée sur comparaison_mensuelle, comparaison_accueil et variation_mensuelle';
end $$;

rollback;
