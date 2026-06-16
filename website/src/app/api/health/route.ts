import { NextResponse } from "next/server";
import { ensureFirestore } from "@/lib/firestore/client";

export async function GET() {
  try {
    await ensureFirestore();
    return NextResponse.json({ ok: true, service: "nucleus-sync", database: "firestore" });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Firestore unavailable";
    return NextResponse.json({ ok: false, error: message }, { status: 503 });
  }
}
