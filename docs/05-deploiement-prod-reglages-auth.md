# Be Smart Pilotage — Note de déploiement : réglages Auth de prod

*À relire avant le premier `supabase db push` vers la prod et avant la mise en ligne Vercel. Source : PR #12 (navigation et parcours d'accueil), fichiers `supabase/config.toml`, `supabase/templates/`.*

## Pourquoi cette note existe

`supabase db push` applique les migrations, pas la configuration Auth. Le dashboard Supabase de prod garde donc ses valeurs par défaut tant qu'on ne les règle pas à la main. Un mauvais réglage ici se voit dans les e-mails envoyés aux vrais utilisateurs, et se rattrape mal.

Le plus grave : tous les liens d'e-mail sont construits sur **Site URL** (`{{ .SiteURL }}` dans les trois modèles). Si Site URL reste `http://localhost:3000`, aucun CEO ni comptable ne peut confirmer son compte ni accepter une invitation en prod.

## Réglages à reporter dans le dashboard de prod

| Où (dashboard Supabase de prod) | Valeur à mettre | Pourquoi |
|---|---|---|
| Authentication → URL Configuration → **Site URL** | URL publique de l'application (ex. `https://<domaine>`) | Base de tous les liens e-mail. Ne jamais laisser `localhost` |
| URL Configuration → **Redirect URLs** | URL publique uniquement | Liste blanche des redirections. **Retirer** `http://localhost:3000` et `http://127.0.0.1:3000` présents en local |
| Authentication → Sign In / Providers → Email → **Confirm email** | activé | Parcours d'inscription : confirmation avant connexion |
| Authentication → Sign In / Providers → Email → **Enable sign ups** | activé | Inscription du CEO (`enable_signup = true` en local) |
| Authentication → Sign In / Providers → **Anonymous sign-ins** | **désactivé** | `enable_anonymous_sign_ins = false` en local ; une connexion anonyme ouvrirait l'accès aux RPC |
| Authentication → Emails → modèle **Confirm signup** | contenu de `supabase/templates/confirmation.html`, sujet « Confirmez votre adresse e-mail — Be Smart Pilotage » | Le lien passe par `/auth/confirm?token_hash=…&type=signup` |
| Authentication → Emails → modèle **Invite user** | contenu de `supabase/templates/invite.html`, sujet « Vous êtes invité(e) sur Be Smart Pilotage » | Le lien passe par `/auth/confirm?…&type=invite` |
| Authentication → Emails → modèle **Reset password** | contenu de `supabase/templates/recovery.html`, sujet « Réinitialisation de votre mot de passe — Be Smart Pilotage » | Le lien passe par `/auth/confirm?…&type=recovery` |
| Authentication → Sign In / Providers → **Phone** | désactivé | `[auth.sms] enable_signup = false` en local ; aucune connexion par SMS en V1 |
| Authentication → Sign In / Providers → **Fournisseurs OAuth** (Apple, Google, etc.) | tous désactivés | Aucun `enabled = true` dans `[auth.external.*]` du repo ; l'application n'en propose aucun en V1 |
| Authentication → Sign In → **Minimum password length** | 6 minimum, ou plus (décision à prendre) | `minimum_password_length = 6` en local |
| Authentication → Emails → **SMTP** | fournisseur SMTP personnalisé | **Décision Ouezz, Phase 5.** Le SMTP intégré de Supabase est limité en volume et réservé aux tests |
| Authentication → Rate limits | valeurs à décider | Local : `max_frequency = "1s"`, `email_sent = 2` (ce second réglage n'a de sens qu'avec SMTP personnalisé) |
| Authentication → durée de validité des liens (OTP) | `otp_expiry = 3600` (1 h) par défaut | Une invitation valable 1 h est courte : le CEO peut la renvoyer depuis `/utilisateurs` |

Les modèles d'e-mail doivent rester **identiques** aux fichiers du repo : chaque lien dépend de la route `/auth/confirm`. Un modèle par défaut de Supabase enverrait un lien qui ne passe pas par l'application.

### Parcours hors V1 (modèles par défaut, à ne pas activer sans modèle dédié)

- **Changement d'adresse e-mail** : `double_confirm_changes = true` est dans `config.toml`, mais l'application n'appelle jamais `updateUser({ email })` (seul `updateUser({ password })` existe, dans `components/formulaire-mot-de-passe.tsx`). Le modèle « Change email address » reste celui de Supabase. Avant d'ouvrir ce parcours : créer un modèle `…/auth/confirm?token_hash={{ .TokenHash }}&type=email_change` et vérifier que `/auth/confirm` accepte ce type.
- **Connexion par lien magique** (`signInWithOtp`) : absent de l'application. Le modèle « Magic link » reste celui de Supabase. Même règle : modèle dédié avec `type=magiclink` avant d'activer.

## Décisions encore ouvertes (Ouezz)

1. **Fournisseur SMTP** (Phase 5), avec son domaine d'expédition et les enregistrements DNS associés.
2. **Longueur minimale du mot de passe** : 6 (local) ou davantage.
3. **Limites de débit** des e-mails et des tentatives de connexion en prod.
4. **Durée de validité** des liens d'invitation et de réinitialisation (1 h ou plus).

## Vérifications après réglage (sans créer de compte en prod)

- Site URL affichée dans le dashboard = URL publique exacte, sans `localhost`.
- Les trois modèles d'e-mail contiennent `{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=…`.
- Aucune URL `localhost` dans la liste Redirect URLs.
- Anonymous sign-ins désactivé.
- Un test de bout en bout se fait sur un environnement de test, pas sur la prod, puisqu'il crée des comptes réels.

## Hors de cette note

- `supabase db push` vers la prod : job CI dédié, à créer en Phase 5 (voir [roadmap](04-roadmap-suivi-modules.md)). Il ne doit pas être lancé à la main avant revue.
- Ordre de mise en ligne, décidé par Ouezz : (1) job CI `supabase db push` et schéma appliqué sur la prod Supabase ; (2) projet d'hébergement lié au repo `Be-Smart`, avec seulement l'URL et la clé `anon` en `NEXT_PUBLIC_*`, la clé `service_role` restant serveur-only ; (3) réglages Auth ci-dessus (Site URL, Redirect URLs). Aucun projet d'hébergement n'existe à ce jour.

## Décision ouverte : plan d'hébergement

- Le plan Hobby de Vercel interdit l'usage commercial. Be Smart Pilotage est destiné à être vendu, donc concerné au plus tard au premier client payant.
- Options non tranchées : garder Vercel au plan Pro au moment de la commercialisation, ou choisir un hébergeur au plan gratuit autorisant l'usage commercial (ce qui impliquerait de revoir [docs/01-stack-et-architecture.md](01-stack-et-architecture.md)).
- À trancher par Ouezz avant le premier client pilote. Rien n'est à faire avant la mise en ligne.
