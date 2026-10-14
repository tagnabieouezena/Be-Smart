-- Tests du prérequis « solde de caisse initial daté » (Module 4.8).
-- Voir docs/briefs/Solde-Initial-Date.md. Chaque scénario s'exécute en
-- BEGIN … ROLLBACK avec des entreprises dédiées : rien ne persiste. Les
-- appels se font en utilisateur authentifié réel (role authenticated + sub),
-- jamais en service_role. Attendus chiffrés écrits en dur.
--
-- Règle testée : solde à la FIN de la journée t, avec D = date_solde_initial
--   t >= D : S + somme(D < date <= t)      t < D : S - somme(t < date <= D)

set client_min_messages to notice;

-- ---------------------------------------------------------------------
-- Aides de préparation (exécutées en tant que postgres).
-- ---------------------------------------------------------------------
create function pg_temp.idu(p_ii int, p_suffixe text) returns uuid
language sql immutable as $$
  select ('48' || lpad(p_ii::text, 2, '0') || '0000-0000-0000-0000-0000000000' || p_suffixe)::uuid;
$$;

-- Entreprise dédiée : CEO (c1), comptable (c2), catégories (21 fixe, 23 revenu).
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
     'ceo-48' || p_ii || '@test.besmart.local', crypt('mot-de-passe-test', gen_salt('bf')),
     now(), '{}', '{}', now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', pg_temp.idu(p_ii, 'c2'), 'authenticated', 'authenticated',
     'comptable-48' || p_ii || '@test.besmart.local', crypt('mot-de-passe-test', gen_salt('bf')),
     now(), '{}', '{}', now(), now(), '', '', '', '');

  insert into public.entreprises (id, nom, secteur, devise, solde_initial, date_solde_initial)
  values (pg_temp.idu(p_ii, '01'), 'Entreprise Solde ' || p_ii, 'Test', 'FCFA', p_solde, p_date);

  insert into public.utilisateurs (id, nom, email, role, entreprise_id) values
    (pg_temp.idu(p_ii, 'c1'), 'CEO 48' || p_ii, 'ceo-48' || p_ii || '@test.besmart.local', 'ceo', pg_temp.idu(p_ii, '01')),
    (pg_temp.idu(p_ii, 'c2'), 'Comptable 48' || p_ii, 'comptable-48' || p_ii || '@test.besmart.local', 'comptable', pg_temp.idu(p_ii, '01'));

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

-- Les neuf transactions du scénario A, dans l'ordre demandé :
--   1 = chronologique ; 3 = octobre d'abord, puis janvier à septembre.
create function pg_temp.historique_a(p_ii int, p_ordre int) returns void
language plpgsql as $$
begin
  if p_ordre = 3 then
    perform pg_temp.tx(p_ii, '2026-10-05', 'vente', 40000);
    perform pg_temp.tx(p_ii, '2026-10-13', 'vente', 25000);
    perform pg_temp.tx(p_ii, '2026-10-20', 'fixe', 70000);
  end if;
  perform pg_temp.tx(p_ii, '2026-01-10', 'vente', 300000);
  perform pg_temp.tx(p_ii, '2026-02-05', 'fixe', 120000);
  perform pg_temp.tx(p_ii, '2026-03-20', 'vente', 90000);
  perform pg_temp.tx(p_ii, '2026-05-15', 'fixe', 60000);
  perform pg_temp.tx(p_ii, '2026-07-01', 'vente', 150000);
  perform pg_temp.tx(p_ii, '2026-09-30', 'fixe', 200000);
  if p_ordre <> 3 then
    perform pg_temp.tx(p_ii, '2026-10-05', 'vente', 40000);
    perform pg_temp.tx(p_ii, '2026-10-13', 'vente', 25000);
    perform pg_temp.tx(p_ii, '2026-10-20', 'fixe', 70000);
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 0. Propriétés de sécurité : fonction, trigger, colonne, ACL.
-- ---------------------------------------------------------------------
begin;

do $$
declare
  v_nom text;
  v_def boolean;
  v_config text[];
  v_grantees text[];
