// Scheduled Edge Function — finds recently-missed doses, resolves each
// patient's linked caregivers (Care Circle), and sends them an FCM push.
//
// Deploy: supabase functions deploy send-missed-dose-alerts
// Schedule: Supabase Dashboard -> Edge Functions -> this function -> Cron
//   (e.g. "*/5 * * * *" for every 5 minutes), or `supabase functions schedule`.
//
// Required secret (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are already
// auto-injected by Supabase into every Edge Function — do not set those
// manually):
//   supabase secrets set FCM_SERVICE_ACCOUNT_JSON='<paste the full JSON
//     content of a Firebase service account key — Firebase Console ->
//     Project Settings -> Service Accounts -> Generate new private key>'

import { createClient } from "npm:@supabase/supabase-js@2";
import { create, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
// Slightly wider than the recommended 5-minute cron interval so a slow
// invocation never leaves a gap where a missed dose goes unchecked.
const LOOKBACK_MINUTES = 6;

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

function loadServiceAccount(): ServiceAccount {
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON");
  if (!raw) throw new Error("FCM_SERVICE_ACCOUNT_JSON secret is not set.");
  return JSON.parse(raw);
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const binaryDer = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    binaryDer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

async function getAccessToken(sa: ServiceAccount): Promise<string> {
  const key = await importPrivateKey(sa.private_key);
  const jwt = await create(
    { alg: "RS256", typ: "JWT" },
    {
      iss: sa.client_email,
      scope: FCM_SCOPE,
      aud: "https://oauth2.googleapis.com/token",
      exp: getNumericDate(60 * 60),
      iat: getNumericDate(0),
    },
    key,
  );

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) {
    throw new Error(`Token exchange failed: ${res.status} ${await res.text()}`);
  }
  const json = await res.json();
  return json.access_token as string;
}

async function sendFcm(
  projectId: string,
  accessToken: string,
  token: string,
  title: string,
  body: string,
): Promise<void> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: { token, notification: { title, body } },
      }),
    },
  );
  if (!res.ok) {
    console.error(`FCM send failed for token ${token}: ${res.status} ${await res.text()}`);
  }
}

Deno.serve(async (_req) => {
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const since = new Date(Date.now() - LOOKBACK_MINUTES * 60 * 1000).toISOString();

    // medicine_logs.payload is the JSONB DoseLog (status/medicineName/etc)
    // — filter on the row's own created_at (when it synced to Supabase).
    const { data: logs, error: logsError } = await supabase
      .from("medicine_logs")
      .select("user_id, payload, created_at")
      .gte("created_at", since);
    if (logsError) throw logsError;

    const missed = (logs ?? []).filter((l) => l.payload?.status === "missed");
    if (missed.length === 0) {
      return new Response(JSON.stringify({ sent: 0 }), { status: 200 });
    }

    const sa = loadServiceAccount();
    const accessToken = await getAccessToken(sa);

    let sent = 0;
    for (const log of missed) {
      const patientId = log.user_id as string;
      const medicineName = log.payload?.medicineName ?? "a medicine";

      const { data: members } = await supabase
        .from("care_circle_members")
        .select("caregiver_id, patient_display_name")
        .eq("patient_id", patientId)
        .eq("status", "active");

      for (const member of members ?? []) {
        const { data: tokens } = await supabase
          .from("device_tokens")
          .select("fcm_token")
          .eq("user_id", member.caregiver_id);

        for (const t of tokens ?? []) {
          await sendFcm(
            sa.project_id,
            accessToken,
            t.fcm_token,
            "Missed dose alert",
            `${member.patient_display_name} missed a dose of ${medicineName}.`,
          );
          sent++;
        }
      }
    }

    return new Response(JSON.stringify({ sent }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error(e);
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
