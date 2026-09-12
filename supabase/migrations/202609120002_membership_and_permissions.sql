begin;

alter table public.makeit_sales drop constraint if exists makeit_sales_customer_type_check;
alter table public.makeit_sales add constraint makeit_sales_customer_type_check
 check(customer_type in ('Student','Office','Family','Other','Unspecified'));

create table public.makeit_shop_members (
 shop_id uuid not null references public.makeit_shops(id) on delete cascade,
 user_id uuid not null unique references auth.users(id) on delete cascade,
 role text not null default 'member' check(role='member'),
 joined_at timestamptz not null default now(),
 primary key(shop_id,user_id)
);
create index makeit_shop_members_shop_idx on public.makeit_shop_members(shop_id,joined_at);
alter table public.makeit_shop_members enable row level security;
revoke all on public.makeit_shop_members from public,anon,authenticated;

create table public.makeit_shop_invites (
 shop_id uuid primary key references public.makeit_shops(id) on delete cascade,
 code text not null unique check(code ~ '^[A-Z0-9]{8}$'),
 updated_at timestamptz not null default now()
);
alter table public.makeit_shop_invites enable row level security;
revoke all on public.makeit_shop_invites from public,anon,authenticated;
insert into public.makeit_shop_invites(shop_id,code)
 select id,upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)) from public.makeit_shops
on conflict(shop_id) do nothing;

create or replace function public.makeit_shop_id() returns uuid language sql stable security definer set search_path=public,pg_temp as $$
 select id from (
  select s.id,0 priority from public.makeit_shops s where s.owner_id=auth.uid()
  union all
  select m.shop_id,1 from public.makeit_shop_members m where m.user_id=auth.uid()
 ) access order by priority limit 1
$$;
create or replace function public.makeit_access_role() returns text language sql stable security definer set search_path=public,pg_temp as $$
 select case
  when exists(select 1 from public.makeit_shops where owner_id=auth.uid()) then 'owner'
  when exists(select 1 from public.makeit_shop_members where user_id=auth.uid()) then 'member'
  else 'none' end
$$;
revoke all on function public.makeit_access_role() from public,anon,authenticated;
grant execute on function public.makeit_access_role() to authenticated;

create or replace function public.makeit_lock_shop() returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare s uuid:=public.makeit_shop_id();
begin
 if s is null then raise exception 'กรุณาเลือกร้านหรือสร้างร้านก่อน'; end if;
 perform 1 from public.makeit_shops where id=s for update;
 return s;
end $$;

drop policy if exists shop_read on public.makeit_shops;
create policy shop_read on public.makeit_shops for select to authenticated using(id=public.makeit_shop_id());

create or replace function public.makeit_setup_shop(p_name text) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare s uuid; begin
 if auth.uid() is null then raise exception 'กรุณาเข้าสู่ระบบ'; end if;
 if exists(select 1 from public.makeit_shop_members where user_id=auth.uid()) then raise exception 'บัญชีนี้เป็นสมาชิกของร้านอยู่แล้ว'; end if;
 insert into public.makeit_shops(owner_id,name) values(auth.uid(),trim(p_name))
 on conflict(owner_id) do update set name=excluded.name returning id into s;
 insert into public.makeit_shop_invites(shop_id,code) values(s,upper(substr(replace(gen_random_uuid()::text,'-',''),1,8))) on conflict(shop_id) do nothing;
 return s;
end $$;

create function public.makeit_join_shop(p_code text) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare s uuid; begin
 if auth.uid() is null then raise exception 'กรุณาเข้าสู่ระบบ'; end if;
 if exists(select 1 from public.makeit_shops where owner_id=auth.uid()) then raise exception 'บัญชีเจ้าของร้านไม่สามารถเข้าร่วมร้านอื่นได้'; end if;
 if exists(select 1 from public.makeit_shop_members where user_id=auth.uid()) then raise exception 'บัญชีนี้เป็นสมาชิกของร้านอยู่แล้ว'; end if;
 select shop_id into s from public.makeit_shop_invites where code=upper(trim(coalesce(p_code,'')));
 if s is null then raise exception 'รหัสร้านไม่ถูกต้อง กรุณาตรวจสอบอีกครั้ง'; end if;
 insert into public.makeit_shop_members(shop_id,user_id) values(s,auth.uid());
 return s;
