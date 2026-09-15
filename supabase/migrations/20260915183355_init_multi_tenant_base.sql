-- Phase 0 — Fondations multi-tenant : entreprises, utilisateurs, isolation RLS.
-- Voir docs/briefs/phase-0-fondations.md et docs/03-modele-de-donnees.md.

create extension if not exists pgcrypto;

-- =========================================================================
-- 1. Tables
-- =========================================================================

create table public.entreprises (
  id uuid primary key default gen_random_uuid(),
  nom text not null,
  secteur text,
  devise text not null default 'FCFA',
  solde_initial numeric not null default 0,
  created_at timestamptz not null default now()
);

comment on table public.entreprises is
  'Une entreprise cliente de Be Smart Pilotage (tenant).';
comment on column public.entreprises.solde_initial is
  'Montant en numeric (jamais float) — exactitude financière non négociable.';

-- utilisateurs.id référence auth.users(id) : chaque utilisateur applicatif
-- correspond à un compte Supabase Auth ; le rôle et l'entreprise sont donc
-- résolus à partir de auth.uid(), jamais saisis côté client.
create table public.utilisateurs (
  id uuid primary key references auth.users (id) on delete cascade,
  nom text not null,
  email text not null,
  role text not null check (role in ('ceo', 'comptable')),
  entreprise_id uuid not null references public.entreprises (id) on delete cascade,
  created_at timestamptz not null default now()
);

comment on table public.utilisateurs is
  'Profil applicatif (rôle + entreprise) d''un utilisateur Supabase Auth.';

create index utilisateurs_entreprise_id_idx on public.utilisateurs (entreprise_id);

-- =========================================================================
-- 2. Fonctions helper (security definer : lisent utilisateurs sans re-déclencher
--    ses propres politiques RLS, donc pas de récursion dans les policies).
-- =========================================================================

create or replace function public.current_entreprise_id()
returns uuid
language sql
security definer
stable
set search_path = public
as $$
  select entreprise_id from public.utilisateurs where id = auth.uid();
$$;

comment on function public.current_entreprise_id() is
  'Entreprise (tenant) de l''utilisateur Supabase Auth actuellement connecté.';

create or replace function public.current_role_utilisateur()
returns text
language sql
security definer
stable
set search_path = public
as $$
  select role from public.utilisateurs where id = auth.uid();
$$;

comment on function public.current_role_utilisateur() is
  'Rôle applicatif (ceo | comptable) de l''utilisateur actuellement connecté.';

-- Rôle transverse de supervision Be Smart : pas une ligne de `utilisateurs`
-- (il n'appartient à aucune entreprise cliente), matérialisé par un claim
-- JWT app_metadata.super_admin = true, positionné manuellement par Be Smart
-- via l'API admin Supabase Auth sur les comptes internes concernés.
create or replace function public.is_super_admin_be_smart()
returns boolean
language sql
stable
as $$
  select coalesce(
    (auth.jwt() -> 'app_metadata' ->> 'super_admin')::boolean,
    false
  );
$$;

comment on function public.is_super_admin_be_smart() is
  'Vrai si le compte connecté porte le claim app_metadata.super_admin (équipe Be Smart, supervision lecture seule).';

-- =========================================================================
-- 3. RLS — entreprises
-- =========================================================================

-- RLS ne contrôle que les LIGNES visibles ; l'accès à la table elle-même
-- doit être accordé explicitement au rôle `authenticated` (aucun privilège
-- par défaut sur une table créée en migration). `anon` ne reçoit rien : pas
-- d'accès non authentifié aux données d'une entreprise.
grant select, update on public.entreprises to authenticated;
grant select, insert, update on public.utilisateurs to authenticated;

alter table public.entreprises enable row level security;

-- Le CEO lit et modifie uniquement sa propre entreprise. Aucune policy
-- super-admin sur la table de base : la supervision cross-tenant ne passe
-- que par la vue restreinte en colonnes ci-dessous (section 5), pour ne
-- jamais exposer `solde_initial` (colonne financière) au super-admin.
create policy "ceo_lecture_propre_entreprise"
  on public.entreprises
  for select
  using (id = public.current_entreprise_id());

create policy "ceo_modification_propre_entreprise"
  on public.entreprises
  for update
  using (
    id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'ceo'
  )
  with check (
    id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'ceo'
  );

-- Pas de policy insert/delete en phase 0 : la création d'une entreprise
-- (onboarding) est un flux à privilèges élevés (service_role), traité au
-- Module 4.1. Sans policy, insert/delete restent refusés par défaut sous RLS.

-- =========================================================================
-- 4. RLS — utilisateurs
-- =========================================================================

alter table public.utilisateurs enable row level security;

create policy "isolation_entreprise_lecture_utilisateurs"
  on public.utilisateurs
  for select
  using (entreprise_id = public.current_entreprise_id());

-- Un utilisateur modifie sa propre fiche, ou le CEO modifie n'importe quelle
-- fiche de sa propre entreprise (ex. changement de rôle) — jamais cross-tenant.
create policy "modification_utilisateurs_soi_meme_ou_ceo"
  on public.utilisateurs
  for update
  using (
    entreprise_id = public.current_entreprise_id()
    and (id = auth.uid() or public.current_role_utilisateur() = 'ceo')
  )
  with check (
    entreprise_id = public.current_entreprise_id()
    and (id = auth.uid() or public.current_role_utilisateur() = 'ceo')
  );

-- Seul un CEO peut créer un compte, uniquement pour sa propre entreprise et
-- uniquement avec le rôle 'comptable' (un CEO ne crée pas d'autre CEO).
-- Bootstrap du tout premier CEO d'une entreprise : hors RLS, via service_role
-- (voir supabase/seed.sql en local ; le flux de signup réel est Module 4.1).
create policy "ceo_cree_comptable_propre_entreprise"
  on public.utilisateurs
  for insert
  with check (
    entreprise_id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'ceo'
    and role = 'comptable'
  );

-- =========================================================================
-- 5. Vue de supervision Be Smart (lecture seule, colonnes non financières)
-- =========================================================================

-- security_invoker off (défaut) assumé : cette vue s'exécute avec les droits
-- du propriétaire (contourne les policies ci-dessus), donc l'accès est
-- entièrement contrôlé par le `where` explicite ci-dessous, pas par RLS.
-- Colonnes volontairement limitées à nom/secteur/created_at : jamais
-- `devise` ni `solde_initial` (financier) pour le super-admin.
create view public.v_entreprises_supervision as
select id, nom, secteur, created_at
from public.entreprises
where public.is_super_admin_be_smart();

comment on view public.v_entreprises_supervision is
  'Supervision Be Smart : métadonnées non financières de toutes les entreprises, lecture seule, réservé au claim super_admin.';

revoke all on public.v_entreprises_supervision from anon, authenticated;
grant select on public.v_entreprises_supervision to authenticated;

create view public.v_utilisateurs_supervision as
select id, nom, role, entreprise_id, created_at
from public.utilisateurs
where public.is_super_admin_be_smart();

comment on view public.v_utilisateurs_supervision is
  'Supervision Be Smart : liste et rôles des utilisateurs de toutes les entreprises, lecture seule, réservé au claim super_admin. Jamais les données saisies par ces utilisateurs.';

revoke all on public.v_utilisateurs_supervision from anon, authenticated;
grant select on public.v_utilisateurs_supervision to authenticated;
