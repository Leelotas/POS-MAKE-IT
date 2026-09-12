begin;

-- MAKE IT has one platform administrator. Keep the allow-list in the database so
-- UI mistakes or accidental rows in makeit_admins cannot grant elevated access.
delete from public.makeit_admins a
where not exists (
  select 1
  from auth.users u
  where u.id = a.user_id
    and lower(coalesce(u.email, '')) = 'mootor2550@gmail.com'
    and u.email_confirmed_at is not null
);

insert into public.makeit_admins(user_id)
select u.id
from auth.users u
where lower(coalesce(u.email, '')) = 'mootor2550@gmail.com'
  and u.email_confirmed_at is not null
on conflict (user_id) do nothing;

create or replace function public.makeit_enforce_single_admin()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not exists (
    select 1
    from auth.users u
    where u.id = new.user_id
      and lower(coalesce(u.email, '')) = 'mootor2550@gmail.com'
      and u.email_confirmed_at is not null
  ) then
    raise exception 'อนุญาตสิทธิ์ Admin เฉพาะ mootor2550@gmail.com เท่านั้น';
  end if;
  return new;
end
$$;

revoke all on function public.makeit_enforce_single_admin() from public, anon, authenticated;

drop trigger if exists makeit_enforce_single_admin_trigger on public.makeit_admins;
create trigger makeit_enforce_single_admin_trigger
before insert or update on public.makeit_admins
for each row execute function public.makeit_enforce_single_admin();

create or replace function public.makeit_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.makeit_admins a
    join auth.users u on u.id = a.user_id
    where a.user_id = auth.uid()
      and lower(coalesce(u.email, '')) = 'mootor2550@gmail.com'
      and u.email_confirmed_at is not null
  )
$$;

create or replace function public.makeit_admin_delete_shop(p_shop uuid, p_actor uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare shop_name text;
begin
  select name into shop_name from public.makeit_shops where id = p_shop for update;
  if shop_name is null then raise exception 'ไม่พบร้านค้า'; end if;

  if not exists (
    select 1
    from public.makeit_admins a
    join auth.users u on u.id = a.user_id
    where a.user_id = p_actor
      and lower(coalesce(u.email, '')) = 'mootor2550@gmail.com'
      and u.email_confirmed_at is not null
  ) then
    raise exception 'บัญชีนี้ไม่มีสิทธิ์ Admin';
  end if;

  insert into public.makeit_admin_deletions(shop_id, shop_name, actor_id)
  values(p_shop, shop_name, p_actor);
  delete from public.makeit_admin_audit where shop_id = p_shop;
  delete from public.makeit_cash_entries where shop_id = p_shop;
  delete from public.makeit_sale_items where shop_id = p_shop;
  delete from public.makeit_movements where shop_id = p_shop;
  delete from public.makeit_sales where shop_id = p_shop;
  delete from public.makeit_products where shop_id = p_shop;
  delete from public.makeit_shop_members where shop_id = p_shop;
  delete from public.makeit_shop_invites where shop_id = p_shop;
  delete from public.makeit_shops where id = p_shop;
  delete from public.makeit_file_gc where path like p_shop::text || '/%';
end
$$;

revoke all on function public.makeit_is_admin() from public, anon;
grant execute on function public.makeit_is_admin() to authenticated;
revoke all on function public.makeit_admin_delete_shop(uuid, uuid) from public, anon, authenticated;
grant execute on function public.makeit_admin_delete_shop(uuid, uuid) to service_role;

commit;
