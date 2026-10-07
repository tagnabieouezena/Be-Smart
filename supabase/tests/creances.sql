-- Tests Module 4.5 — Suivi des créances clients.
-- Voir docs/briefs/Module-4.5-Creances-Clients.md, sections 5 (calculs
-- chiffrés) et 6 (adversariaux). Le test de concurrence (deux sessions
-- psql) est dans supabase/tests/creances_concurrence.sh.
-- Chaque bloc s'exécute en BEGIN … ROLLBACK ; les appels se font en
-- utilisateur authentifié réel (role authenticated + sub), jamais en
-- service_role.

set client_min_messages to notice;

-- Jeu de données commun (entreprise dédiée F) : créé par une fonction
-- temporaire de session, appelée en début de chaque bloc AVANT de changer
-- de rôle. Les paiements sont insérés hors contexte JWT (saisi_par explicite).
create function pg_temp.setup_creances() returns void
language plpgsql as $$
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, email_change,
    email_change_token_new, recovery_token
  ) values
    ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-0000000000c1', 'authenticated', 'authenticated',
     'comptable-f@test.besmart.local', crypt('mot-de-passe-test', gen_salt('bf')), now(), '{}', '{}', now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', 'f1000000-0000-0000-0000-0000000000c2', 'authenticated', 'authenticated',
     'ceo-f@test.besmart.local', crypt('mot-de-passe-test', gen_salt('bf')), now(), '{}', '{}', now(), now(), '', '', '', '');

  insert into public.entreprises (id, nom, secteur, devise, solde_initial)
  values ('f0000000-0000-0000-0000-000000000001', 'Entreprise Creances F', 'Test', 'FCFA', 0);

  insert into public.utilisateurs (id, nom, email, role, entreprise_id) values
    ('f1000000-0000-0000-0000-0000000000c1', 'Comptable F', 'comptable-f@test.besmart.local', 'comptable', 'f0000000-0000-0000-0000-000000000001'),
    ('f1000000-0000-0000-0000-0000000000c2', 'CEO F', 'ceo-f@test.besmart.local', 'ceo', 'f0000000-0000-0000-0000-000000000001');

  insert into public.categories (id, entreprise_id, libelle, type) values
    ('f2000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000001', 'Ventes', 'revenu'),
    ('f2000000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-000000000001', 'Loyer', 'fixe');

  insert into public.creances (id, entreprise_id, client, montant_du, date_facturation, echeance, saisi_par) values
    ('f8000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000001', 'Alpha',   300000, '2026-08-01', '2026-08-31', 'f1000000-0000-0000-0000-0000000000c1'),
    ('f8000000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-000000000001', 'Beta',    150000, '2026-09-20', '2026-10-20', 'f1000000-0000-0000-0000-0000000000c1'),
    ('f8000000-0000-0000-0000-000000000003', 'f0000000-0000-0000-0000-000000000001', 'Gamma',    80000, '2026-07-01', '2026-07-31', 'f1000000-0000-0000-0000-0000000000c1'),
    ('f8000000-0000-0000-0000-000000000004', 'f0000000-0000-0000-0000-000000000001', 'Delta',    50000, '2026-06-01', '2026-06-30', 'f1000000-0000-0000-0000-0000000000c1'),
    ('f8000000-0000-0000-0000-000000000005', 'f0000000-0000-0000-0000-000000000001', 'Epsilon',  60000, '2026-09-01', '2026-09-30', 'f1000000-0000-0000-0000-0000000000c1');

  insert into public.transactions (entreprise_id, date, description, categorie_id, type, montant, mode_paiement, saisi_par, creance_id) values
    ('f0000000-0000-0000-0000-000000000001', '2026-09-10', 'Encaissement Alpha', 'f2000000-0000-0000-0000-000000000001', 'entree', 100000, 'virement',
     'f1000000-0000-0000-0000-0000000000c1', 'f8000000-0000-0000-0000-000000000001'),
    ('f0000000-0000-0000-0000-000000000001', '2026-08-05', 'Encaissement Gamma', 'f2000000-0000-0000-0000-000000000001', 'entree', 80000, 'cash',
     'f1000000-0000-0000-0000-0000000000c1', 'f8000000-0000-0000-0000-000000000003');