begin
  foreach v_nom in array array['public.solde_caisse_a(date)', 'public.ecarts_mensuels(int, date)'] loop
    select prosecdef, proconfig into v_def, v_config from pg_proc where oid = v_nom::regprocedure;
    if v_def then raise exception '% ne doit jamais être security definer', v_nom; end if;
    if not ('search_path=public' = any (coalesce(v_config, '{}'))) then
      raise exception '% doit fixer search_path = public (config : %)', v_nom, v_config;
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
    if has_function_privilege('anon', v_nom::regprocedure, 'execute') then
      raise exception 'ACL : anon peut exécuter %', v_nom;
    end if;
    if not has_function_privilege('authenticated', v_nom::regprocedure, 'execute') then
      raise exception 'ACL : authenticated ne peut pas exécuter %', v_nom;
    end if;
  end loop;

  -- Colonne : not null, défaut 2000-01-01.
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'entreprises' and column_name = 'date_solde_initial'
      and is_nullable = 'NO' and column_default like '%2000-01-01%'
  ) then
    raise exception 'date_solde_initial doit être not null avec le défaut 2000-01-01';
  end if;

  -- La fonction du trigger n'est exécutable par aucun rôle applicatif.
  if has_function_privilege('anon', 'public.verifier_date_solde_initial()'::regprocedure, 'execute')
     or has_function_privilege('authenticated', 'public.verifier_date_solde_initial()'::regprocedure, 'execute') then
    raise exception 'verifier_date_solde_initial est exécutable par anon ou authenticated';
  end if;

  -- Le trigger de date future existe, sur insert et sur update de la colonne.
  if not exists (
    select 1 from pg_trigger
    where tgname = 'entreprises_date_solde_initial' and tgrelid = 'public.entreprises'::regclass and not tgisinternal
  ) then
    raise exception 'trigger entreprises_date_solde_initial introuvable';
  end if;

  -- Aucune des deux colonnes n'est exposée par la vue de supervision.
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'v_entreprises_supervision'
      and column_name in ('solde_initial', 'date_solde_initial')
  ) then
    raise exception 'v_entreprises_supervision expose le solde initial ou sa date';
  end if;

  -- Défaut appliqué aux entreprises du seed.
  if exists (
    select 1 from public.entreprises
    where id in ('a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001')
      and date_solde_initial <> date '2000-01-01'
  ) then
    raise exception 'le seed devrait porter la date par défaut 2000-01-01';
  end if;

  raise notice 'OK — solde_caisse_a et ecarts_mensuels : security invoker, search_path fixé, ACL sans PUBLIC ni anon ; colonne not null défaut 2000-01-01 ; trigger présent ; vue de supervision sans solde ni date ; seed au défaut';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- A. Solde saisi en octobre, historique de janvier à septembre importé.
--    S = 800 000, D = 2026-10-13. Trois ordres de saisie, mêmes résultats :
--    (1) solde d'abord, transactions chronologiques ;
--    (2) transactions d'abord, solde et date ensuite ;
--    (3) solde, puis octobre, PUIS l'historique de janvier à septembre.
-- ---------------------------------------------------------------------
begin;

-- Ordre 1
select pg_temp.preparer(11, 800000, '2026-10-13');
select pg_temp.historique_a(11, 1);
-- Ordre 2 : l'entreprise naît avec le défaut, les transactions arrivent, puis le solde est saisi.
select pg_temp.preparer(12, 0, '2000-01-01');
select pg_temp.historique_a(12, 2);
update public.entreprises set solde_initial = 800000, date_solde_initial = '2026-10-13' where id = pg_temp.idu(12, '01');
-- Ordre 3
select pg_temp.preparer(13, 800000, '2026-10-13');
select pg_temp.historique_a(13, 3);

set local role authenticated;

