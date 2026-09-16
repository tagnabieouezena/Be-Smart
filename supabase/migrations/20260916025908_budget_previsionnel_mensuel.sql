-- Module 4.3 — Budget prévisionnel mensuel.
-- Voir docs/briefs/module-4.3-budget-previsionnel.md.

-- =========================================================================
-- 1. Table budgets_mensuels
-- =========================================================================

create table public.budgets_mensuels (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references public.entreprises (id) on delete cascade,
  mois int not null check (mois between 1 and 12),
  annee int not null,
  statut text not null default 'brouillon' check (statut in ('brouillon', 'valide')),
  created_at timestamptz not null default now(),
  unique (entreprise_id, mois, annee)
);

comment on table public.budgets_mensuels is
  'Budget prévisionnel mensuel d''une entreprise. `statut` sans effet de verrouillage en V1 (sobriété fonctionnelle, cf. brief).';

create index budgets_mensuels_entreprise_id_idx on public.budgets_mensuels (entreprise_id);

grant select, insert, update on public.budgets_mensuels to authenticated;
grant select, insert, update on public.budgets_mensuels to service_role;

alter table public.budgets_mensuels enable row level security;

create policy "isolation_entreprise_lecture_budgets_mensuels"
  on public.budgets_mensuels
  for select
  using (entreprise_id = public.current_entreprise_id());

create policy "ceo_creation_budgets_mensuels"
  on public.budgets_mensuels
  for insert
  with check (
    entreprise_id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'ceo'
  );

create policy "ceo_modification_budgets_mensuels"
  on public.budgets_mensuels
  for update
  using (
    entreprise_id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'ceo'
  )
  with check (
    entreprise_id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'ceo'
  );

-- =========================================================================
-- 2. Table lignes_charge_prevue
-- =========================================================================

create table public.lignes_charge_prevue (
  id uuid primary key default gen_random_uuid(),
  budget_mensuel_id uuid not null references public.budgets_mensuels (id) on delete cascade,
  entreprise_id uuid not null references public.entreprises (id) on delete cascade,
  categorie_id uuid not null references public.categories (id),
  designation text not null,
  montant numeric not null check (montant >= 0),
  statut text not null default 'a_faire' check (statut in ('a_faire', 'planifie', 'realise', 'annule')),
  created_at timestamptz not null default now()
);

comment on table public.lignes_charge_prevue is
  'Ligne de charge (fixe ou variable) prévue dans un budget mensuel.';

create index lignes_charge_prevue_entreprise_id_idx on public.lignes_charge_prevue (entreprise_id);
create index lignes_charge_prevue_budget_mensuel_id_idx on public.lignes_charge_prevue (budget_mensuel_id);

grant select, insert, update, delete on public.lignes_charge_prevue to authenticated;
grant select, insert, update, delete on public.lignes_charge_prevue to service_role;

alter table public.lignes_charge_prevue enable row level security;

create policy "isolation_entreprise_lecture_lignes_charge_prevue"
  on public.lignes_charge_prevue
  for select
  using (entreprise_id = public.current_entreprise_id());

create policy "ceo_ecriture_lignes_charge_prevue"
  on public.lignes_charge_prevue
  for insert
  with check (
    entreprise_id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'ceo'
  );

create policy "ceo_modification_lignes_charge_prevue"
  on public.lignes_charge_prevue
  for update
  using (
    entreprise_id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'ceo'
  )
  with check (
    entreprise_id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'ceo'
  );

create policy "ceo_suppression_lignes_charge_prevue"
  on public.lignes_charge_prevue
  for delete
  using (
    entreprise_id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'ceo'
  );

-- Garde-fous que ni un `check`, ni une simple `foreign key` ne peuvent
-- exprimer : cohérence d'entreprise entre la ligne, son budget et sa
-- catégorie, et exclusion des catégories de type 'revenu'. Sans ça, la
-- policy RLS empêcherait seulement de *voir* une incohérence après coup,
-- pas de la *créer*.
create or replace function public.verifier_coherence_ligne_charge_prevue()
returns trigger
language plpgsql
as $$
declare
  v_budget_entreprise_id uuid;
  v_categorie_entreprise_id uuid;
  v_categorie_type text;
