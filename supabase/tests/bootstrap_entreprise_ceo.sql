-- Test adversarial de la RPC public.creer_entreprise_et_ceo (Module 4.1).
--
-- Preuve exigée par docs/briefs/module-4.1-authentification.md : un même
-- compte ne doit jamais pouvoir créer une deuxième entreprise ni se
-- rattacher deux fois, et aucune entreprise orpheline ne doit apparaître
-- entre les deux tentatives. Depuis la confirmation d'e-mail, le 2e appel
-- (lien rouvert, double clic) est idempotent : il renvoie la même
-- entreprise au lieu de lever une erreur.
--
-- Exécution : docker exec -i supabase_db_<projet> psql -U postgres
--             -v ON_ERROR_STOP=1 -f supabase/tests/bootstrap_entreprise_ceo.sql

set client_min_messages to warning;

begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "d0000000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
declare
  v_entreprises_avant int;
  v_entreprises_apres_1er_appel int;
  v_entreprises_apres_2e_appel int;
  v_entreprise_id uuid;
  v_entreprise_2e_appel uuid;
  v_utilisateurs_count int;
begin
  select count(*) into v_entreprises_avant from public.entreprises;

  -- 1er appel : doit réussir et créer entreprise + CEO.
  select public.creer_entreprise_et_ceo(
    'Nouvelle Entreprise Test',
    'Services',
    'Nouveau CEO'
  ) into v_entreprise_id;

  if v_entreprise_id is null then
    raise exception 'ECHEC : la RPC n''a renvoyé aucun id d''entreprise au 1er appel';
  end if;

  select count(*) into v_entreprises_apres_1er_appel from public.entreprises;
  if v_entreprises_apres_1er_appel <> v_entreprises_avant + 1 then
    raise exception 'ECHEC : le 1er appel n''a pas créé exactement 1 entreprise (avant=%, après=%)',
      v_entreprises_avant, v_entreprises_apres_1er_appel;
  end if;

  select count(*) into v_utilisateurs_count
  from public.utilisateurs
  where id = 'd0000000-0000-0000-0000-0000000000c1'
    and role = 'ceo'
    and entreprise_id = v_entreprise_id;

  if v_utilisateurs_count <> 1 then
    raise exception 'ECHEC : le CEO n''a pas été créé correctement au 1er appel';
  end if;

  -- 2e appel, même compte : idempotent — renvoie la même entreprise, sans
  -- en créer une seconde et sans erreur (double clic, lien de confirmation
  -- rouvert).
  v_entreprise_2e_appel := public.creer_entreprise_et_ceo(
    'Deuxieme Entreprise Frauduleuse',
    'Autre secteur',
    'Second CEO'
  );

  if v_entreprise_2e_appel is distinct from v_entreprise_id then
    raise exception 'IDEMPOTENCE ROMPUE : le 2e appel a renvoyé % au lieu de %', v_entreprise_2e_appel, v_entreprise_id;
  end if;

  select count(*) into v_entreprises_apres_2e_appel from public.entreprises;
  if v_entreprises_apres_2e_appel <> v_entreprises_apres_1er_appel then
    raise exception 'ENTREPRISE ORPHELINE : le 2e appel (rejeté) a quand même créé une ligne entreprises (avant=%, après=%)',
      v_entreprises_apres_1er_appel, v_entreprises_apres_2e_appel;
  end if;

  if exists (select 1 from public.entreprises where nom = 'Deuxieme Entreprise Frauduleuse')
     or (select nom from public.utilisateurs where id = 'd0000000-0000-0000-0000-0000000000c1') <> 'Nouveau CEO' then
    raise exception 'IDEMPOTENCE ROMPUE : le 2e appel a modifié ou créé quelque chose';
  end if;

  raise notice 'OK — bootstrap entreprise+CEO : 1er appel réussi, 2e appel idempotent (même entreprise, rien créé ni modifié)';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- Compte issu d'une invitation (auth.users.invited_at non nul) :
--  a) orphelin (aucune ligne utilisateurs, cas connu du Module 4.1) :
--     l'appel est rejeté et aucune entreprise n'est créée, même avec des
--     noms bien formés ;
--  b) invité DÉJÀ rattaché (comptable normal) : l'appel reste idempotent
--     (renvoie son entreprise, ne crée rien).
-- ---------------------------------------------------------------------
begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, invited_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values (
  '00000000-0000-0000-0000-000000000000', 'd0000000-0000-0000-0000-0000000000c9',
  'authenticated', 'authenticated', 'orphelin-invite@test.besmart.local',
  crypt('mot-de-passe-test', gen_salt('bf')), now(), now(), '{}',
  '{"nom_entreprise": "Entreprise Forgee", "nom_ceo": "Orphelin"}',
  now(), now(), '', '', '', ''
);

set local role authenticated;
set local request.jwt.claims = '{"sub": "d0000000-0000-0000-0000-0000000000c9", "role": "authenticated"}';

do $$
declare
  v_entreprises_avant int;
  v_entreprises_apres int;
begin
  select count(*) into v_entreprises_avant from public.entreprises;

  begin
    perform public.creer_entreprise_et_ceo('Entreprise Forgee', 'Test', 'Orphelin');
    raise exception 'GARDE-FOU ROMPU : un compte issu d''une invitation, sans entreprise, a pu en créer une';
  exception
    when others then
      if sqlerrm not like '%créé par invitation%contactez votre gérant%' then
        raise exception 'ECHEC INATTENDU (orphelin invité) : %', sqlerrm;
      end if;
      raise notice 'ORPHELIN INVITE : rejeté — "%"', sqlerrm;
  end;

  select count(*) into v_entreprises_apres from public.entreprises;
  if v_entreprises_apres <> v_entreprises_avant then
    raise exception 'ENTREPRISE CREEE : avant=%, après=%', v_entreprises_avant, v_entreprises_apres;
  end if;

  if exists (select 1 from public.utilisateurs where id = 'd0000000-0000-0000-0000-0000000000c9')
     or exists (select 1 from public.entreprises where nom = 'Entreprise Forgee') then
    raise exception 'ORPHELIN : un profil ou une entreprise a été créé malgré le rejet';
  end if;

  raise notice 'OK — compte invité sans entreprise : appel rejeté, aucune entreprise ni profil créé';
end $$;

rollback;

begin;

-- Comptable invité déjà rattaché (invited_at posé comme après une vraie invitation).
update auth.users set invited_at = now() where id = 'a1000000-0000-0000-0000-0000000000c2';

set local role authenticated;
set local request.jwt.claims = '{"sub": "a1000000-0000-0000-0000-0000000000c2", "role": "authenticated"}';

do $$
declare
  v_entreprises_avant int;
  v_retour uuid;
begin
  select count(*) into v_entreprises_avant from public.entreprises;

  v_retour := public.creer_entreprise_et_ceo('Autre', 'Autre', 'Autre');

  if v_retour is distinct from 'a0000000-0000-0000-0000-000000000001'::uuid then
    raise exception 'IDEMPOTENCE ROMPUE pour un invité rattaché : retour %', v_retour;
  end if;
  if (select count(*) from public.entreprises) <> v_entreprises_avant then
    raise exception 'ENTREPRISE CREEE pour un invité déjà rattaché';
  end if;

  raise notice 'OK — comptable invité déjà rattaché : appel idempotent (son entreprise, rien créé)';
end $$;

rollback;