do $$
declare
  v_ii int;
  v_f jsonb;
  v_ecarts jsonb;
  v_attendu_f jsonb := '[
    {"t":"2025-12-31","f":575000},{"t":"2026-01-31","f":875000},{"t":"2026-02-28","f":755000},
    {"t":"2026-03-31","f":845000},{"t":"2026-04-30","f":845000},{"t":"2026-05-31","f":785000},
    {"t":"2026-06-30","f":785000},{"t":"2026-07-31","f":935000},{"t":"2026-08-31","f":935000},
    {"t":"2026-09-29","f":935000},{"t":"2026-09-30","f":735000},{"t":"2026-10-05","f":775000},
    {"t":"2026-10-12","f":775000},{"t":"2026-10-13","f":800000},{"t":"2026-10-19","f":800000},
    {"t":"2026-10-20","f":730000},{"t":"2026-10-31","f":730000}
  ]'::jsonb;
  v_attendu_ecarts jsonb := '[
    {"mois":1,"resultat_reel":300000,"solde_debut":575000,"solde_fin_reel":875000},
    {"mois":2,"resultat_reel":-120000,"solde_debut":875000,"solde_fin_reel":755000},
    {"mois":3,"resultat_reel":90000,"solde_debut":755000,"solde_fin_reel":845000},
    {"mois":5,"resultat_reel":-60000,"solde_debut":845000,"solde_fin_reel":785000},
    {"mois":7,"resultat_reel":150000,"solde_debut":785000,"solde_fin_reel":935000},
    {"mois":9,"resultat_reel":-200000,"solde_debut":935000,"solde_fin_reel":735000},
    {"mois":10,"resultat_reel":-5000,"solde_debut":735000,"solde_fin_reel":730000}
  ]'::jsonb;
begin
  foreach v_ii in array array[11, 12, 13] loop
    perform set_config('request.jwt.claims',
      format('{"sub": "48%s0000-0000-0000-0000-0000000000c1", "role": "authenticated"}', lpad(v_ii::text, 2, '0')), true);

    select jsonb_agg(jsonb_build_object('t', d::text, 'f', public.solde_caisse_a(d)) order by d) into v_f
    from unnest(array[
      '2025-12-31', '2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30', '2026-05-31', '2026-06-30',
      '2026-07-31', '2026-08-31', '2026-09-29', '2026-09-30', '2026-10-05', '2026-10-12', '2026-10-13',
      '2026-10-19', '2026-10-20', '2026-10-31'
    ]::date[]) d;
    if v_f is distinct from v_attendu_f then
      raise exception 'ORDRE % : soldes obtenus = % ; attendus = %', v_ii - 10, v_f, v_attendu_f;
    end if;

    select jsonb_agg(jsonb_build_object('mois', mois, 'resultat_reel', resultat_reel, 'solde_debut', solde_debut, 'solde_fin_reel', solde_fin_reel) order by mois)
    into v_ecarts
    from public.ecarts_mensuels(2026, '2026-10-20');
    if v_ecarts is distinct from v_attendu_ecarts then
      raise exception 'ORDRE % : ecarts_mensuels obtenu = % ; attendu = %', v_ii - 10, v_ecarts, v_attendu_ecarts;
    end if;
  end loop;

  raise notice 'OK — scénario A : 17 soldes (F(2025-12-31) = 575 000, F(13/10) = 800 000 = solde saisi, F(20/10) = 730 000) et 7 mois d''ecarts_mensuels identiques pour les trois ordres de saisie, sans double comptage';
end $$;

-- La transaction du jour D (13 octobre, +25 000) est déjà dans le solde saisi :
-- F(D) = S et F(D - 1) = S - 25 000 ; une transaction à D + 1 s'ajoute.
do $$
begin
  perform set_config('request.jwt.claims', '{"sub": "48110000-0000-0000-0000-0000000000c1", "role": "authenticated"}', true);
  if public.solde_caisse_a('2026-10-13') <> 800000 or public.solde_caisse_a('2026-10-12') <> 775000 then
    raise exception 'JOUR D : F(D) = % (800000 attendu), F(D-1) = % (775000 attendu)', public.solde_caisse_a('2026-10-13'), public.solde_caisse_a('2026-10-12');
  end if;
  raise notice 'OK — la transaction datée D est dans le solde saisi (F(D) = S, F(D−1) = S − 25 000)';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- B. Modification du solde ou de sa date : tout est relu sans migration.
-- ---------------------------------------------------------------------
begin;

select pg_temp.preparer(14, 800000, '2026-10-13');
select pg_temp.historique_a(14, 1);

set local role authenticated;
set local request.jwt.claims = '{"sub": "48140000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
declare
  r record;
  v_cas record;