end $$;

-- ---------------------------------------------------------------------
-- 0. Propriétés de sécurité : security invoker, search_path, ACL réelles.
-- ---------------------------------------------------------------------
begin;

do $$
declare
  v_nom text;
  v_definer boolean;
  v_config text[];
begin
  foreach v_nom in array array['creances_situation(date)', 'creances_balance_agee(date)'] loop
    select prosecdef, proconfig into v_definer, v_config
    from pg_proc where oid = ('public.' || v_nom)::regprocedure;

    if v_definer then
      raise exception '% ne doit jamais être security definer', v_nom;
    end if;
    if not ('search_path=public' = any (coalesce(v_config, '{}'))) then
      raise exception '% doit fixer search_path = public (config : %)', v_nom, v_config;
    end if;
  end loop;

  -- Une fonction Postgres est exécutable par PUBLIC par défaut : aucune
  -- entrée PUBLIC (grantee 0) ni anon ne doit subsister sur les ACL.
  if exists (
    select 1
    from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where p.proname in ('creances_situation', 'creances_balance_agee')
      and (a.grantee = 0 or a.grantee = 'anon'::regrole)
  ) then
    raise exception 'ACL : creances_situation / creances_balance_agee exécutables par PUBLIC ou anon';
  end if;

  if not has_function_privilege('authenticated', 'public.creances_situation(date)', 'execute')
     or not has_function_privilege('authenticated', 'public.creances_balance_agee(date)', 'execute') then
    raise exception 'authenticated doit pouvoir exécuter les deux fonctions';
  end if;

  raise notice 'OK — fonctions créances en security invoker, search_path fixé, aucun droit PUBLIC/anon, authenticated autorisé';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 1. Tests chiffrés, date de référence 2026-10-15 (comptable F), suivis des
--    adversariaux 1, 3, 5, 6 sur la même entreprise, puis du cas
--    « paiement de 200 000 sur C1 ».
-- ---------------------------------------------------------------------
begin;

select pg_temp.setup_creances();

set local role authenticated;
set local request.jwt.claims = '{"sub": "f1000000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

-- 1a. creances_situation('2026-10-15') : créance par créance.
do $$
declare
  r record;
  v_attendu record;
  v_nb int := 0;
begin
  for v_attendu in
    select * from (values
      ('Alpha',   100000::numeric, 200000::numeric, 'en_retard',  45,  '31_60'),
      ('Beta',    0,               150000,          'en_attente',  0,  'non_echue'),
      ('Gamma',   80000,           0,               'paye',        0,  null),
      ('Delta',   0,               50000,           'en_retard', 107,  'plus_60'),
      ('Epsilon', 0,               60000,           'en_retard',  15,  '1_30')
    ) as t(client, encaisse, reste, statut, jours, tranche)
  loop
    select * into r from public.creances_situation('2026-10-15') s where s.client = v_attendu.client;

    raise notice '% : encaissé attendu % | obtenu % ; reste attendu % | obtenu % ; statut attendu % | obtenu % ; jours attendu % | obtenu % ; tranche attendu % | obtenu %',
      v_attendu.client,
      v_attendu.encaisse, r.montant_encaisse, v_attendu.reste, r.reste_du,
      v_attendu.statut, r.statut, v_attendu.jours, r.jours_retard,
      coalesce(v_attendu.tranche, 'null'), coalesce(r.tranche, 'null');

    if r.montant_encaisse is distinct from v_attendu.encaisse
       or r.reste_du is distinct from v_attendu.reste
       or r.statut is distinct from v_attendu.statut
       or r.jours_retard is distinct from v_attendu.jours
       or r.tranche is distinct from v_attendu.tranche then
      raise exception 'SITUATION % : écart entre attendu et obtenu (voir notice ci-dessus)', v_attendu.client;
    end if;
    v_nb := v_nb + 1;
  end loop;

  if (select count(*) from public.creances_situation('2026-10-15')) <> 5 then
    raise exception 'creances_situation devrait renvoyer exactement 5 créances';
  end if;

  raise notice 'OK — creances_situation(2026-10-15) : 5 créances conformes (statut, encaissé, reste, jours, tranche)';
