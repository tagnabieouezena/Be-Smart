import { FormulaireConnexion } from "@/components/formulaire-connexion";
import { cheminInterneSur } from "@/lib/redirection";

export default async function ConnexionPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const { next } = await searchParams;
  // Un `next` externe ou protocole-relatif est ignoré : accueil du rôle.
  const suite = cheminInterneSur(next);

  return (
    <main style={{ padding: "2rem", maxWidth: 480, fontFamily: "system-ui, sans-serif" }}>
      <h1>Connexion — Be Smart Pilotage</h1>
      <FormulaireConnexion suite={suite} />
    </main>
  );
}
