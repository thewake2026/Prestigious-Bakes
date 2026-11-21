-- Run this once in Supabase > SQL Editor.

create table items(id bigint generated always as identity primary key, name text not null, category text not null, price numeric, image_url text, available boolean default true, sort int default 0);
create table orders(id bigint generated always as identity primary key, code text unique default substr(md5(random()::text),1,6), name text, phone text, mode text, needed_on date, note text, items jsonb, status text default 'Received', paid boolean default false, created_at timestamptz default now());
create table settings(key text primary key, value text);
create table admins(email text primary key, role text not null check (role in ('owner','dev')));

alter table items enable row level security;
alter table orders enable row level security;
alter table settings enable row level security;
alter table admins enable row level security;

create function is_admin() returns boolean language sql security definer stable as $$ select exists(select 1 from admins where email = auth.jwt()->>'email') $$;
create function is_dev() returns boolean language sql security definer stable as $$ select exists(select 1 from admins where email = auth.jwt()->>'email' and role = 'dev') $$;

-- Customers: see available menu items and bank details, place orders. Nothing else.
create policy "menu public" on items for select using (available = true);
create policy "menu admin" on items for all using (is_admin()) with check (is_admin());
create policy "bank public" on settings for select using (key like 'bank_%');
create policy "settings admin" on settings for all using (is_admin()) with check (is_admin());
create policy "customers place orders" on orders for insert to anon, authenticated with check (status = 'Received' and paid = false);
create policy "orders admin" on orders for all using (is_admin()) with check (is_admin());
create policy "admins read self" on admins for select using (email = auth.jwt()->>'email' or is_dev());
create policy "dev manages admins" on admins for all using (is_dev()) with check (is_dev());

-- Order tracking: needs the name AND the phone number, so nobody can browse orders.
create function track_orders(p_name text, p_phone text) returns table(status text, paid boolean, needed_on date, items jsonb, created_at timestamptz)
language sql security definer as $$
  select o.status, o.paid, o.needed_on, o.items, o.created_at from orders o
  where lower(trim(o.name)) = lower(trim(p_name)) and right(o.phone, 9) = right(regexp_replace(p_phone, '\D', '', 'g'), 9)
  order by o.created_at desc limit 5
$$;
grant execute on function track_orders(text, text) to anon, authenticated;

-- Photo storage for menu items.
insert into storage.buckets (id, name, public) values ('photos', 'photos', true);
create policy "photos admin write" on storage.objects for insert with check (bucket_id = 'photos' and is_admin());
create policy "photos admin delete" on storage.objects for delete using (bucket_id = 'photos' and is_admin());

-- Make yourself and the owner admins AFTER creating both logins in Authentication > Users.
-- insert into admins values ('your@email.com', 'dev'), ('owner@email.com', 'owner');