end $$;

-- 1b. creances_balance_agee('2026-10-15').
do $$
declare
  v_attendu record;
  v_obtenu numeric;
begin
  for v_attendu in
    select * from (values
      ('total',   'en_cours',  460000::numeric),
      ('tranche', 'non_echue', 150000),
      ('tranche', '1_30',       60000),
      ('tranche', '31_60',     200000),
      ('tranche', 'plus_60',    50000),
      ('mois',    '2026-06',    50000),
      ('mois',    '2026-08',   200000),
      ('mois',    '2026-09',    60000),
      ('mois',    '2026-10',   150000)
    ) as t(rubrique, cle, montant)
  loop
    select b.montant into v_obtenu from public.creances_balance_agee('2026-10-15') b
    where b.rubrique = v_attendu.rubrique and b.cle = v_attendu.cle;

    raise notice 'BALANCE % % : attendu % | obtenu %', v_attendu.rubrique, v_attendu.cle, v_attendu.montant, v_obtenu;

    if v_obtenu is distinct from v_attendu.montant then
      raise exception 'BALANCE % % : attendu %, obtenu %', v_attendu.rubrique, v_attendu.cle, v_attendu.montant, v_obtenu;
    end if;
  end loop;

  if (select count(*) from public.creances_balance_agee('2026-10-15')) <> 9 then
    raise exception 'creances_balance_agee devrait renvoyer exactement 9 lignes (1 total + 4 tranches + 4 mois)';
  end if;
  if (select sum(montant) from public.creances_balance_agee('2026-10-15') where rubrique = 'tranche') <> 460000 then
    raise exception 'La somme des tranches doit égaler le total en cours (460000)';
  end if;

  raise notice 'OK — creances_balance_agee(2026-10-15) : total 460000, tranches 150000/60000/200000/50000, 4 mois conformes';
end $$;

-- Adversarial 1 : surpaiement (200 001 sur C1, reste 200 000) rejeté.
-- Le paiement exact (200 000) est testé plus bas.
do $$
begin
  begin
    insert into public.transactions (entreprise_id, date, description, categorie_id, type, montant, mode_paiement, creance_id)
    values ('f0000000-0000-0000-0000-000000000001', '2026-10-15', 'Surpaiement', 'f2000000-0000-0000-0000-000000000001', 'entree', 200001, 'cash',
            'f8000000-0000-0000-0000-000000000001');
    raise exception 'GARDE-FOU ROMPU : un surpaiement de 200001 sur un reste de 200000 a été accepté';
  exception
    when others then
      if sqlerrm not like '%dépasse le reste dû : 200000 FCFA%' then
        raise exception 'ECHEC INATTENDU (surpaiement) : %', sqlerrm;
      end if;
      raise notice 'ADV1 surpaiement 200001 sur reste 200000 : rejeté — "%"', sqlerrm;
  end;

  raise notice 'OK — adversarial 1 : surpaiement rejeté';
end $$;