begin
  select entreprise_id into v_budget_entreprise_id
  from public.budgets_mensuels where id = new.budget_mensuel_id;

  if v_budget_entreprise_id is null or v_budget_entreprise_id <> new.entreprise_id then
    raise exception 'Le budget référencé n''appartient pas à la même entreprise que la ligne.';
  end if;

  select entreprise_id, type into v_categorie_entreprise_id, v_categorie_type
  from public.categories where id = new.categorie_id;

  if v_categorie_entreprise_id is null or v_categorie_entreprise_id <> new.entreprise_id then
    raise exception 'La catégorie référencée n''appartient pas à la même entreprise que la ligne.';
  end if;

  if v_categorie_type = 'revenu' then
    raise exception 'Une charge prévue ne peut pas être rattachée à une catégorie de type revenu.';
  end if;

  return new;
end;
$$;

create trigger verifier_coherence_ligne_charge_prevue
  before insert or update on public.lignes_charge_prevue
  for each row execute function public.verifier_coherence_ligne_charge_prevue();

-- =========================================================================
-- 3. Table lignes_revenu_prevu
-- =========================================================================

create table public.lignes_revenu_prevu (
  id uuid primary key default gen_random_uuid(),
  budget_mensuel_id uuid not null references public.budgets_mensuels (id) on delete cascade,
  entreprise_id uuid not null references public.entreprises (id) on delete cascade,
  source text not null,
  montant_estime numeric not null check (montant_estime >= 0),
  echeance date,
  statut text not null default 'en_attente' check (statut in ('ok', 'en_attente', 'annule')),
  created_at timestamptz not null default now()
);

comment on table public.lignes_revenu_prevu is
  'Ligne de revenu prévu dans un budget mensuel. `source` en texte libre (le CDC ne catégorise pas les revenus, contrairement aux charges).';

create index lignes_revenu_prevu_entreprise_id_idx on public.lignes_revenu_prevu (entreprise_id);
create index lignes_revenu_prevu_budget_mensuel_id_idx on public.lignes_revenu_prevu (budget_mensuel_id);

grant select, insert, update, delete on public.lignes_revenu_prevu to authenticated;
grant select, insert, update, delete on public.lignes_revenu_prevu to service_role;

alter table public.lignes_revenu_prevu enable row level security;

create policy "isolation_entreprise_lecture_lignes_revenu_prevu"
  on public.lignes_revenu_prevu
  for select
  using (entreprise_id = public.current_entreprise_id());

create policy "ceo_ecriture_lignes_revenu_prevu"
  on public.lignes_revenu_prevu
  for insert
  with check (
    entreprise_id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'ceo'
  );

create policy "ceo_modification_lignes_revenu_prevu"
  on public.lignes_revenu_prevu
  for update
  using (
    entreprise_id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'ceo'
  )
  with check (
    entreprise_id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'ceo'
  );

create policy "ceo_suppression_lignes_revenu_prevu"
  on public.lignes_revenu_prevu
  for delete
  using (
    entreprise_id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'ceo'
  );

create or replace function public.verifier_coherence_ligne_revenu_prevu()
returns trigger
language plpgsql
as $$
declare
  v_budget_entreprise_id uuid;
begin
  select entreprise_id into v_budget_entreprise_id
  from public.budgets_mensuels where id = new.budget_mensuel_id;

  if v_budget_entreprise_id is null or v_budget_entreprise_id <> new.entreprise_id then
    raise exception 'Le budget référencé n''appartient pas à la même entreprise que la ligne.';
  end if;

  return new;
end;
$$;

create trigger verifier_coherence_ligne_revenu_prevu
  before insert or update on public.lignes_revenu_prevu
  for each row execute function public.verifier_coherence_ligne_revenu_prevu();

-- =========================================================================
-- 4. Vue des totaux (calcul automatique, CDC 4.3)
-- =========================================================================

