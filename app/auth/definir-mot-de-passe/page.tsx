import { redirect } from "next/navigation";
import { FormulaireMotDePasse } from "@/components/formulaire-mot-de-passe";
import { createClient } from "@/lib/supabase/server";

export default async function Page() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  // Cette page n'est utile qu'avec la session ouverte par le lien de l'e-mail.
  if (!user) {
    redirect("/auth/lien-invalide?type=invite");
  }

  return (
    <main style={{ padding: "2rem", maxWidth: 480, fontFamily: "system-ui, sans-serif" }}>
      <h1>Choisir mon mot de passe</h1>
      <FormulaireMotDePasse bouton="Définir mon mot de passe" />
    </main>
  );
}
