-- Test adversarial de la RPC public.creer_entreprise_et_ceo (Module 4.1).
--
-- Preuve exigée par docs/briefs/module-4.1-authentification.md : un même
-- compte ne doit jamais pouvoir créer une deuxième entreprise ni se
-- rattacher deux fois, et aucune entreprise orpheline ne doit apparaître
-- entre les deux tentatives.
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

  -- 2e appel, même compte : doit échouer, sans créer d'entreprise orpheline.
  begin
    perform public.creer_entreprise_et_ceo(
      'Deuxieme Entreprise Frauduleuse',
      'Autre secteur',
      'Second CEO'
    );
    raise exception 'DOUBLE RATTACHEMENT AUTORISE : le 2e appel de la RPC aurait dû échouer';
  exception
    when others then
      if sqlerrm not like '%déjà rattaché%' then
        raise exception 'ECHEC INATTENDU au 2e appel (message reçu: %)', sqlerrm;
      end if;
      -- attendu : 'Ce compte est déjà rattaché à une entreprise.'
  end;

  select count(*) into v_entreprises_apres_2e_appel from public.entreprises;
  if v_entreprises_apres_2e_appel <> v_entreprises_apres_1er_appel then
    raise exception 'ENTREPRISE ORPHELINE : le 2e appel (rejeté) a quand même créé une ligne entreprises (avant=%, après=%)',
      v_entreprises_apres_1er_appel, v_entreprises_apres_2e_appel;
  end if;

  raise notice 'OK — bootstrap entreprise+CEO : 1er appel réussi, 2e appel rejeté, aucune entreprise orpheline';
end $$;

rollback;