begin
  for v_cas in
    select * from (values
      (1, 800000::numeric, date '2026-10-13', 575000::numeric, 735000::numeric, 730000::numeric),
      (2, 800000::numeric, date '2026-09-30', 640000::numeric, 800000::numeric, 795000::numeric),
      (3, 900000::numeric, date '2026-10-13', 675000::numeric, 835000::numeric, 830000::numeric),
      (4, 500000::numeric, date '2026-06-30', 290000::numeric, 450000::numeric, 445000::numeric)
    ) as c(n, s, d, f_ouverture, f_sept, f_oct)
  loop
    update public.entreprises
    set solde_initial = v_cas.s, date_solde_initial = v_cas.d
    where id = '48140000-0000-0000-0000-000000000001';
    if not found then
      raise exception 'CAS % : le CEO n''a pas pu modifier son solde', v_cas.n;
    end if;

    if public.solde_caisse_a('2025-12-31') <> v_cas.f_ouverture
       or public.solde_caisse_a('2026-09-30') <> v_cas.f_sept
       or public.solde_caisse_a('2026-10-31') <> v_cas.f_oct
       or public.solde_caisse_a(v_cas.d) <> v_cas.s then
      raise exception 'CAS % (S=%, D=%) : F(2025-12-31)=%, F(2026-09-30)=%, F(2026-10-31)=%, F(D)=% (attendus % / % / % / %)',
        v_cas.n, v_cas.s, v_cas.d, public.solde_caisse_a('2025-12-31'), public.solde_caisse_a('2026-09-30'),
        public.solde_caisse_a('2026-10-31'), public.solde_caisse_a(v_cas.d),
        v_cas.f_ouverture, v_cas.f_sept, v_cas.f_oct, v_cas.s;
    end if;

    -- ecarts_mensuels suit immédiatement : ouverture de janvier et fin d'octobre.
    select (array_agg(solde_debut order by mois))[1] as ouverture, (array_agg(solde_fin_reel order by mois))[array_length(array_agg(mois), 1)] as fin
    into r
    from public.ecarts_mensuels(2026, '2026-10-20');
    if r.ouverture <> v_cas.f_ouverture or r.fin <> v_cas.f_oct then
      raise exception 'CAS % : ecarts_mensuels ne suit pas (ouverture=%, fin=%)', v_cas.n, r.ouverture, r.fin;
    end if;
  end loop;

  raise notice 'OK — scénario B : 4 modifications (date seule, montant seul, les deux) : soldes recalculés sans migration, F(D) = S à chaque fois, ecarts_mensuels suit';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- C. Soldes négatifs : S = −50 000 au 2026-03-31.
-- ---------------------------------------------------------------------
begin;

select pg_temp.preparer(15, -50000, '2026-03-31');
select pg_temp.tx(15, '2026-01-15', 'vente', 100000);
select pg_temp.tx(15, '2026-02-10', 'fixe', 30000);
select pg_temp.tx(15, '2026-04-12', 'vente', 20000);
select pg_temp.tx(15, '2026-05-20', 'fixe', 90000);

set local role authenticated;
set local request.jwt.claims = '{"sub": "48150000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
declare
  v_obtenu jsonb;
  v_attendu jsonb := '[
    {"t":"2025-12-31","f":-120000},{"t":"2026-01-31","f":-20000},{"t":"2026-02-28","f":-50000},
    {"t":"2026-03-31","f":-50000},{"t":"2026-04-30","f":-30000},{"t":"2026-05-31","f":-120000}
  ]'::jsonb;
begin
  select jsonb_agg(jsonb_build_object('t', d::text, 'f', public.solde_caisse_a(d)) order by d) into v_obtenu
  from unnest(array['2025-12-31', '2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30', '2026-05-31']::date[]) d;
  if v_obtenu is distinct from v_attendu then
    raise exception 'NEGATIF : obtenu = % ; attendu = %', v_obtenu, v_attendu;
  end if;
  raise notice 'OK — soldes négatifs : solde initial négatif (−50 000) et soldes reconstitués négatifs (−120 000, −20 000, −50 000, −30 000) conformes';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- D. Bornes de la date : D−1 / D / D+1, date du jour, date future,
--    déclenchement du trigger limité à la colonne.
-- ---------------------------------------------------------------------
begin;

select pg_temp.preparer(16, 1000, '2026-06-15');
select pg_temp.tx(16, '2026-06-14', 'vente', 10);
select pg_temp.tx(16, '2026-06-15', 'vente', 100);
select pg_temp.tx(16, '2026-06-16', 'vente', 1000);

