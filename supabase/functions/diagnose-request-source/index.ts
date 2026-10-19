// Diagnostic-only Edge Function draft.
// NOT DEPLOYED. Does not access the database, accept student codes,
// or return/store IP addresses or raw request headers.
//
// Purpose: help verify whether the deployed gateway supplies source metadata.
// Presence alone does NOT prove that a header is trustworthy. Before relying
// on X-Forwarded-For, validate gateway overwrite/append behavior and spoofing
// resistance in the actual Supabase project.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

serve((req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "GET") {
    return new Response(
      JSON.stringify({ error: "Method not allowed" }),
      {
        status: 405,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  const forwardedFor = req.headers.get("x-forwarded-for");
  const realIp = req.headers.get("x-real-ip");
  const cfConnectingIp = req.headers.get("cf-connecting-ip");

  // Only return booleans and a count. Never return or log header values.
  // A comma count is merely descriptive and is not proof of trusted parsing.
  const response = {
    diagnostic_only: true,
    source_metadata: {
      x_forwarded_for_present: Boolean(forwardedFor?.trim()),
      x_forwarded_for_entry_count: forwardedFor?.trim()
        ? forwardedFor.split(",").filter((part) => part.trim().length > 0).length
        : 0,
      x_real_ip_present: Boolean(realIp?.trim()),
      cf_connecting_ip_present: Boolean(cfConnectingIp?.trim()),
    },
    warning:
      "Header presence does not establish trust. Do not use these values for security decisions until gateway behavior is verified.",
  };

  return new Response(JSON.stringify(response), {
    status: 200,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
