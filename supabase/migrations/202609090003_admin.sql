begin;

create table public.makeit_admins (
 user_id uuid primary key references auth.users(id), created_at timestamptz not null default now()
);
alter table public.makeit_admins enable row level security;
revoke all on public.makeit_admins from public,anon,authenticated;

create table public.makeit_admin_audit (
 id uuid primary key default gen_random_uuid(), request_id uuid not null unique,
 shop_id uuid not null references public.makeit_shops(id), actor_id uuid not null references auth.users(id),
 action text not null, target_id uuid not null, reason text not null check(length(trim(reason)) between 1 and 500),
 before_data jsonb not null, after_data jsonb not null, created_at timestamptz not null default now()
);
alter table public.makeit_admin_audit enable row level security;
revoke all on public.makeit_admin_audit from public,anon,authenticated;
create index on public.makeit_admin_audit(shop_id,created_at desc);
create index on public.makeit_admin_audit(actor_id);

create function public.makeit_is_admin() returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select exists(select 1 from public.makeit_admins a join auth.users u on u.id=a.user_id
  where a.user_id=auth.uid() and u.email_confirmed_at is not null)
$$;
create function public.makeit_require_admin() returns void language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if not public.makeit_is_admin() then raise exception 'บัญชีนี้ไม่มีสิทธิ์ Admin' using errcode='42501'; end if;
end $$;

create function public.makeit_admin_overview(p_search text default '',p_offset integer default 0) returns jsonb
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
   (select count(*) from public.makeit_sales b where b.shop_id=s.id and b.voided_at is null) sale_count,
   (select coalesce(sum(total),0) from public.makeit_sales b where b.shop_id=s.id and b.voided_at is null) revenue,
   greatest(s.created_at,(select max(created_at) from public.makeit_sales b where b.shop_id=s.id),
    (select max(created_at) from public.makeit_movements m where m.shop_id=s.id),
    (select max(created_at) from public.makeit_cash_entries e where e.shop_id=s.id),
    (select max(created_at) from public.makeit_admin_audit a where a.shop_id=s.id)) last_activity
  from selected s
 ) select jsonb_build_object(
  'total_shops',(select count(*) from public.makeit_shops),
  'matched_shops',(select count(*) from shops),
  'total_sales',(select count(*) from public.makeit_sales where voided_at is null),
  'total_revenue',(select coalesce(sum(total),0) from public.makeit_sales where voided_at is null),
  'total_corrections',(select count(*) from public.makeit_admin_audit),
  'shops',coalesce((select jsonb_agg(r order by r.created_at desc,r.id) from rows r),'[]'::jsonb)
 ) into result;
 return result;
end $$;

create function public.makeit_admin_shop(p_shop uuid) returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 perform public.makeit_require_admin();
 if not exists(select 1 from public.makeit_shops where id=p_shop) then raise exception 'ไม่พบร้านค้า'; end if;
 return jsonb_build_object(
 'shop',(select to_jsonb(s) from public.makeit_shops s where id=p_shop),
 'owner_email',(select u.email from auth.users u join public.makeit_shops s on s.owner_id=u.id where s.id=p_shop),
 'products',coalesce((select jsonb_agg(p order by p.created_at desc) from public.makeit_products p where shop_id=p_shop),'[]'::jsonb),
 'sales',coalesce((select jsonb_agg(s order by s.created_at desc) from public.makeit_sales s where shop_id=p_shop),'[]'::jsonb),
 'items',coalesce((select jsonb_agg(i) from public.makeit_sale_items i where shop_id=p_shop),'[]'::jsonb),
 'entries',coalesce((select jsonb_agg(e order by e.occurred_at desc) from public.makeit_cash_entries e where shop_id=p_shop),'[]'::jsonb),
 'movements',coalesce((select jsonb_agg(m order by m.created_at desc) from public.makeit_movements m where shop_id=p_shop),'[]'::jsonb),
 'audit',coalesce((select jsonb_agg(a order by a.created_at desc) from public.makeit_admin_audit a where shop_id=p_shop),'[]'::jsonb));
end $$;

create function public.makeit_admin_check_file(p_shop uuid,p_path text) returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if p_path is not null and (split_part(p_path,'/',1) is distinct from p_shop::text or
  not exists(select 1 from storage.objects where bucket_id='makeit-private' and name=p_path) or
  exists(select 1 from public.makeit_file_gc where path=p_path)) then raise exception 'ไม่พบภาพหลักฐานของร้านนี้'; end if;
