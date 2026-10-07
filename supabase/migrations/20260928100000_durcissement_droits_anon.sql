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
