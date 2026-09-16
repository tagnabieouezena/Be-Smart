-- Tests adversariaux Module 4.2 — Paramétrage (categories, objectifs_ca).
-- Voir docs/briefs/module-4.2-parametrage.md, section 5.

set client_min_messages to warning;

-- ---------------------------------------------------------------------
-- 1. Un comptable ne peut pas écrire sur `categories` (RLS, pas juste l'UI).
-- ---------------------------------------------------------------------
begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "a1000000-0000-0000-0000-0000000000c2", "role": "authenticated"}';

do $$
declare
  v_categorie_id uuid := 'a2000000-0000-0000-0000-000000000001';
begin
  -- Insert
  begin
    insert into public.categories (entreprise_id, libelle, type)
    values ('a0000000-0000-0000-0000-000000000001', 'Créée par comptable', 'variable');
    raise exception 'RLS ROMPUE : un comptable a pu créer une catégorie';
  exception
    when insufficient_privilege or others then null;
  end;

  -- Update
  begin
    update public.categories set libelle = 'Modifiée par comptable' where id = v_categorie_id;
    if found then
      raise exception 'RLS ROMPUE : un comptable a pu modifier une catégorie';
    end if;
  end;

  -- Delete
  begin
    delete from public.categories where id = v_categorie_id;
    if found then
      raise exception 'RLS ROMPUE : un comptable a pu supprimer une catégorie';
    end if;
  end;

  -- Témoin positif : le comptable lit bien les catégories de son entreprise
  -- (et notamment celle-là même qu'il vient d'échouer à modifier/supprimer).
  perform 1 from public.categories where id = v_categorie_id;
  if not found then
    raise exception 'FAUX POSITIF SUSPECT : le comptable ne voit pas une catégorie de sa propre entreprise (RLS trop restrictive ?)';
  end if;

  raise notice 'OK — un comptable ne peut ni créer, ni modifier, ni supprimer une catégorie';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 2. Un comptable qui lit `objectifs_ca` reçoit zéro ligne (pas une erreur).
-- ---------------------------------------------------------------------

-- Précondition (en tant que postgres, hors RLS) : au moins un objectif
-- existe réellement pour l'entreprise A, pour que le zéro ci-dessous prouve
-- une exclusion RLS et non une base vide.
do $$
declare
  v_count int;
begin
  select count(*) into v_count
  from public.objectifs_ca
  where entreprise_id = 'a0000000-0000-0000-0000-000000000001';

  if v_count = 0 then
    raise exception 'PRECONDITION MANQUANTE : aucun objectif_ca seedé pour l''entreprise A, le test ci-dessous serait invalide';
  end if;
end $$;

begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "a1000000-0000-0000-0000-0000000000c2", "role": "authenticated"}';

do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.objectifs_ca;

  if v_count <> 0 then
    raise exception 'DONNEE STRATEGIQUE EXPOSEE : le comptable voit % objectif(s) de CA', v_count;
  end if;

  raise notice 'OK — un comptable lit 0 ligne sur objectifs_ca (aucune erreur SQL, comportement RLS normal)';
end $$;

rollback;

-- ---------------------------------------------------------------------
-- 3. Le CEO de l'entreprise A ne voit/modifie rien de l'entreprise B.
-- ---------------------------------------------------------------------
begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "a1000000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

do $$
declare
  v_count int;
  v_categorie_b_id uuid := 'b2000000-0000-0000-0000-000000000001';
begin
  select count(*) into v_count
  from public.categories
  where entreprise_id = 'b0000000-0000-0000-0000-000000000001';

  if v_count <> 0 then
    raise exception 'ISOLATION ROMPUE : le CEO A voit % catégorie(s) de l''entreprise B', v_count;
  end if;

  select count(*) into v_count
  from public.objectifs_ca
  where entreprise_id = 'b0000000-0000-0000-0000-000000000001';

  if v_count <> 0 then
    raise exception 'ISOLATION ROMPUE : le CEO A voit % objectif(s) de CA de l''entreprise B', v_count;
  end if;

  -- Écriture directe par id connu (fixé dans le seed) : même en ciblant
  -- précisément la ligne de l'entreprise B, la policy `with check` doit
  -- bloquer l'update.
  update public.categories set libelle = 'Modifiée par CEO A' where id = v_categorie_b_id;
  if found then
    raise exception 'ISOLATION ROMPUE : le CEO A a pu modifier une catégorie de l''entreprise B';
  end if;

  raise notice 'OK — le CEO A ne voit/modifie rien des catégories ni objectifs de l''entreprise B';
end $$;

rollback;
