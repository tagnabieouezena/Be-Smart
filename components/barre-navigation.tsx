"use client";

import { useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { BoutonDeconnexion } from "@/components/bouton-deconnexion";

export type LienNavigation = { href: string; libelle: string };

export function BarreNavigation({
  liens,
  entreprise,
  nom,
  roleLibelle,
}: {
  liens: LienNavigation[];
  entreprise: string | null;
  nom: string;
  roleLibelle: string;
}) {
  const pathname = usePathname();
  const [ouvert, setOuvert] = useState(false);

  return (
    <header className="barre-nav">
      <div className="barre-nav-entete">
        <div className="barre-nav-identite">
          <strong>{entreprise ?? "Be Smart Pilotage"}</strong>
          <span>
            {nom} — {roleLibelle}
          </span>
        </div>
        <button
          type="button"
          className="barre-nav-bouton-menu"
          aria-expanded={ouvert}
          aria-controls="menu-principal"
          onClick={() => setOuvert((o) => !o)}
        >
          {ouvert ? "Fermer" : "Menu"}
        </button>
      </div>

      <nav aria-label="Navigation principale" id="menu-principal" className={ouvert ? "barre-nav-liens ouvert" : "barre-nav-liens"}>
        <ul>
          {liens.map((lien) => {
            const actif = pathname === lien.href || pathname.startsWith(`${lien.href}/`);
            return (
              <li key={lien.href}>
                <Link
                  href={lien.href}
                  aria-current={actif ? "page" : undefined}
                  onClick={() => setOuvert(false)}
                >
                  {lien.libelle}
                </Link>
              </li>
            );
          })}
          <li>
            <BoutonDeconnexion className="barre-nav-deconnexion" />
          </li>
        </ul>
      </nav>
    </header>
  );
}
