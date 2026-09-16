-- Tests adversariaux Module 4.4 — Journal des transactions réelles.
-- Voir docs/briefs/module-4.4-journal-transactions.md, section 5.

set client_min_messages to warning;

-- ---------------------------------------------------------------------
-- 1. Le CEO ne peut ni créer, modifier, ni supprimer de transaction —
--    mais lit bien celles de son entreprise (témoin positif).
-- ---------------------------------------------------------------------
begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "a1000000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
declare
  v_transaction_id uuid := 'a7000000-0000-0000-0000-000000000001';
begin
  begin
    insert into public.transactions (entreprise_id, date, description, categorie_id, type, montant, mode_paiement)
    values ('a0000000-0000-0000-0000-000000000001', current_date, 'Créée par CEO', 'a2000000-0000-0000-0000-000000000003', 'entree', 1000, 'cash');
    raise exception 'RLS ROMPUE : le CEO a pu créer une transaction';
  exception when insufficient_privilege or others then null;
  end;

  -- Aucun GRANT update/delete n'existe sur cette table, pour personne :
  -- Postgres rejette donc avec "permission denied" avant même d'évaluer
  -- RLS, plus strict qu'un simple "0 ligne affectée".
  begin
    update public.transactions set description = 'Modifiée par CEO' where id = v_transaction_id;
    raise exception 'RLS ROMPUE : le CEO a pu modifier une transaction';
  exception when insufficient_privilege or others then null;
  end;

  begin
    delete from public.transactions where id = v_transaction_id;
    raise exception 'RLS ROMPUE : le CEO a pu supprimer une transaction';
  exception when insufficient_privilege or others then null;
  end;

  perform 1 from public.transactions where id = v_transaction_id;
  if not found then
    raise exception 'FAUX POSITIF SUSPECT : le CEO ne voit pas une transaction de sa propre entreprise';
  end if;

  raise notice 'OK — le CEO ne peut ni créer, ni modifier, ni supprimer une transaction (mais la lit)';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 2. Le comptable de l'entreprise A ne voit/modifie rien de l'entreprise B.
-- ---------------------------------------------------------------------
begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "a1000000-0000-0000-0000-0000000000c2", "role": "authenticated"}';

do $$
declare
  v_count int;
  v_transaction_b_id uuid := 'b7000000-0000-0000-0000-000000000001';
begin
  select count(*) into v_count from public.transactions where entreprise_id = 'b0000000-0000-0000-0000-000000000001';
  if v_count <> 0 then
    raise exception 'ISOLATION ROMPUE : le comptable A voit % transaction(s) de l''entreprise B', v_count;
  end if;

  begin
    update public.transactions set description = 'Modifiée par comptable A' where id = v_transaction_b_id;
    raise exception 'ISOLATION ROMPUE : le comptable A a pu modifier une transaction de l''entreprise B';
  exception when insufficient_privilege or others then null;
  end;

  raise notice 'OK — le comptable A ne voit/modifie rien des transactions de l''entreprise B';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 3. Cohérence type / catégorie : entree <-> revenu, sortie <-> fixe|variable.
-- ---------------------------------------------------------------------
begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "a1000000-0000-0000-0000-0000000000c2", "role": "authenticated"}';

do $$
begin
  -- entree avec catégorie fixe : rejetée.
  begin
    insert into public.transactions (entreprise_id, date, description, categorie_id, type, montant, mode_paiement)
    values ('a0000000-0000-0000-0000-000000000001', current_date, 'Incohérente', 'a2000000-0000-0000-0000-000000000001', 'entree', 1000, 'cash');
    raise exception 'GARDE-FOU ROMPU : une transaction entree a pu être rattachée à une catégorie fixe';
  exception
    when others then
      if sqlerrm not like '%type revenu%' then
        raise exception 'ECHEC INATTENDU (entree/fixe) : %', sqlerrm;
      end if;
  end;

  -- sortie avec catégorie revenu : rejetée.
  begin
    insert into public.transactions (entreprise_id, date, description, categorie_id, type, montant, mode_paiement)
    values ('a0000000-0000-0000-0000-000000000001', current_date, 'Incohérente', 'a2000000-0000-0000-0000-000000000003', 'sortie', 1000, 'cash');
    raise exception 'GARDE-FOU ROMPU : une transaction sortie a pu être rattachée à une catégorie revenu';
  exception
    when others then
      if sqlerrm not like '%fixe ou variable%' then
        raise exception 'ECHEC INATTENDU (sortie/revenu) : %', sqlerrm;
      end if;
  end;

  raise notice 'OK — cohérence type/catégorie appliquée par le trigger';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 4. Impossible de rattacher une catégorie ou une ligne_revenu_prevu d'une