-- Adversarial 3 : une sortie liée à une créance est rejetée.
do $$
begin
  begin
    insert into public.transactions (entreprise_id, date, description, categorie_id, type, montant, mode_paiement, creance_id)
    values ('f0000000-0000-0000-0000-000000000001', '2026-10-15', 'Sortie liée', 'f2000000-0000-0000-0000-000000000002', 'sortie', 1000, 'cash',
            'f8000000-0000-0000-0000-000000000001');
    raise exception 'GARDE-FOU ROMPU : une transaction de type sortie a pu être liée à une créance';
  exception
    when others then
      if sqlerrm not like '%doit être de type entree%' then
        raise exception 'ECHEC INATTENDU (sortie liée) : %', sqlerrm;
      end if;
      raise notice 'ADV3 sortie liée à une créance : rejetée — "%"', sqlerrm;
  end;

  raise notice 'OK — adversarial 3 : sortie liée à une créance rejetée';
end $$;

-- Adversarial 5 : baisser montant_du de C1 sous l'encaissé (100 000) rejeté.
do $$
begin
  begin
    update public.creances set montant_du = 99999 where id = 'f8000000-0000-0000-0000-000000000001';
    raise exception 'GARDE-FOU ROMPU : montant_du a pu descendre sous le montant encaissé';
  exception
    when others then
      if sqlerrm not like '%inférieur au montant déjà encaissé%' then
        raise exception 'ECHEC INATTENDU (baisse montant_du) : %', sqlerrm;
      end if;
      raise notice 'ADV5 montant_du 99999 < encaissé 100000 : rejeté — "%"', sqlerrm;
  end;

  -- Témoin positif : descendre exactement au niveau de l'encaissé est permis.
  update public.creances set montant_du = 100000 where id = 'f8000000-0000-0000-0000-000000000001';
  if not found then
    raise exception 'TÉMOIN POSITIF ABSENT : la mise à jour de C1 à 100000 (= encaissé) aurait dû passer';
  end if;
  update public.creances set montant_du = 300000 where id = 'f8000000-0000-0000-0000-000000000001';

  raise notice 'OK — adversarial 5 : montant_du sous l''encaissé rejeté (égal à l''encaissé accepté)';
end $$;

-- Cas complémentaire : paiement de 200 000 sur C1 accepté → C1 payée, total 260 000.
do $$
declare
  r record;
  v_total numeric;
begin
  insert into public.transactions (entreprise_id, date, description, categorie_id, type, montant, mode_paiement, creance_id)
  values ('f0000000-0000-0000-0000-000000000001', '2026-10-15', 'Solde Alpha', 'f2000000-0000-0000-0000-000000000001', 'entree', 200000, 'virement',
          'f8000000-0000-0000-0000-000000000001');

  select * into r from public.creances_situation('2026-10-15') s where s.client = 'Alpha';
  select b.montant into v_total from public.creances_balance_agee('2026-10-15') b where b.rubrique = 'total';

  raise notice 'PAIEMENT 200000 sur C1 : statut attendu paye | obtenu %, reste attendu 0 | obtenu %, total en cours attendu 260000 | obtenu %',
    r.statut, r.reste_du, v_total;

  if r.statut <> 'paye' or r.reste_du <> 0 or r.tranche is not null or v_total <> 260000 then
    raise exception 'PAIEMENT SOLDE : C1 devrait être payée (reste 0, tranche null) et le total en cours 260000';
  end if;

  -- Une créance soldée n'accepte plus aucun paiement (reste 0).
  begin
    insert into public.transactions (entreprise_id, date, description, categorie_id, type, montant, mode_paiement, creance_id)
    values ('f0000000-0000-0000-0000-000000000001', '2026-10-15', 'Surpaiement soldé', 'f2000000-0000-0000-0000-000000000001', 'entree', 1, 'cash',
            'f8000000-0000-0000-0000-000000000001');
    raise exception 'GARDE-FOU ROMPU : un paiement a été accepté sur une créance soldée';
  exception
    when others then
      if sqlerrm not like '%dépasse le reste dû : 0 FCFA%' then
        raise exception 'ECHEC INATTENDU (créance soldée) : %', sqlerrm;
      end if;
  end;

  raise notice 'OK — paiement de 200000 accepté : C1 payée, total en cours 260000, plus aucun paiement possible';