end $$;

create function public.makeit_regenerate_join_code() returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare s uuid; new_code text; begin
 select id into s from public.makeit_shops where owner_id=auth.uid() for update;
 if s is null then raise exception 'เฉพาะเจ้าของร้านเท่านั้นที่เปลี่ยนรหัสได้'; end if;
 loop
  new_code:=upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
  begin
   insert into public.makeit_shop_invites(shop_id,code,updated_at) values(s,new_code,now())
   on conflict(shop_id) do update set code=excluded.code,updated_at=now();
   exit;
  exception when unique_violation then null;
  end;
 end loop;
 return new_code;
end $$;

create function public.makeit_remove_member(p_user uuid) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare s uuid; begin
 select id into s from public.makeit_shops where owner_id=auth.uid();
 if s is null then raise exception 'เฉพาะเจ้าของร้านเท่านั้นที่จัดการสมาชิกได้'; end if;
 delete from public.makeit_shop_members where shop_id=s and user_id=p_user;
 if not found then raise exception 'ไม่พบสมาชิกในร้าน'; end if;
end $$;

create function public.makeit_leave_shop() returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 delete from public.makeit_shop_members where user_id=auth.uid();
 if not found then raise exception 'บัญชีนี้ไม่ได้เป็นสมาชิกของร้าน'; end if;
end $$;

create or replace function public.makeit_snapshot() returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare s uuid:=public.makeit_shop_id(); role_name text:=public.makeit_access_role(); begin
 return jsonb_build_object(
 'shop',(select jsonb_build_object('id',x.id,'name',x.name,'owner_id',x.owner_id,'created_at',x.created_at) from public.makeit_shops x where x.id=s),
 'access',case when s is null then null else jsonb_build_object('role',role_name,'can_export',role_name='owner','join_code',case when role_name='owner' then (select code from public.makeit_shop_invites where shop_id=s) end) end,
 'members',case when role_name='owner' then coalesce((select jsonb_agg(row_data order by row_data->>'role',row_data->>'email') from (
   select jsonb_build_object('user_id',u.id,'email',u.email,'role','owner','joined_at',x.created_at) row_data from public.makeit_shops x join auth.users u on u.id=x.owner_id where x.id=s
   union all
   select jsonb_build_object('user_id',u.id,'email',u.email,'role','member','joined_at',m.joined_at) from public.makeit_shop_members m join auth.users u on u.id=m.user_id where m.shop_id=s
  ) members),'[]'::jsonb) else '[]'::jsonb end,
 'products',coalesce((select jsonb_agg(p order by p.created_at desc) from public.makeit_products p where p.shop_id=s),'[]'::jsonb),
 'sales',coalesce((select jsonb_agg(b order by b.created_at desc) from public.makeit_sales b where b.shop_id=s),'[]'::jsonb),
 'items',coalesce((select jsonb_agg(i) from public.makeit_sale_items i where i.shop_id=s),'[]'::jsonb),
 'entries',coalesce((select jsonb_agg(e order by e.occurred_at desc) from public.makeit_cash_entries e where e.shop_id=s),'[]'::jsonb),
 'movements',coalesce((select jsonb_agg(m order by m.created_at desc) from public.makeit_movements m where m.shop_id=s),'[]'::jsonb));
end $$;

