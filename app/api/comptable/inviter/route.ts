import { NextRequest, NextResponse } from "next/server";
import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import { createClient as createSessionClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";

// Authentifie la requête soit via le cookie de session (navigateur), soit
// via un Authorization: Bearer <access_token> (scripts, tests, futurs
// clients non-navigateur) — les deux passent par le client anon, donc les
// policies RLS s'appliquent normalement dans les deux cas, jamais service_role.
async function contexteRequete(request: NextRequest) {
  const authHeader = request.headers.get("authorization");

  if (authHeader?.startsWith("Bearer ")) {
    const token = authHeader.slice("Bearer ".length);
    const supabase = createSupabaseClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      {
        global: { headers: { Authorization: `Bearer ${token}` } },
        auth: { persistSession: false },
      },
    );
    const {
      data: { user },
    } = await supabase.auth.getUser(token);
    return { supabase, user };
  }

  const supabase = await createSessionClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return { supabase, user };
}

// Route serveur uniquement — jamais appelée avec service_role depuis le
// client. Le rôle CEO est vérifié via le client de session (RLS), avant
// tout usage du client admin. Voir docs/briefs/module-4.1-authentification.md.
export async function POST(request: NextRequest) {
  let body: { email?: string; nom?: string };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Corps JSON invalide." }, { status: 400 });
  }

  const { email, nom } = body;
  if (!email || !nom) {
    return NextResponse.json(
      { error: "email et nom sont requis." },
      { status: 400 },
    );
  }

  const { supabase, user } = await contexteRequete(request);

  if (!user) {
    return NextResponse.json({ error: "Authentification requise." }, { status: 401 });
  }

  const { data: profil, error: profilError } = await supabase
    .from("utilisateurs")
    .select("role, entreprise_id")
    .eq("id", user.id)
    .single();

  if (profilError || !profil || profil.role !== "ceo") {
    return NextResponse.json(
      { error: "Seul un CEO peut inviter un comptable." },
      { status: 403 },
    );
  }

  const admin = createAdminClient();

  const { data: invite, error: inviteError } =
    await admin.auth.admin.inviteUserByEmail(email);

  if (inviteError || !invite?.user) {
    return NextResponse.json(
      { error: inviteError?.message ?? "Échec de l'invitation." },
      { status: 502 },
    );
  }

  const { error: insertError } = await admin.from("utilisateurs").insert({
    id: invite.user.id,
    nom,
    email,
    role: "comptable",
    entreprise_id: profil.entreprise_id,
  });

  if (insertError) {
    return NextResponse.json({ error: insertError.message }, { status: 500 });
  }

  return NextResponse.json(
    { id: invite.user.id, email, role: "comptable" },
    { status: 201 },
  );
}