end $$;

-- Adversarial 6 : supprimer une créance avec paiement rejeté ; supprimer C2 (sans paiement) accepté.
do $$
begin
  begin
    delete from public.creances where id = 'f8000000-0000-0000-0000-000000000001';
    raise exception 'GARDE-FOU ROMPU : une créance avec paiement lié a pu être supprimée';
  exception
    when foreign_key_violation then
      raise notice 'ADV6 suppression de C1 (paiements liés) : rejetée — foreign_key_violation';
  end;

  delete from public.creances where id = 'f8000000-0000-0000-0000-000000000002';
  if not found then
    raise exception 'TÉMOIN POSITIF ABSENT : la suppression de C2 (sans paiement) aurait dû passer';
  end if;
  if exists (select 1 from public.creances where id = 'f8000000-0000-0000-0000-000000000002') then
    raise exception 'C2 devrait avoir disparu';
  end if;

  raise notice 'OK — adversarial 6 : suppression refusée avec paiement, acceptée sans paiement (C2)';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 1bis. Suppression d'une créance ayant un paiement, en service_role
--       (donc HORS RLS) : rejetée par la clé étrangère
--       transactions_creance_id_fkey (on delete restrict) ; la transaction
--       comme la créance existent toujours après.
-- ---------------------------------------------------------------------
begin;

select pg_temp.setup_creances();

set local role service_role;

do $$
declare
  v_contrainte text;
  v_transactions int;
  v_creance int;
begin
  begin
    delete from public.creances where id = 'f8000000-0000-0000-0000-000000000001';
    raise exception 'GARDE-FOU ROMPU : service_role a pu supprimer une créance ayant un paiement';
  exception
    when foreign_key_violation then
      get stacked diagnostics v_contrainte = constraint_name;
      if v_contrainte <> 'transactions_creance_id_fkey' then
        raise exception 'Rejet par la mauvaise contrainte : % (attendu transactions_creance_id_fkey)', v_contrainte;
      end if;
      raise notice 'SERVICE_ROLE suppression de C1 (paiement lié) : rejetée par la contrainte %', v_contrainte;
  end;

  select count(*) into v_transactions from public.transactions
  where creance_id = 'f8000000-0000-0000-0000-000000000001';
  select count(*) into v_creance from public.creances
  where id = 'f8000000-0000-0000-0000-000000000001';

  if v_transactions <> 1 or v_creance <> 1 then
    raise exception 'Après le rejet : % transaction(s) liée(s) (attendu 1) et % créance (attendu 1)', v_transactions, v_creance;
  end if;

  -- Témoin positif hors RLS : une créance sans paiement (C2) se supprime.
  delete from public.creances where id = 'f8000000-0000-0000-0000-000000000002';
  if not found then
    raise exception 'TÉMOIN POSITIF ABSENT : service_role devrait pouvoir supprimer C2 (sans paiement)';
  end if;

  raise notice 'OK — service_role (hors RLS) : suppression d''une créance payée rejetée par transactions_creance_id_fkey, transaction et créance toujours présentes ; C2 (sans paiement) supprimable';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 2. Créance partiellement payée NON échue : C6 (100 000, échéance
--    2026-10-31, paiement de 30 000), date de référence 2026-10-01.
-- ---------------------------------------------------------------------
begin;

select pg_temp.setup_creances();

set local role authenticated;
set local request.jwt.claims = '{"sub": "f1000000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
declare
  r record;