set local role authenticated;
set local request.jwt.claims = '{"sub": "48160000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
declare
  v_obtenu jsonb;
  v_attendu jsonb := '[
    {"t":"2026-06-13","f":890},{"t":"2026-06-14","f":900},{"t":"2026-06-15","f":1000},{"t":"2026-06-16","f":2000}
  ]'::jsonb;
  v_avant date;
begin
  select jsonb_agg(jsonb_build_object('t', d::text, 'f', public.solde_caisse_a(d)) order by d) into v_obtenu
  from unnest(array['2026-06-13', '2026-06-14', '2026-06-15', '2026-06-16']::date[]) d;
  if v_obtenu is distinct from v_attendu then
    raise exception 'BORNES : obtenu = % ; attendu = %', v_obtenu, v_attendu;
  end if;

  -- La date du jour est acceptée.
  update public.entreprises set date_solde_initial = current_date where id = '48160000-0000-0000-0000-000000000001';
  if not found then raise exception 'La date du jour devrait être acceptée'; end if;

  -- Une date future est refusée, et la ligne n'est pas modifiée.
  begin
    update public.entreprises set date_solde_initial = current_date + 1 where id = '48160000-0000-0000-0000-000000000001';
    raise exception 'FUTUR : une date dans le futur a été acceptée';
  exception when others then
    if sqlerrm <> 'La date du solde de caisse ne peut pas être dans le futur.' then
      raise exception 'FUTUR : message inattendu : %', sqlerrm;
    end if;
  end;
  select date_solde_initial into v_avant from public.entreprises where id = '48160000-0000-0000-0000-000000000001';
  if v_avant <> current_date then
    raise exception 'FUTUR : la date a changé malgré le refus (%)', v_avant;
  end if;

  raise notice 'OK — bornes : F(D−1) = 900 (la transaction du jour D est retirée), F(D) = 1 000, F(D+1) = 2 000 ; date du jour acceptée ; date future refusée avec le message prévu, ligne inchangée';
end $$;

-- Insertion avec une date future refusée aussi (postgres).
reset role;

do $$
begin
  begin
    insert into public.entreprises (nom, date_solde_initial) values ('Entreprise future', current_date + 1);
    raise exception 'FUTUR (insert) : acceptée';
  exception when others then
    if sqlerrm <> 'La date du solde de caisse ne peut pas être dans le futur.' then
      raise exception 'FUTUR (insert) : message inattendu : %', sqlerrm;
    end if;
  end;
  raise notice 'OK — insertion avec une date future refusée';
end $$;

-- Le trigger ne se déclenche que sur la colonne : on force une date future
-- (trigger désactivé), puis une mise à jour d'une autre colonne doit passer.
alter table public.entreprises disable trigger entreprises_date_solde_initial;
update public.entreprises set date_solde_initial = current_date + 5 where id = '48160000-0000-0000-0000-000000000001';
alter table public.entreprises enable trigger entreprises_date_solde_initial;

set local role authenticated;
set local request.jwt.claims = '{"sub": "48160000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
begin
  update public.entreprises set nom = 'Autre nom' where id = '48160000-0000-0000-0000-000000000001';
  if not found then raise exception 'AUTRE COLONNE : mise à jour du nom refusée'; end if;
  raise notice 'OK — une mise à jour d''une autre colonne (nom) ne déclenche pas le contrôle de date';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- E. Non-régression : date par défaut, entreprise sans date explicite.
--    solde_caisse_a(t) = S + somme(date <= t) ; les scripts du 4.6, du 4.7 et
--    des créances passent sans modification (relancés par la CI).
-- ---------------------------------------------------------------------
begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values (
  '00000000-0000-0000-0000-000000000000', '48170000-0000-0000-0000-0000000000c1', 'authenticated', 'authenticated',
  'ceo-4817@test.besmart.local', crypt('mot-de-passe-test', gen_salt('bf')), now(), '{}', '{}', now(), now(), '', '', '', ''
);
-- Insertion SANS date explicite : le défaut s'applique.
insert into public.entreprises (id, nom, secteur, devise, solde_initial)
values ('48170000-0000-0000-0000-000000000001', 'Entreprise Defaut', 'Test', 'FCFA', 250000);
insert into public.utilisateurs (id, nom, email, role, entreprise_id)
values ('48170000-0000-0000-0000-0000000000c1', 'CEO 4817', 'ceo-4817@test.besmart.local', 'ceo', '48170000-0000-0000-0000-000000000001');
insert into public.categories (id, entreprise_id, libelle, type) values
  ('48170000-0000-0000-0000-000000000023', '48170000-0000-0000-0000-000000000001', 'Ventes', 'revenu'),
  ('48170000-0000-0000-0000-000000000021', '48170000-0000-0000-0000-000000000001', 'Loyer', 'fixe');
