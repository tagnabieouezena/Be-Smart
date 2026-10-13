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
| Authentication → Sign In → **Minimum password length** | 6 minimum, ou plus (décision à prendre) | `minimum_password_length = 6` en local |
| Authentication → Emails → **SMTP** | fournisseur SMTP personnalisé | **Décision Ouezz, Phase 5.** Le SMTP intégré de Supabase est limité en volume et réservé aux tests |
| Authentication → Rate limits | valeurs à décider | Local : `max_frequency = "1s"`, `email_sent = 2` (ce second réglage n'a de sens qu'avec SMTP personnalisé) |
| Authentication → durée de validité des liens (OTP) | `otp_expiry = 3600` (1 h) par défaut | Une invitation valable 1 h est courte : le CEO peut la renvoyer depuis `/utilisateurs` |

Les modèles d'e-mail doivent rester **identiques** aux fichiers du repo : chaque lien dépend de la route `/auth/confirm`. Un modèle par défaut de Supabase enverrait un lien qui ne passe pas par l'application.

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
- Projet Vercel et plan (Hobby ou Pro) : voir la mémoire projet « déploiement Vercel ».