begin
  insert into public.creances (id, entreprise_id, client, montant_du, date_facturation, echeance)
  values ('f8000000-0000-0000-0000-000000000006', 'f0000000-0000-0000-0000-000000000001', 'Zeta', 100000, '2026-09-15', '2026-10-31');

  insert into public.transactions (entreprise_id, date, description, categorie_id, type, montant, mode_paiement, creance_id)
  values ('f0000000-0000-0000-0000-000000000001', '2026-09-25', 'Acompte Zeta', 'f2000000-0000-0000-0000-000000000001', 'entree', 30000, 'mobile_money',
          'f8000000-0000-0000-0000-000000000006');

  select * into r from public.creances_situation('2026-10-01') s where s.client = 'Zeta';

  raise notice 'C6 (ref 2026-10-01) : statut attendu partiellement_paye | obtenu %, encaissé attendu 30000 | obtenu %, reste attendu 70000 | obtenu %, tranche attendu non_echue | obtenu %, jours attendu 0 | obtenu %',
    r.statut, r.montant_encaisse, r.reste_du, r.tranche, r.jours_retard;

  if r.statut <> 'partiellement_paye' or r.montant_encaisse <> 30000 or r.reste_du <> 70000
     or r.tranche <> 'non_echue' or r.jours_retard <> 0 then
    raise exception 'C6 : attendu partiellement_paye / 30000 / 70000 / non_echue / 0';
  end if;

  raise notice 'OK — créance partiellement payée non échue : partiellement_paye, reste 70000, tranche non_echue';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 3. Adversarial 4 — une transaction liée à une créance d'une autre
--    entreprise est rejetée PAR LE TRIGGER (id réel de B, connu en base),
--    y compris quand la RLS est contournée (rôle propriétaire, sans JWT).
-- ---------------------------------------------------------------------
begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "a1000000-0000-0000-0000-0000000000c2", "role": "authenticated"}';

do $$
begin
  begin
    insert into public.transactions (entreprise_id, date, description, categorie_id, type, montant, mode_paiement, creance_id)
    values ('a0000000-0000-0000-0000-000000000001', '2026-10-15', 'Créance étrangère', 'a2000000-0000-0000-0000-000000000003', 'entree', 1000, 'cash',
            'b8000000-0000-0000-0000-000000000001');
    raise exception 'GARDE-FOU ROMPU : le comptable A a pu lier une transaction à une créance de B';
  exception
    when others then
      if sqlerrm not like '%même entreprise%' then
        raise exception 'ECHEC INATTENDU (créance étrangère, comptable A) : %', sqlerrm;
      end if;
      raise notice 'ADV4 comptable A → créance de B : rejeté — "%"', sqlerrm;
  end;
end $$;

reset role;
set local request.jwt.claims = '{}';

do $$
begin
  -- Sans RLS (propriétaire, auth.uid() NULL) : la créance de B est visible,
  -- seul le trigger peut refuser.
  begin
    insert into public.transactions (entreprise_id, date, description, categorie_id, type, montant, mode_paiement, saisi_par, creance_id)
    values ('a0000000-0000-0000-0000-000000000001', '2026-10-15', 'Créance étrangère (RLS contournée)', 'a2000000-0000-0000-0000-000000000003', 'entree', 1000, 'cash',
            'a1000000-0000-0000-0000-0000000000c2', 'b8000000-0000-0000-0000-000000000001');
    raise exception 'GARDE-FOU ROMPU : le trigger a laissé passer une créance d''une autre entreprise (RLS contournée)';
  exception
    when others then
      if sqlerrm not like '%même entreprise%' then
        raise exception 'ECHEC INATTENDU (créance étrangère, RLS contournée) : %', sqlerrm;
      end if;
      raise notice 'ADV4 RLS contournée (propriétaire) → créance de B : rejeté par le trigger — "%"', sqlerrm;
  end;

  raise notice 'OK — adversarial 4 : créance d''une autre entreprise rejetée par le trigger, avec et sans RLS';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 4. Adversarial 7 — le CEO ne crée, ne modifie, ne supprime aucune
--    créance, mais lit bien celles de son entreprise (témoin positif).
-- ---------------------------------------------------------------------
begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "a1000000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
declare
  v_creance_id uuid := 'a8000000-0000-0000-0000-000000000001';
  v_lignes int;
