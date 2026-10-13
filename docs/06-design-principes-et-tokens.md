# Be Smart Pilotage — Principes de design et tokens (proposition)

*Document de cadrage pour le chantier design global. Rien n'est implémenté : la mise en œuvre part de `main` après (a) le merge de la PR #12 et (b) la validation de ce document par Ouezz. Référence d'inspiration : une maquette de tableau de bord sombre (barre latérale, navigation principale, profil en bas). Aucun élément de sa marque n'est repris.*

## 1. Principes tirés de la maquette

**Barre latérale.** Cinq blocs, de haut en bas :
1. **Marque** (nom et repère court) et bouton de repli de la barre.
2. **Recherche**, avec raccourci clavier affiché. **Non repris en V1** : la recherche globale est reportée après la V1 (décision du 2026-10-13) et la barre latérale n'a aucun champ de recherche. L'emplacement reste prévu dans la structure.
3. **Navigation principale** : liste verticale d'icônes et d'intitulés, un élément actif.
4. **Section secondaire**, séparée par un filet et un titre discret (ex. « Autres »).
5. **Profil en bas** : nom, e-mail, menu de déconnexion. Toujours visible, jamais dans le contenu.

**Hiérarchie.** Un seul titre de niveau 1 par écran, grand et net ; les filtres et actions secondaires sous le titre, dans une barre horizontale. Le contenu principal est un bloc unique, sans décor autour.

**Espacements.** Échelle en multiples de 4 px. Marges de page de 16 px sur mobile (règle du brief), 24 à 32 px sur bureau. Entre deux blocs : 16 ou 24 px ; à l'intérieur d'un bloc : 8 à 12 px.

**Densité.** Le pilotage financier demande des tableaux denses et lisibles : hauteur de ligne de 36 px sur bureau pour les tables (transactions, créances, écarts), 44 px minimum pour toute cible tactile (menu mobile, boutons). Pas de cartes décoratives autour des tableaux.

**États.**
- *Actif* : fond teinté de l'accent, texte de l'accent, indicateur plein de 3 px sur le bord. Pas de dégradé (la maquette en utilise un ; on ne le reprend pas, car il réduit le contraste perçu et n'apporte rien).
- *Survol* : fond légèrement teinté, sans changement de taille ni de police.
- *Focus clavier* : contour de 2 px de l'accent, décalé de 2 px. Jamais supprimé.
- *Désactivé* : opacité réduite **et** libellé explicite quand l'action est importante (ex. « Supprimer » désactivé parce qu'un paiement existe).

**Montants et écarts.**
- Chiffres tabulaires (`font-variant-numeric: tabular-nums`), alignés à droite, suffixe « FCFA » dans l'en-tête de colonne plutôt qu'à chaque cellule.
- Un écart favorable ou défavorable n'est **jamais** signalé par la couleur seule : signe explicite (+ / −) et, pour l'alerte, un libellé ou une icône (le seuil de 10 % du 4.6 est déjà un signal textuel).

## 2. Ce qu'on ne reprend pas

