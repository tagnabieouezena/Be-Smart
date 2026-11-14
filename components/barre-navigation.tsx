"use client";

import { useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { BoutonDeconnexion } from "@/components/bouton-deconnexion";

// `section` ne sert qu'à la présentation (filet + titre discret). La liste des
// liens et leur répartition par rôle viennent toujours du serveur.
export type LienNavigation = { href: string; libelle: string; section?: "secondaire" };

// Icônes simples écrites à la main (SVG en ligne, aucune bibliothèque),
// décoratives : le libellé texte est toujours affiché à côté.
function Icone({ href }: { href: string }) {
  const commun = {
    width: 20,
    height: 20,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: 1.8,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
    "aria-hidden": true,
    focusable: false,
  };
  switch (href) {
    case "/ecarts": // cible : prévu vs réel
      return (
        <svg {...commun}>
          <circle cx="12" cy="12" r="8" />
          <circle cx="12" cy="12" r="4" />
          <circle cx="12" cy="12" r="0.8" fill="currentColor" />
        </svg>
      );
    case "/comparaison": // courbe
      return (
        <svg {...commun}>
          <path d="M4 19h16" />
          <path d="M5 15l4-4 4 3 6-7" />
        </svg>
      );
    case "/syntheses": // tableau
      return (
        <svg {...commun}>
          <rect x="4" y="5" width="16" height="14" rx="2" />
          <path d="M4 10h16M10 10v9" />
        </svg>
      );
    case "/budgets": // portefeuille
      return (
        <svg {...commun}>
          <rect x="3.5" y="6.5" width="17" height="12" rx="2" />
          <path d="M15 12.5h5.5M7 6.5l8-3 1 3" />
        </svg>
      );
    case "/transactions": // flèches entrée / sortie
      return (
        <svg {...commun}>
          <path d="M7 4v13M3.5 13.5L7 17l3.5-3.5" />
          <path d="M17 20V7M13.5 10.5L17 7l3.5 3.5" />
        </svg>
      );
    case "/creances": // facture
      return (
        <svg {...commun}>
          <path d="M6 3.5h9l3 3v14l-2-1.2-2 1.2-2-1.2-2 1.2-2-1.2-2 1.2z" />
          <path d="M9 9h6M9 12.5h6M9 16h3" />
        </svg>
      );
    case "/parametrage": // réglages
      return (
        <svg {...commun}>
          <path d="M4 7h10M18 7h2M4 17h2M10 17h10" />
          <circle cx="16" cy="7" r="2" />
          <circle cx="8" cy="17" r="2" />
        </svg>
      );
    case "/utilisateurs": // personnes
      return (
        <svg {...commun}>
          <circle cx="9" cy="8" r="3" />
          <path d="M3.5 19c.6-3.2 2.8-5 5.5-5s4.9 1.8 5.5 5" />
          <path d="M16 5.5a2.6 2.6 0 010 5M17.5 14.3c1.6.6 2.7 2.2 3 4.7" />
        </svg>
      );
    case "/supervision": // bâtiment
      return (
        <svg {...commun}>
          <path d="M4 20V8l8-4 8 4v12" />
          <path d="M9 20v-5h6v5M8 10h1M15 10h1" />
        </svg>
      );
    default:
      return (
        <svg {...commun}>
          <circle cx="12" cy="12" r="3" />
        </svg>
      );
  }
}

export function BarreNavigation({
  liens,
  entreprise,
  nom,
  email,
  roleLibelle,
}: {
  liens: LienNavigation[];
  entreprise: string | null;
  nom: string;
  email: string | null;
  roleLibelle: string;
}) {
  const pathname = usePathname();
  const [ouvert, setOuvert] = useState(false);

  const principaux = liens.filter((l) => l.section !== "secondaire");
  const secondaires = liens.filter((l) => l.section === "secondaire");

  function lienAffiche(lien: LienNavigation) {
    const actif = pathname === lien.href || pathname.startsWith(`${lien.href}/`);
    return (
      <li key={lien.href}>
        <Link href={lien.href} aria-current={actif ? "page" : undefined} onClick={() => setOuvert(false)}>
          <Icone href={lien.href} />
          <span>{lien.libelle}</span>
        </Link>
      </li>
    );
  }

  return (
    <aside className="barre-laterale">
      <div className="barre-entete">
        <div className="marque">
          <span className="marque-repere" aria-hidden="true">
            BS
          </span>
          <div className="marque-textes">
            <span className="marque-nom">Be Smart Pilotage</span>
            {entreprise && <p className="marque-entreprise">{entreprise}</p>}
          </div>
        </div>
        <button
          type="button"
          className="barre-bouton-menu"
          aria-expanded={ouvert}
          aria-controls="menu-principal"
          onClick={() => setOuvert((o) => !o)}
        >
          {ouvert ? "Fermer" : "Menu"}
        </button>
      </div>

      <div id="menu-principal" className={ouvert ? "barre-corps ouvert" : "barre-corps"}>
        {/* Un seul <nav> : liens principaux et secondaires de ce rôle. */}
        <nav aria-label="Navigation principale" className="barre-nav">
          <ul>
            {principaux.map(lienAffiche)}
          </ul>
          {secondaires.length > 0 && (
            <>
              <hr className="barre-separateur" />
              <p className="barre-titre-section" id="titre-section-secondaire">
                Administration
              </p>
              <ul aria-labelledby="titre-section-secondaire">
                {secondaires.map(lienAffiche)}
              </ul>
            </>
          )}
        </nav>

        <div className="barre-profil">
          <p className="profil-nom">{nom}</p>
          {email && email !== nom && <p className="profil-detail">{email}</p>}
          <p className="profil-detail">{roleLibelle}</p>
          <BoutonDeconnexion className="profil-deconnexion" />
        </div>
      </div>
    </aside>
  );
}