begin
  begin
    insert into public.creances (entreprise_id, client, montant_du, date_facturation, echeance)
    values ('a0000000-0000-0000-0000-000000000001', 'Créée par CEO', 1000, '2026-10-01', '2026-10-31');
    raise exception 'RLS ROMPUE : le CEO a pu créer une créance';
  exception when insufficient_privilege or others then
    if sqlerrm not like '%row-level security%' then
      raise exception 'ECHEC INATTENDU (CEO insert) : %', sqlerrm;
    end if;
  end;

  update public.creances set client = 'Modifiée par CEO' where id = v_creance_id;
  if found then
    raise exception 'RLS ROMPUE : le CEO a pu modifier une créance';
  end if;

  delete from public.creances where id = v_creance_id;
  if found then
    raise exception 'RLS ROMPUE : le CEO a pu supprimer une créance';
  end if;

  perform 1 from public.creances where id = v_creance_id;
  if not found then
    raise exception 'FAUX POSITIF SUSPECT : le CEO ne voit pas la créance de sa propre entreprise';
  end if;

  select count(*) into v_lignes from public.creances_situation('2026-10-15');
  if v_lignes <> 1 then
    raise exception 'CEO A : creances_situation devrait renvoyer 1 ligne (seed), obtenu %', v_lignes;
  end if;

  raise notice 'OK — adversarial 7 : le CEO ne peut ni créer, ni modifier, ni supprimer une créance (mais la lit, et les fonctions lui répondent)';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 5. Adversarial 8 — comptable et CEO de B ne voient rien des créances de A
--    (table et deux fonctions). Un comptable B est créé le temps du test.
-- ---------------------------------------------------------------------
begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values (
  '00000000-0000-0000-0000-000000000000', 'b1000000-0000-0000-0000-0000000000c2', 'authenticated', 'authenticated',
  'comptable-b@test.besmart.local', crypt('mot-de-passe-test', gen_salt('bf')), now(), '{}', '{}', now(), now(), '', '', '', ''
);
insert into public.utilisateurs (id, nom, email, role, entreprise_id)
values ('b1000000-0000-0000-0000-0000000000c2', 'Comptable B', 'comptable-b@test.besmart.local', 'comptable', 'b0000000-0000-0000-0000-000000000001');

set local role authenticated;

do $$
declare
  v_sub text;
  v_visibles int;
  v_de_a int;
  v_situation int;
  v_clients text[];
  v_total numeric;
begin
  foreach v_sub in array array['b1000000-0000-0000-0000-0000000000c2', 'b1000000-0000-0000-0000-0000000000c1'] loop
    perform set_config('request.jwt.claims', json_build_object('sub', v_sub, 'role', 'authenticated')::text, true);

    select count(*), count(*) filter (where entreprise_id = 'a0000000-0000-0000-0000-000000000001')
      into v_visibles, v_de_a from public.creances;
    if v_de_a <> 0 or v_visibles <> 1 then
      raise exception 'ISOLATION ROMPUE (table) pour % : % créance(s) visibles dont % de A', v_sub, v_visibles, v_de_a;
    end if;

    select count(*), array_agg(client) into v_situation, v_clients from public.creances_situation('2026-10-15');
    if v_situation <> 1 or v_clients <> array['Client Beta B'] then
      raise exception 'ISOLATION ROMPUE (creances_situation) pour % : % ligne(s), clients %', v_sub, v_situation, v_clients;
    end if;

    select montant into v_total from public.creances_balance_agee('2026-10-15') where rubrique = 'total';
    if v_total <> 70000 then
      raise exception 'ISOLATION ROMPUE (creances_balance_agee) pour % : total en cours % au lieu de 70000 (B seul)', v_sub, v_total;
    end if;

    raise notice 'OK — % : table 1 créance (la sienne), situation = {Client Beta B}, total en cours 70000 (aucune donnée de A)', v_sub;
  end loop;
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 6. Adversarial 9 — supervision Be Smart : zéro ligne (table + fonctions) ;
--    anon : refusé.
-- ---------------------------------------------------------------------
begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "c0000000-0000-0000-0000-000000000001", "role": "authenticated", "app_metadata": {"super_admin": true}}';