insert into public.transactions (entreprise_id, date, description, categorie_id, type, montant, mode_paiement, saisi_par) values
  ('48170000-0000-0000-0000-000000000001', '2026-02-01', 'v', '48170000-0000-0000-0000-000000000023', 'entree', 100000, 'cash', '48170000-0000-0000-0000-0000000000c1'),
  ('48170000-0000-0000-0000-000000000001', '2026-03-15', 'l', '48170000-0000-0000-0000-000000000021', 'sortie', 40000, 'cash', '48170000-0000-0000-0000-0000000000c1'),
  ('48170000-0000-0000-0000-000000000001', '2026-03-15', 'v', '48170000-0000-0000-0000-000000000023', 'entree', 30000, 'cash', '48170000-0000-0000-0000-0000000000c1');

set local role authenticated;
set local request.jwt.claims = '{"sub": "48170000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
declare
  v_obtenu jsonb;
  v_attendu jsonb := '[
    {"t":"1999-12-31","f":250000},{"t":"2026-01-31","f":250000},{"t":"2026-02-01","f":350000},
    {"t":"2026-03-14","f":350000},{"t":"2026-03-15","f":340000},{"t":"2026-12-31","f":340000}
  ]'::jsonb;
  v_defaut date;
begin
  select date_solde_initial into v_defaut from public.entreprises where id = '48170000-0000-0000-0000-000000000001';
  if v_defaut <> date '2000-01-01' then raise exception 'DEFAUT : date = %', v_defaut; end if;

  select jsonb_agg(jsonb_build_object('t', d::text, 'f', public.solde_caisse_a(d)) order by d) into v_obtenu
  from unnest(array['1999-12-31', '2026-01-31', '2026-02-01', '2026-03-14', '2026-03-15', '2026-12-31']::date[]) d;
  if v_obtenu is distinct from v_attendu then
    raise exception 'NON-REGRESSION : obtenu = % ; attendu = %', v_obtenu, v_attendu;
  end if;

  -- Équivalence avec l'ancienne règle : solde_initial + somme(date <= t).
  if exists (
    select 1
    from unnest(array['2026-01-31', '2026-02-01', '2026-03-14', '2026-03-15', '2026-12-31']::date[]) d
    where public.solde_caisse_a(d) <> 250000 + coalesce((
      select sum(case when t.type = 'entree' then t.montant else -t.montant end)
      from public.transactions t where t.date <= d
    ), 0)
  ) then
    raise exception 'NON-REGRESSION : écart avec solde_initial + somme(date <= t)';
  end if;

  raise notice 'OK — entreprise sans date explicite : défaut 2000-01-01, solde = 250 000 + somme des transactions jusqu''à t (350 000 au 1er février, 340 000 au 15 mars), égal à l''ancienne règle';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- F. Sécurité : comptable, supervision, isolation A / B, anon.
--    A : S = 111 000 au 2026-04-30 ; B : S = 777 000 au 2026-05-31.
-- ---------------------------------------------------------------------
begin;

select pg_temp.preparer(18, 111000, '2026-04-30');
select pg_temp.preparer(19, 777000, '2026-05-31');
select pg_temp.tx(18, '2026-03-10', 'vente', 5000);
select pg_temp.tx(19, '2026-03-10', 'vente', 9000);

-- F1. Le comptable de A : null (il lit pourtant les transactions), écriture refusée (0 ligne).
set local role authenticated;
set local request.jwt.claims = '{"sub": "48180000-0000-0000-0000-0000000000c2", "role": "authenticated"}';

do $$
declare
  v_lignes int;
