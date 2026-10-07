-- Parcours d'inscription avec confirmation d'e-mail : la création de
-- l'entreprise est déclenchée par la route de confirmation (lien cliqué) et
-- doit donc être rejouable (double clic, lien rouvert, rechargement) sans
-- créer de seconde entreprise ni lever d'erreur bloquante.
--
-- Nouvelle règle : si l'appelant est déjà rattaché à une entreprise, la
-- fonction renvoie l'identifiant de CETTE entreprise (jamais d'une autre) et
-- ne crée rien. Les appels concurrents d'un même utilisateur sont sérialisés
-- par un verrou consultatif : le second attend, voit le profil créé par le
-- premier, et le renvoie.
--
-- Un compte issu d'une invitation (auth.users.invited_at non nul) ne peut
-- JAMAIS créer d'entreprise : s'il n'est rattaché à aucune (cas de l'orphelin
-- connu du Module 4.1 : invitation envoyée mais insertion du profil échouée),
-- l'appel est rejeté. Le contrôle vit ici, pas seulement dans l'interface :
-- les métadonnées d'un compte étant modifiables par son titulaire, rien de ce
-- que l'interface envoie ne peut contourner ce refus.
--
-- Les paramètres ne servent qu'à NOMMER l'entreprise et le CEO : le rôle
-- ('ceo') et l'entreprise sont fixés ici, jamais fournis par l'appelant.

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
  v_invited_at timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Authentification requise.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('creer_entreprise_et_ceo:' || auth.uid()::text, 0));

  select entreprise_id into v_entreprise_id
  from public.utilisateurs where id = auth.uid();

  if found then
    return v_entreprise_id;
  end if;

  select email, invited_at into v_email, v_invited_at from auth.users where id = auth.uid();

  if v_invited_at is not null then
    raise exception 'Votre compte a été créé par invitation mais n''est rattaché à aucune entreprise : contactez votre gérant.';
  end if;

  insert into public.entreprises (nom, secteur, devise)
  values (p_nom, p_secteur, 'FCFA')
  returning id into v_entreprise_id;

  insert into public.utilisateurs (id, nom, email, role, entreprise_id)
  values (auth.uid(), p_nom_utilisateur, v_email, 'ceo', v_entreprise_id);

  return v_entreprise_id;
end;
$$;

comment on function public.creer_entreprise_et_ceo(text, text, text) is
  'Bootstrap atomique et idempotent : crée une entreprise et son premier CEO (auth.uid() courant) ; si le compte est déjà rattaché, renvoie son entreprise sans rien créer ; refuse tout compte issu d''une invitation non rattaché. Les paramètres ne servent qu''à nommer.';