do $$
declare
  v_table int;
  v_situation int;
  v_balance int;
begin
  select count(*) into v_table from public.creances;
  select count(*) into v_situation from public.creances_situation('2026-10-15');
  select count(*) into v_balance from public.creances_balance_agee('2026-10-15');

  if v_table <> 0 or v_situation <> 0 or v_balance <> 0 then
    raise exception 'ISOLATION ROMPUE : supervision voit table %, situation %, balance % ligne(s)', v_table, v_situation, v_balance;
  end if;

  raise notice 'OK — supervision Be Smart : 0 ligne sur creances, creances_situation et creances_balance_agee';
end $$;

rollback;

begin;

set local role anon;
set local request.jwt.claims = '{"role": "anon"}';

do $$
begin
  begin
    perform * from public.creances;
    raise exception 'ACCES ANON : la table creances a pu être lue sans authentification';
  exception when insufficient_privilege then null;
  end;

  begin
    perform * from public.creances_situation('2026-10-15');
    raise exception 'ACCES ANON : creances_situation a pu être appelée sans authentification';
  exception when insufficient_privilege then null;
  end;

  begin
    perform * from public.creances_balance_agee('2026-10-15');
    raise exception 'ACCES ANON : creances_balance_agee a pu être appelée sans authentification';
  exception when insufficient_privilege then null;
  end;

  raise notice 'OK — anon : permission denied sur creances, creances_situation et creances_balance_agee';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 7. Adversarial 10 — saisi_par forgé à l'insert d'une créance : écrasé par
--    l'appelant réel (relu en base). En mise à jour, la forge est rejetée.
-- ---------------------------------------------------------------------
begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "a1000000-0000-0000-0000-0000000000c2", "role": "authenticated"}';

do $$
declare
  v_saisi_par uuid;
  v_id uuid;
begin
  insert into public.creances (entreprise_id, client, montant_du, date_facturation, echeance, saisi_par)
  values ('a0000000-0000-0000-0000-000000000001', 'Tentative usurpation', 1000, '2026-10-01', '2026-10-31',
          'a1000000-0000-0000-0000-0000000000c1') -- id du CEO, pas de l'appelant
  returning id into v_id;

  select saisi_par into v_saisi_par from public.creances where id = v_id;
  raise notice 'ADV10 saisi_par forgé = CEO (…c1) : relu en base = %', v_saisi_par;

  if v_saisi_par <> 'a1000000-0000-0000-0000-0000000000c2' then
    raise exception 'USURPATION REUSSIE : saisi_par = % au lieu de l''appelant réel', v_saisi_par;
  end if;

  begin
    update public.creances set saisi_par = 'a1000000-0000-0000-0000-0000000000c1' where id = v_id;
    raise exception 'GARDE-FOU ROMPU : saisi_par a pu être modifié après coup';
  exception when others then
    if sqlerrm not like '%saisi_par%immuable%' then
      raise exception 'ECHEC INATTENDU (update saisi_par) : %', sqlerrm;
    end if;
  end;

  begin
    update public.creances set entreprise_id = 'b0000000-0000-0000-0000-000000000001' where id = v_id;
    raise exception 'GARDE-FOU ROMPU : entreprise_id a pu être modifié après coup';
  exception when others then
    if sqlerrm not like '%entreprise_id%immuable%' and sqlerrm not like '%row-level security%' then
      raise exception 'ECHEC INATTENDU (update entreprise_id) : %', sqlerrm;
    end if;
  end;

  raise notice 'OK — adversarial 10 : saisi_par forgé écrasé par l''appelant réel (comptable A) ; saisi_par et entreprise_id immuables';
end $$;

rollback;