create or replace function public.makeit_checkout_v2(p_request uuid,p_items jsonb,p_payment text,p_slip text,p_sold_at timestamptz,p_customer_type text,p_time_source text,p_ocr_detected_at timestamptz default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare s uuid:=public.makeit_lock_shop(); r record; p public.makeit_products; total numeric:=0; cost numeric:=0; begin
 if exists(select 1 from public.makeit_sales where id=p_request and shop_id=s) then return p_request; end if;
 if p_payment is null or p_payment not in ('cash','transfer') then raise exception 'เลือกวิธีชำระเงิน'; end if;
 if p_payment='transfer' and p_slip is null then raise exception 'กรุณาแนบสลิป'; end if;
 if p_sold_at is null or p_sold_at>now()+interval '10 minutes' then raise exception 'เวลาขายไม่ถูกต้อง'; end if;
 if p_customer_type is null or p_customer_type not in ('Student','Office','Family','Other') then raise exception 'กรุณาเลือกประเภทลูกค้า'; end if;
 if p_time_source is null or p_time_source not in ('manual','slip_ocr') then raise exception 'แหล่งที่มาของเวลาไม่ถูกต้อง'; end if;
 if p_time_source='slip_ocr' and (p_payment<>'transfer' or p_slip is null or p_ocr_detected_at is null) then raise exception 'กรุณาอ่านเวลาในสลิปก่อนบันทึก'; end if;
 perform public.makeit_check_file(p_slip);
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'ตะกร้าว่าง'; end if;
 if exists(select 1 from jsonb_to_recordset(p_items) as x(id uuid,quantity numeric) where quantity is null or quantity<=0 or quantity<>trunc(quantity) or quantity>2147483647 or id is null) then raise exception 'จำนวนสินค้าไม่ถูกต้อง'; end if;
 for r in select x.id,sum(x.quantity)::integer quantity from jsonb_to_recordset(p_items) as x(id uuid,quantity numeric) group by x.id order by x.id loop
  select * into p from public.makeit_products where id=r.id and shop_id=s for update;
  if not found then raise exception 'ไม่พบสินค้าในร้าน'; end if;
  if not p.active or p.stock<r.quantity then raise exception 'สินค้า % มีไม่เพียงพอหรือปิดการขายแล้ว',p.name; end if;
  total:=total+p.price*r.quantity;cost:=cost+p.average_cost*r.quantity;
 end loop;
 insert into public.makeit_sales(id,shop_id,payment,slip_path,total,cost,created_at,customer_type,time_source,ocr_detected_at)
 values(p_request,s,p_payment,p_slip,total,cost,p_sold_at,p_customer_type,p_time_source,case when p_time_source='slip_ocr' then p_ocr_detected_at end);
 for r in select x.id,sum(x.quantity)::integer quantity from jsonb_to_recordset(p_items) as x(id uuid,quantity numeric) group by x.id order by x.id loop
  select * into p from public.makeit_products where id=r.id and shop_id=s;
  insert into public.makeit_sale_items(shop_id,sale_id,product_id,name,quantity,price,cost) values(s,p_request,p.id,p.name,r.quantity,p.price,p.average_cost);
  update public.makeit_products set stock=stock-r.quantity where id=p.id;
  insert into public.makeit_movements(shop_id,product_id,kind,quantity,unit_cost,sale_id) values(s,p.id,'sale',-r.quantity,p.average_cost,p_request);
 end loop;
 return p_request;
end $$;

create or replace function public.makeit_admin_overview(p_search text default '',p_offset integer default 0) returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare result jsonb; begin
 perform public.makeit_require_admin();
 with shops as (
  select s.*,u.email from public.makeit_shops s join auth.users u on u.id=s.owner_id
  where s.name ilike '%'||coalesce(p_search,'')||'%' or u.email ilike '%'||coalesce(p_search,'')||'%'
 ), selected as (select * from shops order by created_at desc,id limit 30 offset greatest(0,coalesce(p_offset,0))),
 rows as (
  select s.*,
   (select count(*) from public.makeit_products p where p.shop_id=s.id) product_count,
   (select count(*) from public.makeit_shop_members m where m.shop_id=s.id) member_count,
   (select count(*) from public.makeit_sales b where b.shop_id=s.id and b.voided_at is null) sale_count,
   (select coalesce(sum(total),0) from public.makeit_sales b where b.shop_id=s.id and b.voided_at is null) revenue,
   greatest(s.created_at,(select max(created_at) from public.makeit_sales b where b.shop_id=s.id),(select max(joined_at) from public.makeit_shop_members m where m.shop_id=s.id),
    (select max(created_at) from public.makeit_movements m where m.shop_id=s.id),(select max(created_at) from public.makeit_cash_entries e where e.shop_id=s.id),
    (select max(created_at) from public.makeit_admin_audit a where a.shop_id=s.id)) last_activity
  from selected s
 ) select jsonb_build_object(
  'total_shops',(select count(*) from public.makeit_shops),'matched_shops',(select count(*) from shops),
  'total_members',(select count(*) from public.makeit_shop_members),'total_sales',(select count(*) from public.makeit_sales where voided_at is null),
  'total_revenue',(select coalesce(sum(total),0) from public.makeit_sales where voided_at is null),'total_corrections',(select count(*) from public.makeit_admin_audit),
  'shops',coalesce((select jsonb_agg(r order by r.created_at desc,r.id) from rows r),'[]'::jsonb)) into result;
 return result;
end $$;

create or replace function public.makeit_admin_shop(p_shop uuid) returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 perform public.makeit_require_admin();
 if not exists(select 1 from public.makeit_shops where id=p_shop) then raise exception 'ไม่พบร้านค้า'; end if;
 return jsonb_build_object(
 'shop',(select to_jsonb(s) from public.makeit_shops s where id=p_shop),
 'owner_email',(select u.email from auth.users u join public.makeit_shops s on s.owner_id=u.id where s.id=p_shop),
 'members',coalesce((select jsonb_agg(member_row order by member_row->>'role',member_row->>'email') from (
   select jsonb_build_object('user_id',u.id,'email',u.email,'role','owner','joined_at',s.created_at) member_row from public.makeit_shops s join auth.users u on u.id=s.owner_id where s.id=p_shop
   union all
   select jsonb_build_object('user_id',u.id,'email',u.email,'role','member','joined_at',m.joined_at) from public.makeit_shop_members m join auth.users u on u.id=m.user_id where m.shop_id=p_shop
  ) x),'[]'::jsonb),
 'products',coalesce((select jsonb_agg(p order by p.created_at desc) from public.makeit_products p where shop_id=p_shop),'[]'::jsonb),
 'sales',coalesce((select jsonb_agg(s order by s.created_at desc) from public.makeit_sales s where shop_id=p_shop),'[]'::jsonb),
 'items',coalesce((select jsonb_agg(i) from public.makeit_sale_items i where shop_id=p_shop),'[]'::jsonb),
 'entries',coalesce((select jsonb_agg(e order by e.occurred_at desc) from public.makeit_cash_entries e where shop_id=p_shop),'[]'::jsonb),
 'movements',coalesce((select jsonb_agg(m order by m.created_at desc) from public.makeit_movements m where shop_id=p_shop),'[]'::jsonb),
 'audit',coalesce((select jsonb_agg(a order by a.created_at desc) from public.makeit_admin_audit a where shop_id=p_shop),'[]'::jsonb));
end $$;

create function public.makeit_admin_add_member(p_shop uuid,p_email text) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare target uuid; audit_id uuid; begin
 perform public.makeit_require_admin();
 select id into target from auth.users where lower(email)=lower(trim(p_email)) and email_confirmed_at is not null;
 if target is null then raise exception 'ไม่พบบัญชีที่ยืนยันอีเมลแล้ว'; end if;
 if exists(select 1 from public.makeit_shops where owner_id=target) then raise exception 'บัญชีนี้เป็นเจ้าของร้านอยู่แล้ว'; end if;
 if exists(select 1 from public.makeit_shop_members where user_id=target) then raise exception 'บัญชีนี้เป็นสมาชิกของร้านอยู่แล้ว'; end if;
 if not exists(select 1 from public.makeit_shops where id=p_shop) then raise exception 'ไม่พบร้านค้า'; end if;
 insert into public.makeit_shop_members(shop_id,user_id) values(p_shop,target);
 insert into public.makeit_admin_audit(request_id,shop_id,actor_id,action,target_id,reason,before_data,after_data)
 values(gen_random_uuid(),p_shop,auth.uid(),'member_add',target,'เพิ่มสมาชิก '||trim(p_email),'{}',jsonb_build_object('user_id',target,'email',trim(p_email),'role','member')) returning id into audit_id;
 return target;
end $$;

create function public.makeit_admin_remove_member(p_shop uuid,p_user uuid) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare old_member jsonb; begin
 perform public.makeit_require_admin();
 select jsonb_build_object('user_id',u.id,'email',u.email,'role','member') into old_member from public.makeit_shop_members m join auth.users u on u.id=m.user_id where m.shop_id=p_shop and m.user_id=p_user;
 if old_member is null then raise exception 'ไม่พบสมาชิกในร้าน'; end if;
 delete from public.makeit_shop_members where shop_id=p_shop and user_id=p_user;
 insert into public.makeit_admin_audit(request_id,shop_id,actor_id,action,target_id,reason,before_data,after_data)
 values(gen_random_uuid(),p_shop,auth.uid(),'member_remove',p_user,'ถอดสมาชิกออกจากร้าน',old_member,'{}');
end $$;

create table public.makeit_admin_deletions (
 id uuid primary key default gen_random_uuid(),shop_id uuid not null,shop_name text not null,
 actor_id uuid not null references auth.users(id),deleted_at timestamptz not null default now()
);
alter table public.makeit_admin_deletions enable row level security;
revoke all on public.makeit_admin_deletions from public,anon,authenticated;

create function public.makeit_admin_delete_shop(p_shop uuid,p_actor uuid) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare shop_name text; begin
 select name into shop_name from public.makeit_shops where id=p_shop for update;
 if shop_name is null then raise exception 'ไม่พบร้านค้า'; end if;
 if not exists(select 1 from public.makeit_admins where user_id=p_actor) then raise exception 'บัญชีนี้ไม่มีสิทธิ์ Admin'; end if;
 insert into public.makeit_admin_deletions(shop_id,shop_name,actor_id) values(p_shop,shop_name,p_actor);
 delete from public.makeit_admin_audit where shop_id=p_shop;
 delete from public.makeit_cash_entries where shop_id=p_shop;
 delete from public.makeit_sale_items where shop_id=p_shop;
 delete from public.makeit_movements where shop_id=p_shop;
 delete from public.makeit_sales where shop_id=p_shop;
 delete from public.makeit_products where shop_id=p_shop;
 delete from public.makeit_shop_members where shop_id=p_shop;
 delete from public.makeit_shop_invites where shop_id=p_shop;
 delete from public.makeit_shops where id=p_shop;
 delete from public.makeit_file_gc where path like p_shop::text||'/%';
end $$;

create or replace function public.makeit_admin_mutate(p_request uuid,p_shop uuid,p_action text,p_target uuid,p_expected jsonb,p_data jsonb,p_reason text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare result jsonb; source_sale public.makeit_sales; updated_after jsonb; begin
 perform public.makeit_require_admin();
 select * into source_sale from public.makeit_sales where id=p_target and shop_id=p_shop;
 result:=public.makeit_admin_mutate_core(p_request,p_shop,p_action,p_target,p_expected,p_data,p_reason);
 if p_action='sale' and exists(select 1 from public.makeit_sales where id=p_request and shop_id=p_shop) then
  update public.makeit_sales set
   customer_type=case when coalesce(p_data->>'customer_type',source_sale.customer_type) in ('Student','Office','Family','Other','Unspecified') then coalesce(p_data->>'customer_type',source_sale.customer_type) else 'Unspecified' end,
   time_source=case when coalesce(p_data->>'time_source',source_sale.time_source) in ('system','manual','slip_ocr') then coalesce(p_data->>'time_source',source_sale.time_source) else 'manual' end,
   ocr_detected_at=source_sale.ocr_detected_at where id=p_request and shop_id=p_shop;
  updated_after:=jsonb_build_object('replaces_sale_id',p_target,'sale',(select to_jsonb(s) from public.makeit_sales s where id=p_request),'items',(select jsonb_agg(si) from public.makeit_sale_items si where sale_id=p_request));
  update public.makeit_admin_audit set after_data=updated_after where request_id=p_request;
  result:=jsonb_build_object('audit_id',(select id from public.makeit_admin_audit where request_id=p_request),'after',updated_after);
 end if;
 return result;
end $$;

revoke all on function public.makeit_join_shop(text),public.makeit_regenerate_join_code(),public.makeit_remove_member(uuid),public.makeit_leave_shop(),public.makeit_admin_add_member(uuid,text),public.makeit_admin_remove_member(uuid,uuid),public.makeit_admin_delete_shop(uuid,uuid) from public,anon,authenticated;
grant execute on function public.makeit_join_shop(text),public.makeit_regenerate_join_code(),public.makeit_remove_member(uuid),public.makeit_leave_shop() to authenticated;
grant execute on function public.makeit_admin_add_member(uuid,text),public.makeit_admin_remove_member(uuid,uuid) to authenticated;
grant execute on function public.makeit_admin_delete_shop(uuid,uuid) to service_role;

commit;
