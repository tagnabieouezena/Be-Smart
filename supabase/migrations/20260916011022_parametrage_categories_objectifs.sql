-- Module 4.2 — Paramétrage : catégories et objectifs de CA.
-- Voir docs/briefs/module-4.2-parametrage.md.

-- =========================================================================
-- 1. Table categories
-- =========================================================================

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references public.entreprises (id) on delete cascade,
  libelle text not null,
  type text not null check (type in ('fixe', 'variable', 'revenu')),
  created_at timestamptz not null default now(),
  unique (entreprise_id, type, libelle)
);

comment on table public.categories is
  'Catégories de charges (fixes/variables) et de revenus, personnalisables par entreprise.';

create index categories_entreprise_id_idx on public.categories (entreprise_id);

grant select, insert, update, delete on public.categories to authenticated;
grant select, insert, update, delete on public.categories to service_role;

alter table public.categories enable row level security;

-- Toute personne de l'entreprise (CEO ou comptable) lit les catégories —
-- le comptable en a besoin pour catégoriser ses saisies (Module 4.4).
create policy "isolation_entreprise_lecture_categories"
  on public.categories
  for select
  using (entreprise_id = public.current_entreprise_id());

-- Seul le CEO écrit. Aucune policy comptable pour insert/update/delete :
-- refus par défaut sous RLS, pas une vérification côté UI seulement.
create policy "ceo_ecriture_categories"
  on public.categories
  for insert
  with check (
    entreprise_id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'ceo'
  );

create policy "ceo_modification_categories"
  on public.categories
  for update
  using (
    entreprise_id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'ceo'
  )
  with check (
    entreprise_id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'ceo'
  );

create policy "ceo_suppression_categories"
  on public.categories
  for delete
  using (
    entreprise_id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'ceo'
  );

-- =========================================================================
-- 2. Table objectifs_ca — donnée stratégique, CEO uniquement (CDC 3.2)
-- =========================================================================

create table public.objectifs_ca (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references public.entreprises (id) on delete cascade,
  type_periode text not null check (type_periode in ('mensuel', 'trimestriel', 'annuel')),
  annee int not null,
  mois int check (mois between 1 and 12),
  trimestre int check (trimestre between 1 and 4),
  montant_cible numeric not null check (montant_cible >= 0),
  created_at timestamptz not null default now(),
  check (
    (type_periode = 'mensuel' and mois is not null and trimestre is null)
    or (type_periode = 'trimestriel' and trimestre is not null and mois is null)
    or (type_periode = 'annuel' and mois is null and trimestre is null)
  )
);

comment on table public.objectifs_ca is
  'Objectifs de chiffre d''affaires par mois/trimestre/année — donnée stratégique CEO uniquement (CDC 3.2).';

-- coalesce nécessaire : une contrainte unique standard ne détecterait pas
-- deux objectifs annuels identiques, NULL n'étant jamais égal à NULL.
create unique index objectifs_ca_unique_periode_idx on public.objectifs_ca (
  entreprise_id, type_periode, annee, coalesce(mois, 0), coalesce(trimestre, 0)
);

create index objectifs_ca_entreprise_id_idx on public.objectifs_ca (entreprise_id);

grant select, insert, update on public.objectifs_ca to authenticated;
grant select, insert, update on public.objectifs_ca to service_role;

alter table public.objectifs_ca enable row level security;

-- CEO uniquement, en lecture ET en écriture. Volontairement AUCUNE policy
-- comptable ici : sous RLS, l'absence de policy select fait qu'un comptable
-- lit zéro ligne (comportement normal, pas une erreur) — c'est le
-- comportement attendu et testé, pas une omission.
create policy "ceo_lecture_objectifs_ca"
  on public.objectifs_ca
  for select
  using (
    entreprise_id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'ceo'
  );

create policy "ceo_creation_objectifs_ca"
  on public.objectifs_ca
  for insert
  with check (
    entreprise_id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'ceo'
  );

create policy "ceo_modification_objectifs_ca"
  on public.objectifs_ca
  for update
  using (
    entreprise_id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'ceo'
  )
  with check (
    entreprise_id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'ceo'
  );
