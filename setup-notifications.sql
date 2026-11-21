-- Run AFTER setup.sql. First enable pg_net and pg_cron in Database > Extensions (or the two lines below).
create extension if not exists pg_net; create extension if not exists pg_cron;

-- Private settings (nobody can read these from the website).
create table private_config(k text primary key, v text); alter table private_config enable row level security;
insert into private_config values ('url','https://YOUR-PROJECT-REF.supabase.co/functions/v1/notify'), ('secret','PUT-A-LONG-RANDOM-SECRET-HERE');
create function pb_post(payload jsonb) returns void language plpgsql security definer as $$
declare u text; s text;
begin select v into u from private_config where k='url'; select v into s from private_config where k='secret';
  perform net.http_post(url := u, headers := jsonb_build_object('Content-Type','application/json','x-pb-secret',s), body := payload); end $$;
revoke execute on function pb_post(jsonb) from public, anon, authenticated;

create table push_subs(id bigint generated always as identity primary key, endpoint text unique not null, p256dh text, auth text, role text not null default 'customer', name text, phone text, created_at timestamptz default now());
create table leads(id bigint generated always as identity primary key, name text, phone text unique, cart jsonb default '[]', converted boolean default false, notified_at timestamptz, created_at timestamptz default now(), updated_at timestamptz default now());
create table visits(day date, vid text, primary key(day, vid));
alter table push_subs enable row level security; alter table leads enable row level security; alter table visits enable row level security;
create policy "customers subscribe" on push_subs for insert to anon, authenticated with check (role = 'customer');
create policy "push admin" on push_subs for all using (is_admin()) with check (is_admin());
create policy "leads admin" on leads for all using (is_admin()) with check (is_admin());
create policy "visits admin" on visits for select using (is_admin());

create function save_lead(p_name text, p_phone text, p_cart jsonb) returns void language sql security definer as $$
  insert into leads(name, phone, cart) values (p_name, regexp_replace(p_phone,'\D','','g'), coalesce(p_cart,'[]'))
  on conflict (phone) do update set name = excluded.name, cart = excluded.cart, updated_at = now(),
    notified_at = case when excluded.cart is distinct from leads.cart then null else leads.notified_at end,
    converted = case when jsonb_array_length(excluded.cart) > 0 and excluded.cart is distinct from leads.cart then false else leads.converted end
$$;
create function log_visit(p_vid text) returns void language sql security definer as $$ insert into visits(day, vid) values (current_date, left(p_vid, 40)) on conflict do nothing $$;
grant execute on function save_lead(text, text, jsonb), log_visit(text) to anon, authenticated;

-- Tell the notification function about new orders and status changes.
create function on_order() returns trigger language plpgsql security definer as $$
begin
  if tg_op = 'INSERT' then
    update leads set converted = true where right(phone, 9) = right(new.phone, 9);
    perform pb_post(jsonb_build_object('type','order_new','record',to_jsonb(new)));
  elsif new.status is distinct from old.status then
    perform pb_post(jsonb_build_object('type','order_status','record',to_jsonb(new)));
  end if; return new; end $$;
create trigger orders_notify after insert or update on orders for each row execute function on_order();

-- Every 30 minutes: cart-lead alerts, plus the 8pm daily and Sunday weekly summaries.
select cron.schedule('pb-tick', '*/30 * * * *', $$select pb_post('{"job":"tick"}'::jsonb)$$);
