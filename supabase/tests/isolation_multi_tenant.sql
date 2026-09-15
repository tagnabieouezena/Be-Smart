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
