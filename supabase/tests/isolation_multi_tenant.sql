-- Test d'isolation multi-tenant (adversarial, pas seulement "les tests passent").
--
-- Preuve exigée par docs/briefs/phase-0-fondations.md : le CEO de
-- l'entreprise A (« Boutique Test SARL ») ne peut ni lire ni modifier
-- aucune ligne de l'entreprise B (« Atelier Test SARL ») dans `utilisateurs`
-- ni `entreprises`, malgré une politique RLS en place.
--
-- Technique : on simule une requête authentifiée comme le fait PostgREST,
-- en positionnant le rôle Postgres `authenticated` et le GUC
-- `request.jwt.claims` (lu par auth.uid()/auth.jwt()), sans mot de passe réel.
--
-- Exécution : psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/isolation_multi_tenant.sql
-- Contre la base locale (`supabase db reset` doit avoir tourné avant, pour charger le seed).
-- Un `RAISE EXCEPTION` fait échouer le script (et donc la CI) si l'isolation est rompue.

set client_min_messages to warning;

-- ---------------------------------------------------------------------
-- Contexte : CEO de l'entreprise A
-- ---------------------------------------------------------------------
begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "a1000000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
declare
  v_count int;
begin
  -- 1. Lecture : le CEO A ne doit voir aucune ligne `utilisateurs` de l'entreprise B.
  select count(*) into v_count
  from public.utilisateurs
  where entreprise_id = 'b0000000-0000-0000-0000-000000000001';

  if v_count <> 0 then
    raise exception 'ISOLATION ROMPUE : le CEO A voit % ligne(s) utilisateurs de l''entreprise B', v_count;
  end if;

  -- 2. Lecture : le CEO A ne doit pas voir l'entreprise B elle-même.
  select count(*) into v_count
  from public.entreprises
  where id = 'b0000000-0000-0000-0000-000000000001';

  if v_count <> 0 then
    raise exception 'ISOLATION ROMPUE : le CEO A voit l''entreprise B dans public.entreprises';
  end if;

  -- 3. Écriture : le CEO A ne doit pas pouvoir renommer l'entreprise B.
  begin
    update public.entreprises
    set nom = 'Renommée par CEO A'
    where id = 'b0000000-0000-0000-0000-000000000001';

    if found then
      raise exception 'ISOLATION ROMPUE : le CEO A a pu modifier l''entreprise B';
    end if;
  end;

  -- 4. Écriture : le CEO A ne doit pas pouvoir modifier le CEO de l'entreprise B.
  begin
    update public.utilisateurs
    set nom = 'Renommé par CEO A'
    where id = 'b1000000-0000-0000-0000-0000000000c1';

    if found then
      raise exception 'ISOLATION ROMPUE : le CEO A a pu modifier un utilisateur de l''entreprise B';
    end if;
  end;

  -- 5. Écriture : le CEO A ne doit pas pouvoir créer un utilisateur rattaché à l'entreprise B.
  begin
    insert into public.utilisateurs (id, nom, email, role, entreprise_id)
    values (
      gen_random_uuid(),
      'Intrus créé par CEO A',
      'intrus@test.besmart.local',
      'comptable',
      'b0000000-0000-0000-0000-000000000001'
    );
    raise exception 'ISOLATION ROMPUE : le CEO A a pu créer un utilisateur dans l''entreprise B';
  exception
    when insufficient_privilege or others then
      -- attendu : la policy RLS (with check) doit rejeter l'insert.
      null;
  end;

  -- 6. Témoin positif : le CEO A voit bien SA propre entreprise et SES utilisateurs
  --    (preuve que le test n'échoue pas simplement parce que tout est bloqué).
  select count(*) into v_count
  from public.entreprises
  where id = 'a0000000-0000-0000-0000-000000000001';

  if v_count <> 1 then
    raise exception 'FAUX POSITIF SUSPECT : le CEO A ne voit pas sa propre entreprise (RLS trop restrictive ?)';
  end if;

  select count(*) into v_count
  from public.utilisateurs
  where entreprise_id = 'a0000000-0000-0000-0000-000000000001';

  if v_count <> 2 then
    raise exception 'FAUX POSITIF SUSPECT : le CEO A ne voit pas ses propres utilisateurs (attendu 2, trouvé %)', v_count;
  end if;

  raise notice 'OK — isolation entreprise A -> B vérifiée (lecture + écriture + insert bloqués)';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- Contexte : comptable de l'entreprise A — ne doit pas pouvoir créer de compte
-- ---------------------------------------------------------------------
begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "a1000000-0000-0000-0000-0000000000c2", "role": "authenticated"}';

do $$
begin
  begin
    insert into public.utilisateurs (id, nom, email, role, entreprise_id)
    values (
      gen_random_uuid(),
      'Compte créé par comptable',
      'nouveau@test.besmart.local',
      'comptable',
      'a0000000-0000-0000-0000-000000000001'
    );
    raise exception 'SEPARATION DES ROLES ROMPUE : un comptable a pu créer un compte utilisateur';
  exception
    when insufficient_privilege or others then
      null;
  end;

  raise notice 'OK — un comptable ne peut pas créer de compte utilisateur';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- Contexte : super-admin Be Smart — supervision lecture seule, non financière
-- ---------------------------------------------------------------------
begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "c0000000-0000-0000-0000-000000000001", "role": "authenticated", "app_metadata": {"super_admin": true}}';

do $$
declare
  v_count int;