- **Carte « Upgrade to Pro » / « Boost with AI ».** Elle vend une formule et une fonction (assistant IA) qui n'existent pas dans le périmètre V1 (CDC 4.14 : facturation intégrée et services hors périmètre). Dans un outil de pilotage, un encart commercial en permanence dans la barre latérale détourne l'attention des chiffres et ne sert à rien à un CEO en démonstration. Si une offre apparaît un jour, elle aura sa place sur une page dédiée.
- **Éléments hors V1 de la barre** : *Tasks* (pas de gestion de tâches dans le CDC), *Inbox*, *Refer a Friend* (aucun parrainage prévu), *Documentation* et *Support* (à traiter quand ils existent réellement : une page d'aide, un contact).
- **Notifications** : pas dans la barre tant que le module 4.12 (notifications et rappels, Phase 4) n'existe pas. Un lien vide ou factice est pire que l'absence de lien.
- **Identité visuelle de la maquette** : nom, logo, icône de marque, illustrations, textes, typographie exacte, dégradé du bouton. Rien de tout cela n'est repris.
- **Gradient du bouton et de l'indicateur actif** : voir « États ».

## 3. Tokens CSS proposés

**Thème clair seul en V1** (décision du 2026-10-13). Les tokens du thème sombre ci-dessous restent documentés pour plus tard et **ne sont pas implémentés en V1**. Tous les contrastes sont calculés selon la formule WCAG 2.x (ratio relatif de luminance) ; les seuils visés sont 4.5:1 pour le texte et 3:1 pour les éléments graphiques porteurs d'information.

```css
:root {
  /* Surfaces */
  --color-fond: #ffffff;
  --color-surface: #f6f7f9;          /* cartes, fond de barre latérale */
  --color-surface-haute: #ffffff;    /* menus, popovers */
  --color-bordure: #d0d4dc;          /* séparateurs décoratifs uniquement */
  --color-bordure-saisie: #7a8190;   /* champs de saisie : 3.91:1 sur fond, 3:1 requis */

  /* Texte */
  --color-texte: #111318;            /* 18.58:1 sur fond, 17.33:1 sur surface */
  --color-texte-secondaire: #5b6170; /* 6.20:1 sur fond, 5.78:1 sur surface */

  /* Accent retenu : A, indigo (décision du 2026-10-13, voir §5) */
  --color-accent: #4f46e5;           /* 6.29:1 sur fond, bouton texte blanc 6.29:1 */
  --color-accent-texte: #ffffff;
  --color-accent-fond-actif: #eef0ff;/* fond de l'élément actif de la barre */
  --color-accent-texte-actif: #4f46e5;/* 5.55:1 sur fond actif */

  /* Sémantique financière (toujours accompagnée d'un signe ou d'un libellé) */
  --color-positif: #15703a;          /* 5.74:1 sur surface */
  --color-negatif: #b42318;          /* 6.13:1 sur surface */
  --color-alerte: #8a5a00;           /* 5.93:1 sur fond, 5.53:1 sur surface */

  /* Focus */
  --color-focus: #4f46e5;            /* 6.29:1 sur fond */

  /* Typographie */
  --police-texte: var(--font-inter), system-ui, -apple-system, "Segoe UI", sans-serif; /* --font-inter fournie par next/font */
  --police-chiffres: var(--police-texte); /* tabular-nums activé sur les montants */
  --taille-base: 15px;
  --taille-petite: 13px;
  --taille-titre: 28px;
  --poids-normal: 400;
  --poids-titre: 600;

  /* Espacements (échelle 4 px) */
  --espace-1: 4px;  --espace-2: 8px;  --espace-3: 12px;
  --espace-4: 16px; --espace-6: 24px; --espace-8: 32px;

  /* Rayons */
  --rayon-petit: 6px;
  --rayon: 10px;
  --rayon-grand: 14px;

  /* Ombres (volontairement discrètes) */
  --ombre-carte: 0 1px 2px rgb(17 19 24 / 0.06);
  --ombre-menu: 0 8px 24px rgb(17 19 24 / 0.12);

  /* Dimensions */
  --hauteur-ligne-table: 36px;
  --cible-tactile: 44px;
  --largeur-barre: 248px;
}

/* --- Thème sombre : documenté, hors V1, non implémenté --- */
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --color-fond: #121316;
    --color-surface: #1a1c22;
    --color-surface-haute: #22252d;
    --color-bordure: #3a3e48;        /* décoratif : 1.74:1, non porteur */
    --color-bordure-saisie: #6b7280; /* 3.84:1 sur fond sombre */
    --color-texte: #f2f3f5;          /* 16.73:1 sur fond */
    --color-texte-secondaire: #a3a9b5; /* 7.87:1 sur fond, 7.22:1 sur surface */
    --color-accent: #8b86ff;         /* 6.15:1 sur fond */
    --color-accent-texte: #121316;   /* bouton : 6.15:1 */
    --color-accent-fond-actif: #26243f;
    --color-accent-texte-actif: #8b86ff; /* 4.94:1 sur fond actif */
    --color-positif: #4ade80;        /* 9.77:1 sur surface */
    --color-negatif: #f87171;        /* 6.16:1 sur surface */
    --color-alerte: #f5c26b;         /* 11.33:1 sur fond */
    --color-focus: #8b86ff;
    --ombre-carte: none;
    --ombre-menu: 0 8px 24px rgb(0 0 0 / 0.5);
  }
}

:root[data-theme="dark"] {
    --color-fond: #121316;
    --color-surface: #1a1c22;
    --color-surface-haute: #22252d;
    --color-bordure: #3a3e48;        /* décoratif : 1.74:1, non porteur */
    --color-bordure-saisie: #6b7280; /* 3.84:1 sur fond sombre */
    --color-texte: #f2f3f5;          /* 16.73:1 sur fond */
    --color-texte-secondaire: #a3a9b5; /* 7.87:1 sur fond, 7.22:1 sur surface */
    --color-accent: #8b86ff;         /* 6.15:1 sur fond */
    --color-accent-texte: #121316;   /* bouton : 6.15:1 */
    --color-accent-fond-actif: #26243f;
    --color-accent-texte-actif: #8b86ff; /* 4.94:1 sur fond actif */
    --color-positif: #4ade80;        /* 9.77:1 sur surface */
    --color-negatif: #f87171;        /* 6.16:1 sur surface */
    --color-alerte: #f5c26b;         /* 11.33:1 sur fond */
    --color-focus: #8b86ff;
    --ombre-carte: none;
    --ombre-menu: 0 8px 24px rgb(0 0 0 / 0.5);
}
```

Points de contrôle :
- Hors V1 : les deux blocs sombres (préférence système et choix explicite) portent les mêmes valeurs : à générer depuis une seule source (un fichier de tokens) pour éviter les dérives.
- `body` reçoit une couleur de fond et une couleur de texte explicites, à chaque thème.
- Le texte sur fond d'accent (bouton) et l'accent sur fond actif sont à vérifier à chaque nouvelle couleur.

## 4. Correspondance avec la navigation par rôle (PR #12)

La structure de navigation ne change pas : seule la présentation change. Les liens viennent toujours de la logique serveur de `lib/redirection.ts` / `components/barre-navigation.tsx`.

| Rôle | Liens de la barre principale | Section secondaire | Profil (bas) |
|---|---|---|---|
| CEO | Écarts, Budget, Transactions, Créances, Paramétrage, Utilisateurs | — | Nom, e-mail, rôle, « Se déconnecter » |
| Comptable | Transactions, Créances | — | Nom, e-mail, rôle, « Se déconnecter » |
| Supervision Be Smart | Supervision (lien unique) | — | Nom, e-mail, « Se déconnecter » |

- Le bouton de repli de la barre et le titre du bloc profil sont les seuls éléments communs aux trois rôles.
- Le contrôle d'accès reste côté serveur : un lien masqué n'est pas une protection (brief, §1).
- Le nom de l'entreprise, présent dans la barre actuelle, passe sous la marque, en texte secondaire.

## 5. Décisions

### Décidées par Ouezz (2026-10-13)

1. **Accent : A, indigo** — `#4f46e5` (thème clair) / `#8b86ff` (thème sombre, hors V1). Contraste du bouton 6.29:1 ; texte actif 5.55:1 sur son fond. Écartés : B, sarcelle (`#0f766e`), car trop proche du vert des écarts positifs (`#15703a`, rapport de luminance 1.12:1) ; C, violet (`#6d28d9`), non retenu. Les contrastes de A restent ceux du §3.
2. **Thème : clair seul en V1.** Les tokens sombres du §3 restent documentés pour plus tard, non implémentés ; les ajouter plus tard demande surtout des tests et des captures.
3. **Police : Inter via `next/font/google`**, auto-hébergée au build : aucune requête vers Google Fonts à l'exécution. Repli sur la pile système (`system-ui, -apple-system, "Segoe UI", sans-serif`) si la police ne se charge pas. Licence SIL Open Font License, chiffres tabulaires disponibles.
4. **Recherche globale : reportée après la V1.** Aucun champ de recherche dans la barre latérale en V1.

### Encore ouvertes

Aucune décision de design n'est en attente pour l'étape 2. Le fournisseur SMTP et le plan d'hébergement relèvent d'autres notes (`docs/05-deploiement-prod-reglages-auth.md`).

## 6. Hors de ce document

- Implémentation des tokens et de la barre latérale : étape 2, après merge de la PR #12 et validation de ce document.
- Maquettes écran par écran (tableau de bord KPI, écrans de saisie) : à faire après le module 4.11.
