-- Module 4.1 — Bootstrap atomique entreprise + premier CEO.
-- Voir docs/briefs/module-4.1-authentification.md.

-- Correctif oublié en Phase 0 : `service_role` contourne RLS (BYPASSRLS)
-- mais pas les privilèges de table de base — sans ce GRANT explicite, la
-- route serveur d'invitation (client service_role) échoue avec
-- "permission denied for table utilisateurs" dès son premier insert.
-- Repéré en testant la route de ce module, corrigé ici plutôt que de
-- rouvrir la migration Phase 0 déjà mergée/revue.
grant select, insert, update on public.entreprises to service_role;
grant select, insert, update on public.utilisateurs to service_role;

create or replace function public.creer_entreprise_et_ceo(
  p_nom text,
  p_secteur text,
  p_nom_utilisateur text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entreprise_id uuid;
  v_email text;
begin
  if auth.uid() is null then
    raise exception 'Authentification requise.';
  end if;

  -- Vérification préalable : message d'erreur clair dans le cas séquentiel
  -- normal. La vraie garantie contre une entreprise orpheline en cas de
  -- double appel concurrent vient de la clé primaire utilisateurs.id : si
  -- deux appels concurrents passent tous les deux ce test avant de committer,
  -- le second insert dans utilisateurs échoue sur la contrainte PK, et
  -- l'absence de bloc EXCEPTION ici fait remonter l'erreur jusqu'à annuler
  -- toute la transaction du second appel — y compris son insert entreprises.
  if exists (select 1 from public.utilisateurs where id = auth.uid()) then
    raise exception 'Ce compte est déjà rattaché à une entreprise.';
  end if;

  select email into v_email from auth.users where id = auth.uid();

  insert into public.entreprises (nom, secteur, devise)
  values (p_nom, p_secteur, 'FCFA')
  returning id into v_entreprise_id;

  insert into public.utilisateurs (id, nom, email, role, entreprise_id)
  values (auth.uid(), p_nom_utilisateur, v_email, 'ceo', v_entreprise_id);

  return v_entreprise_id;
end;
$$;

comment on function public.creer_entreprise_et_ceo(text, text, text) is
  'Bootstrap atomique : crée une entreprise et son premier CEO (auth.uid() courant). Échoue si ce compte est déjà rattaché à une entreprise — jamais de double rattachement ni de changement d''entreprise via cette fonction.';

revoke all on function public.creer_entreprise_et_ceo(text, text, text) from public;
grant execute on function public.creer_entreprise_et_ceo(text, text, text) to authenticated;