end $$;

-- Undo stock at the historical cost; callable only from the protected transaction below.
create function public.makeit_admin_restore_sale(p_sale uuid,p_reason text) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare i record; p public.makeit_products; begin
 for i in select * from public.makeit_sale_items where sale_id=p_sale order by product_id loop
  select * into strict p from public.makeit_products where id=i.product_id for update;
  update public.makeit_products set average_cost=(p.stock*p.average_cost+i.quantity*i.cost)/(p.stock+i.quantity),stock=p.stock+i.quantity where id=p.id;
  insert into public.makeit_movements(shop_id,product_id,kind,quantity,unit_cost,reason,sale_id)
  values(p.shop_id,p.id,'void',i.quantity,i.cost,p_reason,p_sale);
 end loop;
 update public.makeit_sales set voided_at=now(),void_reason=p_reason where id=p_sale;
end $$;

create function public.makeit_admin_mutate(p_request uuid,p_shop uuid,p_action text,p_target uuid,p_expected jsonb,p_data jsonb,p_reason text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
 shop public.makeit_shops; product public.makeit_products; entry public.makeit_cash_entries; sale public.makeit_sales;
 prior public.makeit_admin_audit; before_json jsonb; after_json jsonb; audit_id uuid;
 i record; old_i public.makeit_sale_items; original_stock jsonb; p_price numeric; p_qty integer;
 p_cost numeric; pool_cost numeric; total numeric:=0; total_cost numeric:=0; remaining_value numeric;
 new_sale uuid; new_payment text; new_time timestamptz; new_slip text; prepared jsonb:='[]'::jsonb;
begin
 perform public.makeit_require_admin();
 if p_request is null or p_target is null or p_data is null or jsonb_typeof(p_data)<>'object' or length(trim(coalesce(p_reason,''))) not between 1 and 500 then
  raise exception 'กรุณาระบุข้อมูลและเหตุผลการแก้ไข';
 end if;
 select * into shop from public.makeit_shops where id=p_shop for update;
 if not found then raise exception 'ไม่พบร้านค้า'; end if;
 select * into prior from public.makeit_admin_audit where request_id=p_request;
 if found then
  if prior.actor_id<>auth.uid() or prior.shop_id<>p_shop or prior.action<>p_action or prior.target_id<>p_target then raise exception 'รหัสคำขอถูกใช้แล้ว'; end if;
  return jsonb_build_object('audit_id',prior.id,'after',prior.after_data);
 end if;

 if p_action='shop' then
  if p_target<>p_shop then raise exception 'ร้านค้าไม่ตรงกัน'; end if;
  before_json:=to_jsonb(shop);
  if p_expected is distinct from before_json then raise exception 'ข้อมูลเปลี่ยนแล้ว กรุณาปิดหน้าต่างและโหลดข้อมูลใหม่'; end if;
  update public.makeit_shops set name=trim(p_data->>'name') where id=p_shop returning to_jsonb(makeit_shops.*) into after_json;

 elsif p_action='product' then
  select * into product from public.makeit_products where id=p_target and shop_id=p_shop for update;
  if not found then raise exception 'ไม่พบสินค้าในร้านนี้'; end if;
  before_json:=to_jsonb(product);
  if p_expected is distinct from before_json then raise exception 'สินค้าเปลี่ยนแล้ว กรุณาปิดหน้าต่างและโหลดข้อมูลใหม่'; end if;
  if (p_data->>'stock')::numeric<>trunc((p_data->>'stock')::numeric) then raise exception 'จำนวนสินค้าต้องเป็นจำนวนเต็ม'; end if;
  p_qty:=(p_data->>'stock')::integer;p_cost:=(p_data->>'average_cost')::numeric;
  update public.makeit_products set name=trim(p_data->>'name'),category=trim(coalesce(p_data->>'category','')),
   price=(p_data->>'price')::numeric,stock=p_qty,average_cost=p_cost,active=(p_data->>'active')::boolean
   where id=p_target returning to_jsonb(makeit_products.*) into after_json;
  if product.stock<>p_qty or product.average_cost<>p_cost then
   insert into public.makeit_movements(shop_id,product_id,kind,quantity,unit_cost,reason,request_id)
   values(p_shop,p_target,'adjustment',p_qty-product.stock,p_cost,'Admin: '||trim(p_reason),p_request);
  end if;

 elsif p_action='entry' then
  select * into entry from public.makeit_cash_entries where id=p_target and shop_id=p_shop for update;
  if not found then raise exception 'ไม่พบรายการเงินของร้านนี้'; end if;
  before_json:=to_jsonb(entry);
  if p_expected is distinct from before_json then raise exception 'รายการเปลี่ยนแล้ว กรุณาปิดหน้าต่างและโหลดข้อมูลใหม่'; end if;
  if (entry.kind='purchase' and p_data->>'kind' is distinct from 'purchase') or
   (entry.kind<>'purchase' and coalesce(p_data->>'kind','') not in ('income','expense')) then raise exception 'ประเภทของรายการไม่ถูกต้อง'; end if;
  if length(trim(coalesce(p_data->>'category','')))=0 then raise exception 'กรุณาระบุหมวดหมู่'; end if;
  update public.makeit_cash_entries set kind=p_data->>'kind',category=trim(p_data->>'category'),amount=(p_data->>'amount')::numeric,
   note=coalesce(p_data->>'note',''),occurred_at=(p_data->>'occurred_at')::timestamptz
   where id=p_target returning to_jsonb(makeit_cash_entries.*) into after_json;

 elsif p_action in ('sale','void_sale') then
  select * into sale from public.makeit_sales where id=p_target and shop_id=p_shop for update;
  if not found then raise exception 'ไม่พบบิลในร้านนี้'; end if;
  if p_expected is distinct from to_jsonb(sale) then raise exception 'บิลเปลี่ยนแล้ว กรุณาปิดหน้าต่างและโหลดข้อมูลใหม่'; end if;
  if sale.voided_at is not null then raise exception 'บิลนี้ยกเลิกแล้ว'; end if;
  before_json:=jsonb_build_object('sale',to_jsonb(sale),'items',(select jsonb_agg(si) from public.makeit_sale_items si where sale_id=p_target));
  if p_action='void_sale' then
   perform public.makeit_admin_restore_sale(p_target,'Admin: '||trim(p_reason));
   select to_jsonb(s) into after_json from public.makeit_sales s where id=p_target;
  else
   if jsonb_typeof(p_data->'items') is distinct from 'array' or jsonb_array_length(p_data->'items')=0 then raise exception 'กรุณาเพิ่มสินค้าในบิล'; end if;
   if exists(select 1 from jsonb_to_recordset(p_data->'items') x(id uuid,quantity numeric,price numeric) where id is null or quantity is null or quantity<=0 or quantity<>trunc(quantity) or quantity>10000000 or price is null or price<0 or price>=1000000000000) then raise exception 'จำนวนหรือราคาสินค้าไม่ถูกต้อง'; end if;
   if (select count(*) from jsonb_to_recordset(p_data->'items') x(id uuid))<>(select count(distinct id) from jsonb_to_recordset(p_data->'items') x(id uuid)) then raise exception 'สินค้าในบิลซ้ำกัน'; end if;
   new_payment:=p_data->>'payment';new_time:=(p_data->>'created_at')::timestamptz;new_slip:=nullif(p_data->>'slip_path','');
   if new_payment is null or new_payment not in ('cash','transfer') or new_time is null then raise exception 'วิธีชำระหรือเวลาไม่ถูกต้อง'; end if;
   if new_payment='transfer' and new_slip is null then raise exception 'บิลเงินโอนต้องแนบสลิป'; end if;
   perform public.makeit_admin_check_file(p_shop,new_slip);
   select jsonb_object_agg(id,to_jsonb(p)) into original_stock from public.makeit_products p where shop_id=p_shop;
   perform public.makeit_admin_restore_sale(p_target,'Admin แก้ไขบิล: '||trim(p_reason));
   new_sale:=p_request;
   for i in select * from jsonb_to_recordset(p_data->'items') x(id uuid,quantity integer,price numeric) order by id loop
    select * into product from public.makeit_products where id=i.id and shop_id=p_shop for update;
    if not found then raise exception 'ไม่พบสินค้าในร้านนี้'; end if;
    if product.stock<i.quantity then raise exception 'สินค้า % คงเหลือไม่เพียงพอ',product.name; end if;
    select * into old_i from public.makeit_sale_items where sale_id=p_target and product_id=i.id;
    if not product.active and old_i.id is null then raise exception 'สินค้าใหม่ที่เพิ่มในบิลต้องเปิดขาย'; end if;
    -- Preserve original cost for the original quantity; only additional units use the
    -- current pool's cost. The remainder's weighted cost follows its actual value.
    pool_cost:=(original_stock->i.id::text->>'average_cost')::numeric;
    p_cost:=round((least(i.quantity,coalesce(old_i.quantity,0))*coalesce(old_i.cost,0)+greatest(i.quantity-coalesce(old_i.quantity,0),0)*pool_cost)/i.quantity,6);
    remaining_value:=product.stock*product.average_cost-i.quantity*p_cost;
    if remaining_value < -0.01 then raise exception 'ต้นทุนคงเหลือไม่ถูกต้อง กรุณาตรวจสต็อก'; end if;
    update public.makeit_products set stock=stock-i.quantity,average_cost=case when stock=i.quantity then p_cost else greatest(0,remaining_value)/(stock-i.quantity) end where id=i.id;
    p_price:=round(i.price,2);total:=total+i.quantity*p_price;total_cost:=total_cost+i.quantity*p_cost;
    prepared:=prepared||jsonb_build_array(jsonb_build_object('id',i.id,'name',coalesce(old_i.name,product.name),'quantity',i.quantity,'price',p_price,'cost',p_cost));
   end loop;
   insert into public.makeit_sales(id,shop_id,payment,slip_path,total,cost,created_at) values(new_sale,p_shop,new_payment,new_slip,total,total_cost,new_time);
   for i in select * from jsonb_to_recordset(prepared) x(id uuid,name text,quantity integer,price numeric,cost numeric) loop
    insert into public.makeit_sale_items(shop_id,sale_id,product_id,name,quantity,price,cost) values(p_shop,new_sale,i.id,i.name,i.quantity,i.price,i.cost);
    insert into public.makeit_movements(shop_id,product_id,kind,quantity,unit_cost,reason,sale_id) values(p_shop,i.id,'sale',-i.quantity,i.cost,'Admin แก้ไขบิล: '||trim(p_reason),new_sale);
   end loop;
   after_json:=jsonb_build_object('replaces_sale_id',p_target,'sale',(select to_jsonb(s) from public.makeit_sales s where id=new_sale),'items',(select jsonb_agg(si) from public.makeit_sale_items si where sale_id=new_sale));
  end if;
 else raise exception 'ไม่รองรับการแก้ไขนี้'; end if;

 insert into public.makeit_admin_audit(request_id,shop_id,actor_id,action,target_id,reason,before_data,after_data)
 values(p_request,p_shop,auth.uid(),p_action,p_target,trim(p_reason),before_json,after_json) returning id into audit_id;
 return jsonb_build_object('audit_id',audit_id,'after',after_json);
end $$;

revoke all on function public.makeit_is_admin(),public.makeit_require_admin(),public.makeit_admin_overview(text,integer),public.makeit_admin_shop(uuid),public.makeit_admin_check_file(uuid,text),public.makeit_admin_restore_sale(uuid,text),public.makeit_admin_mutate(uuid,uuid,text,uuid,jsonb,jsonb,text) from public,anon,authenticated;
grant execute on function public.makeit_is_admin(),public.makeit_admin_overview(text,integer),public.makeit_admin_shop(uuid),public.makeit_admin_mutate(uuid,uuid,text,uuid,jsonb,jsonb,text) to authenticated;
create policy makeit_admin_file_read on storage.objects for select to authenticated
 using(bucket_id='makeit-private' and public.makeit_is_admin());
create function public.makeit_admin_shop_exists(p_id text) returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select public.makeit_is_admin() and exists(select 1 from public.makeit_shops where id::text=p_id)
$$;
revoke all on function public.makeit_admin_shop_exists(text) from public,anon;
grant execute on function public.makeit_admin_shop_exists(text) to authenticated;
create policy makeit_admin_file_upload on storage.objects for insert to authenticated
 with check(bucket_id='makeit-private' and public.makeit_admin_shop_exists((storage.foldername(name))[1]));
commit;