begin
  if (select count(*) from public.transactions) = 0 then
    raise exception 'TEMOIN : le comptable devrait lire les transactions de son entreprise';
  end if;
  if public.solde_caisse_a('2026-06-30') is not null then
    raise exception 'COMPTABLE : solde_caisse_a n''est pas null';
  end if;
  update public.entreprises set date_solde_initial = '2026-01-01', solde_initial = 1 where id = '48180000-0000-0000-0000-000000000001';
  get diagnostics v_lignes = row_count;
  if v_lignes <> 0 then
    raise exception 'COMPTABLE : %  ligne(s) modifiée(s) dans entreprises', v_lignes;
  end if;
  raise notice 'OK — comptable : solde_caisse_a null (transactions lisibles), modification du solde ou de sa date refusée (0 ligne)';
end $$;

-- F2. Supervision Be Smart : null et écriture refusée.
set local request.jwt.claims = '{"sub": "c0000000-0000-0000-0000-000000000001", "role": "authenticated", "app_metadata": {"super_admin": true}}';

do $$
declare
  v_lignes int;
begin
  if public.solde_caisse_a('2026-06-30') is not null then
    raise exception 'SUPERVISION : solde_caisse_a n''est pas null';
  end if;
  update public.entreprises set date_solde_initial = '2026-01-01' where id = '48180000-0000-0000-0000-000000000001';
  get diagnostics v_lignes = row_count;
  if v_lignes <> 0 then raise exception 'SUPERVISION : modification acceptée'; end if;
  raise notice 'OK — supervision Be Smart : solde_caisse_a null, modification refusée';
end $$;

-- F3. Isolation A / B : chaque CEO voit son solde, ne peut pas toucher l'autre.
set local request.jwt.claims = '{"sub": "48180000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
declare
  v_lignes int;
begin
  if public.solde_caisse_a('2026-04-30') <> 111000 or public.solde_caisse_a('2026-03-09') <> 106000 then
    raise exception 'CEO A : F(2026-04-30) = % (111000 attendu), F(2026-03-09) = % (106000 attendu)', public.solde_caisse_a('2026-04-30'), public.solde_caisse_a('2026-03-09');
  end if;
  update public.entreprises set solde_initial = 1, date_solde_initial = '2026-01-01' where id = '48190000-0000-0000-0000-000000000001';
  get diagnostics v_lignes = row_count;
  if v_lignes <> 0 then raise exception 'CEO A a modifié le solde de B'; end if;
  if exists (select 1 from public.entreprises where id = '48190000-0000-0000-0000-000000000001') then
    raise exception 'CEO A voit l''entreprise B';
  end if;
  raise notice 'OK — CEO de A : 111 000 au 30/04 (et 106 000 au 09/03 en remontant le temps), l''entreprise B est invisible et immodifiable';
end $$;

set local request.jwt.claims = '{"sub": "48190000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
begin
  if public.solde_caisse_a('2026-05-31') <> 777000 or public.solde_caisse_a('2026-03-09') <> 768000 then
    raise exception 'CEO B : F(2026-05-31) = % (777000 attendu), F(2026-03-09) = % (768000 attendu)', public.solde_caisse_a('2026-05-31'), public.solde_caisse_a('2026-03-09');
  end if;
  raise notice 'OK — CEO de B : 777 000 au 31/05 (et 768 000 au 09/03), rien de A';
end $$;

-- F4. anon : appel refusé.
reset role;
set local role anon;

do $$
begin
  begin
    perform public.solde_caisse_a('2026-06-30');
    raise exception 'ANON : solde_caisse_a a été exécutée';
  exception when insufficient_privilege then
    null;
  end;
  raise notice 'OK — anon : permission refusée sur solde_caisse_a';
end $$;

reset role;

-- F5. Les valeurs de A et de B n'ont pas bougé après toutes ces tentatives.
do $$
begin
  if (select solde_initial from public.entreprises where id = '48180000-0000-0000-0000-000000000001') <> 111000
     or (select date_solde_initial from public.entreprises where id = '48180000-0000-0000-0000-000000000001') <> date '2026-04-30'
     or (select solde_initial from public.entreprises where id = '48190000-0000-0000-0000-000000000001') <> 777000
     or (select date_solde_initial from public.entreprises where id = '48190000-0000-0000-0000-000000000001') <> date '2026-05-31' then
    raise exception 'Un solde ou une date a été modifié malgré les refus';
  end if;
  raise notice 'OK — soldes et dates de A et de B inchangés après toutes les tentatives interdites';
end $$;

rollback;
