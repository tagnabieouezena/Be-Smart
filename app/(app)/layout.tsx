import { BarreNavigation, type LienNavigation } from "@/components/barre-navigation";
import { lireContexte } from "@/lib/contexte";

const LIENS_CEO: LienNavigation[] = [
  { href: "/ecarts", libelle: "Écarts" },
  { href: "/comparaison", libelle: "Comparaison" },
  { href: "/syntheses", libelle: "Synthèses" },
  { href: "/budgets", libelle: "Budget" },
  { href: "/transactions", libelle: "Transactions" },
  { href: "/creances", libelle: "Créances" },
  // Section secondaire : présentation seulement (filet + titre « Administration »).
  { href: "/parametrage", libelle: "Paramétrage", section: "secondaire" },
  { href: "/utilisateurs", libelle: "Utilisateurs", section: "secondaire" },
];

const LIENS_COMPTABLE: LienNavigation[] = [
  { href: "/transactions", libelle: "Transactions" },
  { href: "/creances", libelle: "Créances" },
];

const LIENS_SUPERVISION: LienNavigation[] = [{ href: "/supervision", libelle: "Supervision" }];

const LIBELLES_ROLE = {
  ceo: "CEO",
  comptable: "Comptable",
  supervision: "Supervision Be Smart",
} as const;

// La barre est construite côté serveur à partir du rôle. Masquer un lien n'est
// pas une mesure de sécurité : chaque page garde son propre contrôle de rôle.
export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const contexte = await lireContexte();

  const liens =
    contexte?.role === "ceo"
      ? LIENS_CEO
      : contexte?.role === "comptable"
        ? LIENS_COMPTABLE
        : contexte?.role === "supervision"
          ? LIENS_SUPERVISION
          : null;

  return (
    <div className="coquille">
      {contexte && contexte.role && liens && (
        <BarreNavigation
          liens={liens}
          entreprise={contexte.entrepriseNom}
          nom={contexte.nom}
          email={contexte.user.email ?? null}
          roleLibelle={LIBELLES_ROLE[contexte.role]}
        />
      )}
      <div className="coquille-contenu">{children}</div>
    </div>
  );
}