begin
  -- Voit les deux entreprises via la vue de supervision (colonnes non financières).
  select count(*) into v_count from public.v_entreprises_supervision;
  if v_count <> 2 then
    raise exception 'SUPERVISION CASSEE : le super-admin devrait voir 2 entreprises via la vue, en voit %', v_count;
  end if;

  -- Ne voit RIEN sur la table de base (pas de policy super-admin dessus : le
  -- claim super_admin ne donne accès qu'à la vue restreinte en colonnes).
  select count(*) into v_count from public.entreprises;
  if v_count <> 0 then
    raise exception 'FUITE FINANCIERE : le super-admin voit % ligne(s) sur la table entreprises (colonnes financières incluses)', v_count;
  end if;

  raise notice 'OK — supervision Be Smart : lecture seule, non financière, via la vue uniquement';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- Audit des droits du rôle anon (défense en profondeur) : la RLS ne doit
-- pas être la seule barrière. Aucune table, vue, séquence ni fonction du
-- schéma public ne doit accorder le moindre droit à anon, et une future
-- table doit naître sans ces droits. Lecture des ACL réelles ; échoue si
-- une migration (ou les privilèges par défaut de l'image Supabase)
-- réintroduit un droit.
-- ---------------------------------------------------------------------
begin;

do $$
declare
  v_tables text;
  v_fonctions text;
  v_sequences text;
  v_effectifs text;
begin
  -- Tables et vues : droits explicites accordés à anon.
  select string_agg(table_name || ' [' || privileges || ']', ' ; ' order by table_name)
    into v_tables
  from (
    select table_name, string_agg(privilege_type, ',' order by privilege_type) as privileges
    from information_schema.role_table_grants
    where grantee = 'anon' and table_schema = 'public'
    group by table_name
  ) t;

  if v_tables is not null then
    raise exception 'DROITS ANON SUR TABLES/VUES : %', v_tables;
  end if;

  -- Droits effectifs (y compris hérités) de anon sur toute table, vue ou séquence.
  select string_agg(c.relname, ', ' order by c.relname)
    into v_effectifs
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and (
      (c.relkind in ('r', 'v', 'm', 'p', 'f')
        and has_table_privilege('anon', c.oid, 'select, insert, update, delete, truncate, references, trigger'))
      or (c.relkind = 'S'
        and has_sequence_privilege('anon', c.oid, 'usage, select, update'))
    );

  if v_effectifs is not null then
    raise exception 'DROITS ANON EFFECTIFS SUR : %', v_effectifs;
  end if;

  -- Séquences : droits explicites (information_schema n'a pas de vue dédiée aux grants de séquences par rôle).
  select string_agg(c.relname, ', ' order by c.relname)
    into v_sequences
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  cross join lateral aclexplode(coalesce(c.relacl, acldefault('S', c.relowner))) a
  where n.nspname = 'public' and c.relkind = 'S' and a.grantee = 'anon'::regrole;

  if v_sequences is not null then
    raise exception 'DROITS ANON SUR SEQUENCES : %', v_sequences;
  end if;

  -- Fonctions : droit EXECUTE accordé à anon OU au pseudo-rôle PUBLIC
  -- (que anon hérite), lu dans les ACL réelles.
  select string_agg(distinct routine_name || ' (' || grantee || ')', ', ' order by routine_name || ' (' || grantee || ')')
    into v_fonctions
  from information_schema.routine_privileges
  where grantee in ('anon', 'PUBLIC') and routine_schema = 'public';

  if v_fonctions is not null then
    raise exception 'DROIT EXECUTE ANON/PUBLIC SUR FONCTIONS : %', v_fonctions;
  end if;

  -- Droit effectif de anon, par n'importe quel chemin.
  select string_agg(p.proname, ', ' order by p.proname)
    into v_fonctions
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute');

  if v_fonctions is not null then
    raise exception 'DROIT EXECUTE EFFECTIF DE ANON SUR FONCTIONS : %', v_fonctions;
  end if;

  raise notice 'OK — audit anon : aucun droit sur les tables, vues, séquences et fonctions du schéma public';
end $$;

-- Une future table (créée ici par le rôle qui exécute les migrations) doit
-- naître sans aucun droit pour anon : privilèges par défaut verrouillés.
create table public.zz_audit_table_future (id int);
create view public.zz_audit_vue_future as select 1 as x;
create sequence public.zz_audit_sequence_future;
create function public.zz_audit_fonction_future() returns int language sql as 'select 1';

do $$
begin
  if has_table_privilege('anon', 'public.zz_audit_table_future', 'select, insert, update, delete, truncate, references, trigger')
     or has_table_privilege('anon', 'public.zz_audit_vue_future', 'select, insert, update, delete')
     or has_sequence_privilege('anon', 'public.zz_audit_sequence_future', 'usage, select, update') then
    raise exception 'PRIVILEGES PAR DEFAUT : une future table, vue ou séquence naît avec des droits pour anon';
  end if;

  if exists (
    select 1 from information_schema.routine_privileges
    where grantee in ('anon', 'PUBLIC') and routine_schema = 'public' and routine_name = 'zz_audit_fonction_future'
  ) or has_function_privilege('anon', 'public.zz_audit_fonction_future()', 'execute') then
    raise exception 'PRIVILEGES PAR DEFAUT : une future fonction naît avec EXECUTE pour anon ou PUBLIC';
  end if;

  raise notice 'OK — privilèges par défaut : une future table, vue, séquence ou fonction naît sans droit pour anon';
end $$;

rollback;
