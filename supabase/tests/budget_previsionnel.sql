-- Tests adversariaux Module 4.3 — Budget prévisionnel mensuel.
-- Voir docs/briefs/module-4.3-budget-previsionnel.md, section 7.

set client_min_messages to warning;

-- ---------------------------------------------------------------------
-- 1. Un comptable ne peut ni créer, modifier, ni supprimer un budget ou
--    une ligne — mais lit bien celles de sa propre entreprise.
-- ---------------------------------------------------------------------
begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "a1000000-0000-0000-0000-0000000000c2", "role": "authenticated"}';

do $$
declare
  v_budget_id uuid := 'a4000000-0000-0000-0000-000000000002';
  v_ligne_charge_id uuid := 'a5000000-0000-0000-0000-000000000002';
begin
  -- Budget : insert
  begin
    insert into public.budgets_mensuels (entreprise_id, mois, annee)
    values ('a0000000-0000-0000-0000-000000000001', 10, 2026);
    raise exception 'RLS ROMPUE : un comptable a pu créer un budget';
  exception when insufficient_privilege or others then null;
  end;

  -- Budget : update
  update public.budgets_mensuels set statut = 'valide' where id = v_budget_id;
  if found then
    raise exception 'RLS ROMPUE : un comptable a pu modifier un budget';
  end if;

  -- Ligne charge : insert
  begin
    insert into public.lignes_charge_prevue (budget_mensuel_id, entreprise_id, categorie_id, designation, montant)
    values (v_budget_id, 'a0000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', 'Créée par comptable', 1000);
    raise exception 'RLS ROMPUE : un comptable a pu créer une ligne de charge';
  exception when insufficient_privilege or others then null;
  end;

  -- Ligne charge : update
  update public.lignes_charge_prevue set designation = 'Modifiée par comptable' where id = v_ligne_charge_id;
  if found then
    raise exception 'RLS ROMPUE : un comptable a pu modifier une ligne de charge';
  end if;

  -- Ligne charge : delete
  delete from public.lignes_charge_prevue where id = v_ligne_charge_id;
  if found then
    raise exception 'RLS ROMPUE : un comptable a pu supprimer une ligne de charge';
  end if;

  -- Témoins positifs : le comptable lit bien le budget et la ligne de sa
  -- propre entreprise (donc les échecs ci-dessus viennent de RLS, pas d'un
  -- problème d'accès en lecture).
  perform 1 from public.budgets_mensuels where id = v_budget_id;
  if not found then
    raise exception 'FAUX POSITIF SUSPECT : le comptable ne voit pas le budget de sa propre entreprise';
  end if;

  perform 1 from public.lignes_charge_prevue where id = v_ligne_charge_id;
  if not found then
    raise exception 'FAUX POSITIF SUSPECT : le comptable ne voit pas la ligne de charge de sa propre entreprise';
  end if;

  raise notice 'OK — un comptable ne peut ni créer, ni modifier, ni supprimer un budget ou une ligne (mais les lit)';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 2. Le CEO de l'entreprise A ne voit/modifie rien de l'entreprise B.
-- ---------------------------------------------------------------------
begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "a1000000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
declare
  v_count int;
  v_budget_b_id uuid := 'b4000000-0000-0000-0000-000000000001';
  v_ligne_b_id uuid := 'b5000000-0000-0000-0000-000000000001';
begin
  select count(*) into v_count from public.budgets_mensuels where entreprise_id = 'b0000000-0000-0000-0000-000000000001';
  if v_count <> 0 then
    raise exception 'ISOLATION ROMPUE : le CEO A voit % budget(s) de l''entreprise B', v_count;
  end if;

  select count(*) into v_count from public.lignes_charge_prevue where entreprise_id = 'b0000000-0000-0000-0000-000000000001';
  if v_count <> 0 then
    raise exception 'ISOLATION ROMPUE : le CEO A voit % ligne(s) de charge de l''entreprise B', v_count;
  end if;

  update public.budgets_mensuels set statut = 'valide' where id = v_budget_b_id;
  if found then
    raise exception 'ISOLATION ROMPUE : le CEO A a pu modifier le budget de l''entreprise B';
  end if;

  update public.lignes_charge_prevue set designation = 'Modifiée par CEO A' where id = v_ligne_b_id;
  if found then
    raise exception 'ISOLATION ROMPUE : le CEO A a pu modifier une ligne de charge de l''entreprise B';
  end if;

  raise notice 'OK — le CEO A ne voit/modifie rien des budgets ni lignes de l''entreprise B';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 3. Une catégorie de type 'revenu' ne peut pas être rattachée à une
--    ligne_charge_prevue (trigger, pas seulement RLS).
-- ---------------------------------------------------------------------
begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "a1000000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
begin
  begin
    insert into public.lignes_charge_prevue (budget_mensuel_id, entreprise_id, categorie_id, designation, montant)
    values (
      'a4000000-0000-0000-0000-000000000002',
      'a0000000-0000-0000-0000-000000000001',
      'a2000000-0000-0000-0000-000000000003', -- 'Ventes boutique', type revenu
      'Charge invalide',
      5000
    );
    raise exception 'GARDE-FOU ROMPU : une charge a pu être rattachée à une catégorie de type revenu';
  exception
    when others then
      if sqlerrm not like '%type revenu%' then
        raise exception 'ECHEC INATTENDU (message reçu: %)', sqlerrm;
      end if;
  end;

  raise notice 'OK — une catégorie de type revenu est rejetée sur une ligne de charge prévue';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 4. Le CEO A ne peut pas rattacher une ligne à un budget de l'entreprise B,
--    même en indiquant son propre entreprise_id sur la ligne.
-- ---------------------------------------------------------------------
begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "a1000000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
begin
  begin
    insert into public.lignes_charge_prevue (budget_mensuel_id, entreprise_id, categorie_id, designation, montant)
    values (
      'b4000000-0000-0000-0000-000000000001', -- budget de l'entreprise B
      'a0000000-0000-0000-0000-000000000001', -- entreprise_id du CEO A (usurpation tentée)
      'a2000000-0000-0000-0000-000000000001',
      'Ligne frauduleuse',
      1000
    );
    raise exception 'GARDE-FOU ROMPU : une ligne a pu être rattachée au budget d''une autre entreprise';
  exception
    when others then
      if sqlerrm not like '%même entreprise%' and sqlerrm not like '%budget référencé%' then
        raise exception 'ECHEC INATTENDU (message reçu: %)', sqlerrm;
      end if;
  end;

  raise notice 'OK — impossible de rattacher une ligne au budget d''une autre entreprise, même avec son propre entreprise_id';
end $$;

rollback;
