import { NextResponse } from "next/server";
import { estimateTask } from "@/lib/estimator";

export const dynamic = "force-dynamic";

export async function GET(req: Request) {
  const url = new URL(req.url);
  const task = url.searchParams.get("task");
  if (!task) {
    return NextResponse.json({ error: "Missing ?task= parameter" }, { status: 400 });
  }

  const result = await estimateTask(task);
  return NextResponse.json(result);
}

export async function POST(req: Request) {
  const body = await req.json();
  const task = body.task;
  if (!task) {
    return NextResponse.json({ error: "Missing task field" }, { status: 400 });
  }

  const result = await estimateTask(task);
  return NextResponse.json(result);
}
