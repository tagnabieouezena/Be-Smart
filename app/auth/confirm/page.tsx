import { redirect } from "next/navigation";
import { cheminInterneSur } from "@/lib/redirection";

const TYPES = {
  signup: {
    titre: "Confirmer mon inscription",
    texte: "Cliquez sur le bouton pour confirmer votre adresse e-mail et créer votre espace.",
    bouton: "Confirmer mon inscription",
  },
  invite: {
    titre: "Accepter l'invitation",
    texte: "Cliquez sur le bouton pour activer votre compte et choisir votre mot de passe.",
    bouton: "Accepter l'invitation",
  },
  recovery: {
    titre: "Réinitialiser mon mot de passe",
    texte: "Cliquez sur le bouton pour choisir un nouveau mot de passe.",
    bouton: "Réinitialiser mon mot de passe",
  },
} as const;

// Cette page (GET) n'appelle PAS Supabase et ne consomme donc jamais le jeton :
// un scanner d'e-mails ou un aperçu de lien qui l'ouvre le laisse intact. Le
// jeton n'est vérifié qu'à la soumission du formulaire (POST /auth/verifier).
export default async function ConfirmationPage({
  searchParams,
}: {
  searchParams: Promise<{ token_hash?: string; type?: string; next?: string }>;
}) {
  const { token_hash: tokenHash, type, next } = await searchParams;

  if (!tokenHash || !type || !(type in TYPES)) {
    redirect(`/auth/lien-invalide?type=${type && type in TYPES ? type : "inconnu"}`);
  }

  const texte = TYPES[type as keyof typeof TYPES];
  const suite = cheminInterneSur(next);

  return (
    <main style={{ padding: "2rem", maxWidth: 480, fontFamily: "system-ui, sans-serif" }}>
      <h1>{texte.titre}</h1>
      <p>{texte.texte}</p>
      <form method="POST" action="/auth/verifier" style={{ marginTop: "1rem" }}>
        <input type="hidden" name="token_hash" value={tokenHash} />
        <input type="hidden" name="type" value={type} />
        {suite && <input type="hidden" name="next" value={suite} />}
        <button type="submit" style={{ minHeight: 48, padding: "0 1.5rem", fontSize: "1rem" }}>
          {texte.bouton}
        </button>
      </form>
    </main>
  );
}
