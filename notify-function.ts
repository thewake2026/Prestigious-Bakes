// Supabase Edge Function named "notify". Paste into Edge Functions > Create function. Turn "Verify JWT" OFF.
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
webpush.setVapidDetails("mailto:" + Deno.env.get("VAPID_EMAIL"), Deno.env.get("VAPID_PUBLIC")!, Deno.env.get("VAPID_PRIVATE")!);
const last9 = (p: string) => String(p || "").replace(/\D/g, "").slice(-9);
async function push(subs: any[], msg: object) {
  await Promise.all(subs.map(async (s) => {
    try { await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, JSON.stringify(msg)); }
    catch (e) { if ([404, 410].includes((e as any).statusCode)) await db.from("push_subs").delete().eq("endpoint", s.endpoint); }
  }));
}
const subs = async (role: string) => (await db.from("push_subs").select("*").eq("role", role)).data ?? [];
const sum = (items: any[]) => (items ?? []).map((i) => `${i.qty} ${i.name}`).join(", ");

Deno.serve(async (req) => {
  const b = await req.json().catch(() => ({}));
  let ok = req.headers.get("x-pb-secret") === Deno.env.get("PB_SECRET");
  if (!ok) {
    const t = (req.headers.get("Authorization") || "").replace("Bearer ", "");
    const { data } = await db.auth.getUser(t);
    if (data.user) ok = !!(await db.from("admins").select("email").eq("email", data.user.email).maybeSingle()).data;
  }
  if (!ok) return new Response("Not allowed", { status: 401 });
  const r = b.record;

  if (b.type === "order_new") await push(await subs("admin"), { title: `New order from ${r.name}`, body: `${sum(r.items)} · ${r.mode} on ${r.needed_on}`, url: "/admin.html" });

  if (b.type === "order_status") {
    const text: any = {
      Baking: ["Your order is being baked", `Hi ${r.name}, we have started on your order.`],
      Ready: ["Your order is ready!", r.mode === "Pickup" ? `Hi ${r.name}, come to Eksu, Ado-Ekiti to pick it up.` : `Hi ${r.name}, it is ready and on its way to you.`],
      Delivered: ["Order completed", `Thank you ${r.name}! Enjoy, and order again soon.`],
    };
    const t = text[r.status];
    if (t) await push((await subs("customer")).filter((s) => last9(s.phone) === last9(r.phone)), { title: t[0], body: t[1], url: "/#track" });
  }

  if (b.broadcast) await push(await subs("customer"), { title: b.title, body: b.body, url: "/#menu" });

  if (b.job === "tick") {
    const { data: leads } = await db.from("leads").select("*").eq("converted", false).is("notified_at", null).lt("updated_at", new Date(Date.now() - 30 * 60e3).toISOString());
    for (const l of leads ?? []) {
      if (!(l.cart ?? []).length) continue;
      await push(await subs("admin"), { title: `${l.name} left items in the cart`, body: `${sum(l.cart)}. Tap to message them.`, url: "/admin.html#leads" });
      await db.from("leads").update({ notified_at: new Date().toISOString() }).eq("id", l.id);
    }
    const lagos = new Date(Date.now() + 3600e3), today = lagos.toISOString().slice(0, 10);
    if (lagos.getUTCHours() === 20) {
      const last = (await db.from("settings").select("value").eq("key", "last_digest").maybeSingle()).data?.value;
      if (last !== today) {
        await db.from("settings").upsert({ key: "last_digest", value: today });
        const since = (d: number) => new Date(Date.now() - d * 864e5).toISOString().slice(0, 10);
        const visits = async (d: number) => (await db.from("visits").select("vid", { count: "exact", head: true }).gte("day", since(d))).count ?? 0;
        const orders = (await db.from("orders").select("id", { count: "exact", head: true }).gte("created_at", today + "T00:00:00+01:00")).count ?? 0;
        const admins = await subs("admin");
        await push(admins, { title: "Today at Prestigious Bakes", body: `${await visits(0)} visitors and ${orders} orders today.`, url: "/admin.html" });
        if (lagos.getUTCDay() === 0) await push(admins, { title: "Your week", body: `${await visits(6)} visits to the website this week.`, url: "/admin.html" });
      }
    }
  }
  return new Response("ok");
});
