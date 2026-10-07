-- Durcissement : le rôle anon n'a aucun droit sur le schéma public.
-- Défense en profondeur : la RLS ne doit pas être la seule barrière contre
-- anon, et le comportement local doit être identique à la CI (donc à la
-- prod) quelle que soit la version du CLI Supabase, dont l'image Postgres
-- accorde des droits par défaut à anon sur les objets du schéma public.
--
-- Ne touche ni aux droits d'authenticated ni à ceux de service_role.

-- 1. Objets existants (tables, vues, séquences, fonctions du schéma public).
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke all on all functions in schema public from anon;

-- 2. Objets futurs : ils naissent sans droit pour anon. S'applique aux objets
--    créés par le rôle qui exécute les migrations (postgres).
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on sequences from anon;
alter default privileges in schema public revoke execute on functions from anon;

-- 3. Fonctions : plus aucune n'est exécutable via le pseudo-rôle PUBLIC.
--    Une fonction Postgres est exécutable par PUBLIC dès sa création ;
--    anon en héritait donc malgré le revoke direct ci-dessus. Les droits
--    nécessaires sont accordés explicitement (idempotent : ils existent déjà
--    via les privilèges par défaut de l'image, mais ne doivent plus en dépendre).
revoke execute on all functions in schema public from public;

-- Fonctions appelées par les policies RLS (tables et Storage) et les vues :
-- évaluées avec les droits de l'appelant, donc authenticated en a besoin.
grant execute on function public.current_entreprise_id() to authenticated, service_role;
grant execute on function public.current_role_utilisateur() to authenticated, service_role;
grant execute on function public.is_super_admin_be_smart() to authenticated, service_role;

-- Les fonctions de trigger n'ont besoin d'aucun EXECUTE pour fonctionner
-- (le droit n'est vérifié qu'à la création du trigger). Les RPC applicatives
-- (creer_entreprise_et_ceo, dupliquer_charges_fixes_mois_precedent,
-- ecarts_mensuels, creances_situation, creances_balance_agee,
-- seuil_ecart_significatif) ont déjà leur grant explicite à authenticated.

-- Futures fonctions : naissent sans EXECUTE pour PUBLIC. La forme
-- « in schema public » ne suffit pas : Postgres n'y retire pas le droit par
-- défaut GLOBAL (EXECUTE pour PUBLIC sur toute fonction créée), il faut donc
-- la forme globale, limitée au rôle qui exécute les migrations (postgres).
-- Elle ne touche ni les schémas gérés par Supabase (autres propriétaires) ni
-- les fonctions existantes.
alter default privileges in schema public revoke execute on functions from public;
alter default privileges for role postgres revoke execute on functions from public;