--    autre entreprise, même avec son propre entreprise_id sur la ligne.
-- ---------------------------------------------------------------------
begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "a1000000-0000-0000-0000-0000000000c2", "role": "authenticated"}';

do $$
begin
  -- Catégorie de l'entreprise B, entreprise_id du CEO... du comptable A ici.
  begin
    insert into public.transactions (entreprise_id, date, description, categorie_id, type, montant, mode_paiement)
    values ('a0000000-0000-0000-0000-000000000001', current_date, 'Frauduleuse', 'b2000000-0000-0000-0000-000000000002', 'entree', 1000, 'cash');
    raise exception 'GARDE-FOU ROMPU : une transaction a pu référencer une catégorie d''une autre entreprise';
  exception
    when others then
      if sqlerrm not like '%même entreprise%' then
        raise exception 'ECHEC INATTENDU (catégorie étrangère) : %', sqlerrm;
      end if;
  end;

  -- ligne_revenu_prevu de l'entreprise B (existe réellement, cf. seed) :
  -- la catégorie et l'entreprise_id sont corrects pour A, seule la ligne
  -- de revenu prévu appartient à B — c'est bien le trigger qui doit
  -- l'attraper, pas une simple violation de clé étrangère.
  begin
    insert into public.transactions (entreprise_id, date, description, categorie_id, type, montant, mode_paiement, ligne_revenu_prevu_id)
    values ('a0000000-0000-0000-0000-000000000001', current_date, 'Frauduleuse', 'a2000000-0000-0000-0000-000000000003', 'entree', 1000, 'cash', 'b6000000-0000-0000-0000-000000000001');
    raise exception 'GARDE-FOU ROMPU : une transaction a pu référencer une ligne de revenu prévu d''une autre entreprise';
  exception
    when others then
      if sqlerrm not like '%même entreprise%' then
        raise exception 'ECHEC INATTENDU (ligne_revenu_prevu étrangère) : %', sqlerrm;
      end if;
  end;

  raise notice 'OK — impossible de référencer une catégorie ou une ligne de revenu prévu d''une autre entreprise';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 5. Rapprochement automatique : ligne_revenu_prevu passe à 'ok'.
-- ---------------------------------------------------------------------
begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "a1000000-0000-0000-0000-0000000000c2", "role": "authenticated"}';

do $$
declare
  v_statut text;
begin
  select statut into v_statut from public.lignes_revenu_prevu where id = 'a6000000-0000-0000-0000-000000000001';
  if v_statut <> 'en_attente' then
    raise exception 'PRECONDITION MANQUANTE : la ligne de revenu prévu n''est pas en_attente au départ (statut=%)', v_statut;
  end if;

  insert into public.transactions (entreprise_id, date, description, categorie_id, type, montant, mode_paiement, ligne_revenu_prevu_id)
  values (
    'a0000000-0000-0000-0000-000000000001', current_date, 'Encaissement ventes du mois',
    'a2000000-0000-0000-0000-000000000003', 'entree', 800000, 'virement',
    'a6000000-0000-0000-0000-000000000001'
  );

  select statut into v_statut from public.lignes_revenu_prevu where id = 'a6000000-0000-0000-0000-000000000001';
  if v_statut <> 'ok' then
    raise exception 'RAPPROCHEMENT ECHOUE : statut attendu ok, obtenu %', v_statut;
  end if;

  raise notice 'OK — le rapprochement automatique passe bien la ligne de revenu prévu à ok';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 6. saisi_par forgé par le client est écrasé par l'appelant réel.
-- ---------------------------------------------------------------------
begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "a1000000-0000-0000-0000-0000000000c2", "role": "authenticated"}';

do $$
declare
  v_saisi_par uuid;
  v_transaction_id uuid;
begin
  insert into public.transactions (entreprise_id, date, description, categorie_id, type, montant, mode_paiement, saisi_par)
  values (
    'a0000000-0000-0000-0000-000000000001', current_date, 'Tentative usurpation',
    'a2000000-0000-0000-0000-000000000003', 'entree', 1000, 'cash',
    'a1000000-0000-0000-0000-0000000000c1' -- id du CEO, pas de l'appelant
  )
  returning id into v_transaction_id;

  select saisi_par into v_saisi_par from public.transactions where id = v_transaction_id;

  if v_saisi_par <> 'a1000000-0000-0000-0000-0000000000c2' then
    raise exception 'USURPATION REUSSIE : saisi_par = % au lieu de l''appelant réel', v_saisi_par;
  end if;

  raise notice 'OK — saisi_par forgé par le client est écrasé par l''appelant réel (comptable A)';
end $$;

rollback;