-- security_invoker = true : la vue s'exécute avec les droits de l'appelant,
-- donc les policies RLS des tables sous-jacentes s'appliquent normalement
-- (CEO et comptable voient les totaux de leur propre entreprise, comme sur
-- budgets_mensuels lui-même) — contrairement aux vues de supervision de la
-- Phase 0 qui, elles, ont besoin du comportement inverse.
create view public.v_budget_mensuel_totaux
with (security_invoker = true)
as
select
  b.id as budget_mensuel_id,
  b.entreprise_id,
  b.mois,
  b.annee,
  coalesce(cf.total, 0) as total_charges_fixes,
  coalesce(cv.total, 0) as total_charges_variables,
  coalesce(r.total, 0) as total_ca_previsionnel,
  coalesce(r.total, 0) - coalesce(cf.total, 0) - coalesce(cv.total, 0) as resultat_previsionnel
from public.budgets_mensuels b
left join (
  select l.budget_mensuel_id, sum(l.montant) as total
  from public.lignes_charge_prevue l
  join public.categories c on c.id = l.categorie_id
  where c.type = 'fixe'
  group by l.budget_mensuel_id
) cf on cf.budget_mensuel_id = b.id
left join (
  select l.budget_mensuel_id, sum(l.montant) as total
  from public.lignes_charge_prevue l
  join public.categories c on c.id = l.categorie_id
  where c.type = 'variable'
  group by l.budget_mensuel_id
) cv on cv.budget_mensuel_id = b.id
left join (
  select budget_mensuel_id, sum(montant_estime) as total
  from public.lignes_revenu_prevu
  group by budget_mensuel_id
) r on r.budget_mensuel_id = b.id;

comment on view public.v_budget_mensuel_totaux is
  'Totaux calculés (charges fixes, charges variables, CA prévisionnel, résultat prévisionnel) par budget mensuel — numeric partout, jamais de float.';

grant select on public.v_budget_mensuel_totaux to authenticated;

-- =========================================================================
-- 5. RPC de duplication des charges fixes du mois précédent (CDC 4.3)
-- =========================================================================

-- Pas de security definer : s'exécute avec les droits de l'appelant, donc
-- les policies RLS existantes (CEO uniquement en écriture, + les triggers
-- de cohérence ci-dessus) s'appliquent naturellement à l'insert qu'elle fait.
create or replace function public.dupliquer_charges_fixes_mois_precedent(p_budget_mensuel_id uuid)
returns int
language plpgsql
as $$
declare
  v_entreprise_id uuid;
  v_mois int;
  v_annee int;
  v_mois_prec int;
  v_annee_prec int;
  v_budget_prec_id uuid;
  v_count int;
begin
  select entreprise_id, mois, annee into v_entreprise_id, v_mois, v_annee
  from public.budgets_mensuels
  where id = p_budget_mensuel_id;

  if v_entreprise_id is null then
    raise exception 'Budget introuvable.';
  end if;

  if v_entreprise_id <> public.current_entreprise_id() then
    raise exception 'Ce budget n''appartient pas à votre entreprise.';
  end if;

  if v_mois = 1 then
    v_mois_prec := 12;
    v_annee_prec := v_annee - 1;
  else
    v_mois_prec := v_mois - 1;
    v_annee_prec := v_annee;
  end if;

  select id into v_budget_prec_id
  from public.budgets_mensuels
  where entreprise_id = v_entreprise_id and mois = v_mois_prec and annee = v_annee_prec;

  if v_budget_prec_id is null then
    return 0;
  end if;

  insert into public.lignes_charge_prevue (entreprise_id, budget_mensuel_id, categorie_id, designation, montant, statut)
  select v_entreprise_id, p_budget_mensuel_id, l.categorie_id, l.designation, l.montant, 'a_faire'
  from public.lignes_charge_prevue l
  join public.categories c on c.id = l.categorie_id
  where l.budget_mensuel_id = v_budget_prec_id and c.type = 'fixe';

  get diagnostics v_count = row_count;

  return v_count;
end;
$$;

comment on function public.dupliquer_charges_fixes_mois_precedent(uuid) is
  'Copie les charges fixes du budget du mois précédent (même entreprise) vers le budget cible, statut réinitialisé à a_faire. Renvoie 0 (pas d''erreur) si le mois précédent n''a pas de budget ou pas de charges fixes.';

revoke all on function public.dupliquer_charges_fixes_mois_precedent(uuid) from public;
grant execute on function public.dupliquer_charges_fixes_mois_precedent(uuid) to authenticated;
