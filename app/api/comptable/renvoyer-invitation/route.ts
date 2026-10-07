import { NextRequest, NextResponse } from "next/server";
import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import { createClient as createSessionClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";

// Renvoie l'e-mail d'activation d'un comptable de l'entreprise du CEO qui
// l'appelle. Le rôle et le rattachement sont vérifiés avec le client de
// session (RLS) AVANT tout usage du client admin.
export async function POST(request: NextRequest) {
  let body: { id?: string };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Corps JSON invalide." }, { status: 400 });
  }

  if (!body.id) {
    return NextResponse.json({ error: "id requis." }, { status: 400 });
  }

  const supabase = await createSessionClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Authentification requise." }, { status: 401 });
  }

  const { data: profil } = await supabase
    .from("utilisateurs")
    .select("role")
    .eq("id", user.id)
    .single();

  if (!profil || profil.role !== "ceo") {
    return NextResponse.json({ error: "Seul un CEO peut renvoyer une invitation." }, { status: 403 });
  }

  // Filtré par RLS : un comptable d'une autre entreprise reste introuvable.
  const { data: cible } = await supabase
    .from("utilisateurs")
    .select("id, email")
    .eq("id", body.id)
    .eq("role", "comptable")
    .maybeSingle();

  if (!cible) {
    return NextResponse.json({ error: "Comptable introuvable dans votre entreprise." }, { status: 404 });
  }

  const admin = createAdminClient();
  const { data: compte, error: compteError } = await admin.auth.admin.getUserById(cible.id);

  if (compteError || !compte?.user) {
    return NextResponse.json({ error: "Compte introuvable." }, { status: 404 });
  }

  const activeCompte =
    Boolean(compte.user.email_confirmed_at) &&
    (!compte.user.invited_at || compte.user.user_metadata?.mot_de_passe_defini === true);

  if (activeCompte) {
    return NextResponse.json({ error: "Ce compte est déjà activé." }, { status: 409 });
  }

  if (!compte.user.email_confirmed_at) {
    // Invitation jamais acceptée : on la renvoie.
    const { error } = await admin.auth.admin.inviteUserByEmail(cible.email);
    if (error) {
      return NextResponse.json({ error: error.message }, { status: 502 });
    }
  } else {
    // Lien accepté mais mot de passe jamais choisi : un lien de
    // réinitialisation permet de le définir.
    const anon = createSupabaseClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    );
    const { error } = await anon.auth.resetPasswordForEmail(cible.email);
    if (error) {
      return NextResponse.json({ error: error.message }, { status: 502 });
    }
  }

  return NextResponse.json({ id: cible.id, email: cible.email }, { status: 200 });
}
