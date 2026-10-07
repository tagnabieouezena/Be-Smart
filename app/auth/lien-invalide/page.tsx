import Link from "next/link";

const MESSAGES: Record<string, { titre: string; texte: string }> = {
  invite: {
    titre: "Ce lien n'est plus valide",
    texte: "Demandez à votre gérant de vous renvoyer une invitation.",
  },
  signup: {
    titre: "Ce lien n'est plus valide",
    texte:
      "Il a déjà été utilisé ou il a expiré. Si vous avez déjà confirmé votre adresse e-mail, connectez-vous : votre entreprise existe déjà.",
  },
  recovery: {
    titre: "Ce lien n'est plus valide",
    texte: "Il a déjà été utilisé ou il a expiré. Demandez un nouveau lien depuis « Mot de passe oublié ? ».",
  },
  "signup-echec": {
    titre: "Adresse confirmée, entreprise non créée",
    texte: "Votre adresse e-mail est confirmée mais la création de l'entreprise a échoué. Connectez-vous : elle sera recréée automatiquement.",
  },
};

const PAR_DEFAUT = {
  titre: "Ce lien n'est plus valide",
  texte: "Il a déjà été utilisé ou il a expiré. Connectez-vous, ou demandez un nouveau lien.",
};

export default async function LienInvalidePage({
  searchParams,
}: {
  searchParams: Promise<{ type?: string }>;
}) {
  const { type } = await searchParams;
  const message = (type && MESSAGES[type]) || PAR_DEFAUT;

  return (
    <main style={{ padding: "2rem", maxWidth: 480, fontFamily: "system-ui, sans-serif" }}>
      <h1>{message.titre}</h1>
      <p role="alert">{message.texte}</p>
      <p style={{ display: "flex", gap: "1rem", marginTop: "1rem" }}>
        <Link href="/connexion">Se connecter</Link>
        {type === "recovery" && <Link href="/mot-de-passe-oublie">Mot de passe oublié ?</Link>}
      </p>
    </main>
  );
}
