begin;
create table public.makeit_shops (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null unique references auth.users(id),
 name text not null check(length(trim(name)) between 1 and 100), created_at timestamptz not null default now()
);
create table public.makeit_products (
 id uuid primary key default gen_random_uuid(), shop_id uuid not null references public.makeit_shops(id),
 name text not null check(length(trim(name)) between 1 and 160), category text not null default '', image_path text,
 price numeric(14,2) not null check(price>=0), average_cost numeric(18,6) not null check(average_cost>=0),
 stock integer not null default 0 check(stock>=0), active boolean not null default true,
 created_at timestamptz not null default now(), unique(shop_id,id)
);
create table public.makeit_sales (
 id uuid primary key, shop_id uuid not null references public.makeit_shops(id),
 bill_no bigint generated always as identity unique, payment text not null check(payment in ('cash','transfer')),
 slip_path text, total numeric(14,2) not null, cost numeric(18,6) not null,
 created_at timestamptz not null default now(), voided_at timestamptz, void_reason text,
 check(payment='cash' or slip_path is not null), unique(shop_id,id)
);
create table public.makeit_sale_items (
 id uuid primary key default gen_random_uuid(), shop_id uuid not null,
 sale_id uuid not null, product_id uuid not null, name text not null,
 quantity integer not null check(quantity>0), price numeric(14,2) not null, cost numeric(18,6) not null,
 foreign key(shop_id,sale_id) references public.makeit_sales(shop_id,id),
 foreign key(shop_id,product_id) references public.makeit_products(shop_id,id), unique(sale_id,product_id)
);
create table public.makeit_movements (
 id uuid primary key default gen_random_uuid(), shop_id uuid not null, product_id uuid not null,
 kind text not null check(kind in ('opening','purchase','adjustment','sale','void')),
 quantity integer not null, unit_cost numeric(18,6) not null, reason text not null default '',
 sale_id uuid, request_id uuid, created_at timestamptz not null default now(),
 foreign key(shop_id,product_id) references public.makeit_products(shop_id,id),
 foreign key(shop_id,sale_id) references public.makeit_sales(shop_id,id), unique(shop_id,request_id)
);
create table public.makeit_cash_entries (
 id uuid primary key, shop_id uuid not null references public.makeit_shops(id),
 kind text not null check(kind in ('income','expense','purchase')), category text not null,
 amount numeric(14,2) not null check(amount>0), note text not null default '', evidence_path text,
 occurred_at timestamptz not null default now(), created_at timestamptz not null default now(),
 movement_id uuid references public.makeit_movements(id)
);
create index on public.makeit_products(shop_id);
create index on public.makeit_sales(shop_id,created_at);
create index on public.makeit_sale_items(shop_id);
create index on public.makeit_movements(shop_id,created_at);
create index on public.makeit_cash_entries(shop_id,occurred_at);
create unique index makeit_purchase_payment_once on public.makeit_cash_entries(movement_id) where movement_id is not null;
create table public.makeit_file_gc(path text primary key, marked_at timestamptz not null default now());
alter table public.makeit_file_gc enable row level security;
revoke all on public.makeit_file_gc from public,anon,authenticated;

create function public.makeit_shop_id() returns uuid language sql stable security definer set search_path=public,pg_temp as $$
 select id from public.makeit_shops where owner_id=auth.uid()
$$;
create function public.makeit_lock_shop() returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare s uuid;
begin
 select id into s from public.makeit_shops where owner_id=auth.uid() for update;
 if s is null then raise exception 'กรุณาเข้าสู่ระบบและตั้งชื่อร้านก่อน'; end if;
 return s;
end $$;
alter table public.makeit_shops enable row level security;
create policy shop_read on public.makeit_shops for select to authenticated using(owner_id=auth.uid());
do $$ declare t text; begin
 foreach t in array array['makeit_products','makeit_sales','makeit_sale_items','makeit_movements','makeit_cash_entries'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('create policy owner_read on public.%I for select to authenticated using(shop_id=public.makeit_shop_id())',t);
 end loop;
end $$;
revoke all on public.makeit_shops,public.makeit_products,public.makeit_sales,public.makeit_sale_items,public.makeit_movements,public.makeit_cash_entries from anon,authenticated;
grant select on public.makeit_shops,public.makeit_products,public.makeit_sales,public.makeit_sale_items,public.makeit_movements,public.makeit_cash_entries to authenticated;

create function public.makeit_setup_shop(p_name text) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare s uuid; begin
 if auth.uid() is null then raise exception 'กรุณาเข้าสู่ระบบ'; end if;
 insert into public.makeit_shops(owner_id,name) values(auth.uid(),trim(p_name))
 on conflict(owner_id) do update set name=excluded.name returning id into s;
 return s;
end $$;

create function public.makeit_check_file(p_path text) returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if p_path is not null and (split_part(p_path,'/',1) is distinct from public.makeit_shop_id()::text or
 not exists(select 1 from storage.objects where bucket_id='makeit-private' and name=p_path) or
 exists(select 1 from public.makeit_file_gc where path=p_path)) then
 raise exception 'ไม่พบไฟล์หลักฐานของร้าน กรุณาอัปโหลดอีกครั้ง'; end if;
end $$;

create function public.makeit_save_product(p_id uuid,p_name text,p_category text,p_price numeric,p_cost numeric,p_stock integer,p_active boolean,p_image text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare s uuid:=public.makeit_lock_shop(); old public.makeit_products; begin
 perform public.makeit_check_file(p_image);
 select * into old from public.makeit_products where id=p_id and shop_id=s;
 if found then
  update public.makeit_products set name=trim(p_name),category=trim(p_category),price=p_price,active=p_active,image_path=p_image where id=p_id and shop_id=s;
 else
  insert into public.makeit_products(id,shop_id,name,category,price,average_cost,stock,active,image_path)
  values(p_id,s,trim(p_name),trim(p_category),p_price,p_cost,p_stock,p_active,p_image);
  insert into public.makeit_movements(shop_id,product_id,kind,quantity,unit_cost,reason)
  values(s,p_id,'opening',p_stock,p_cost,'ยอดยกมา');
 end if;
 return p_id;
end $$;

create function public.makeit_stock(p_request uuid,p_product uuid,p_kind text,p_quantity integer,p_cost numeric,p_paid boolean,p_reason text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare s uuid:=public.makeit_lock_shop(); p public.makeit_products; m uuid; q integer; c numeric; begin
 select id into m from public.makeit_movements where shop_id=s and request_id=p_request;
 if found then return m; end if;
 select * into p from public.makeit_products where id=p_product and shop_id=s for update;
 if not found then raise exception 'ไม่พบสินค้า'; end if;
 if p_kind not in ('purchase','adjustment') or p_quantity is null or p_cost is null or p_cost<0 then raise exception 'ข้อมูลสต็อกไม่ถูกต้อง'; end if;
 if p_kind='purchase' then
  if p_quantity<=0 then raise exception 'จำนวนรับเข้าต้องมากกว่า 0'; end if;
  q:=p_quantity; c:=(p.stock*p.average_cost+q*p_cost)/(p.stock+q);
 else
  if p_quantity<0 or length(trim(coalesce(p_reason,'')))=0 then raise exception 'ระบุยอดคงเหลือและเหตุผล'; end if;
  q:=p_quantity-p.stock; c:=p.average_cost;
 end if;
 update public.makeit_products set stock=stock+q,average_cost=c where id=p.id;
 insert into public.makeit_movements(shop_id,product_id,kind,quantity,unit_cost,reason,request_id)
 values(s,p.id,p_kind,q,case when p_kind='purchase' then p_cost else p.average_cost end,coalesce(p_reason,''),p_request) returning id into m;
 if p_kind='purchase' and p_paid and q*p_cost>0 then
  insert into public.makeit_cash_entries(id,shop_id,kind,category,amount,note,movement_id)
  values(p_request,s,'purchase','ซื้อสินค้า',round(q*p_cost,2),p.name,m);
 end if;
 return m;
end $$;

create function public.makeit_checkout(p_request uuid,p_items jsonb,p_payment text,p_slip text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare s uuid:=public.makeit_lock_shop(); r record; p public.makeit_products; total numeric:=0; cost numeric:=0; begin
 if exists(select 1 from public.makeit_sales where id=p_request and shop_id=s) then return p_request; end if;
 if p_payment is null or p_payment not in ('cash','transfer') then raise exception 'เลือกวิธีชำระเงิน'; end if;
 if p_payment='transfer' and p_slip is null then raise exception 'กรุณาแนบสลิป'; end if;
 perform public.makeit_check_file(p_slip);
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'ตะกร้าว่าง'; end if;
 if exists(select 1 from jsonb_to_recordset(p_items) as x(id uuid,quantity numeric) where quantity is null or quantity<=0 or quantity<>trunc(quantity) or quantity>2147483647 or id is null) then raise exception 'จำนวนสินค้าไม่ถูกต้อง'; end if;
 for r in select x.id,sum(x.quantity)::integer quantity from jsonb_to_recordset(p_items) as x(id uuid,quantity numeric) group by x.id order by x.id loop
  select * into p from public.makeit_products where id=r.id and shop_id=s for update;
  if not found then raise exception 'ไม่พบสินค้าในร้าน'; end if;
  if not p.active or p.stock<r.quantity then raise exception 'สินค้า % มีไม่เพียงพอหรือปิดการขายแล้ว',p.name; end if;
  total:=total+p.price*r.quantity; cost:=cost+p.average_cost*r.quantity;
 end loop;
 insert into public.makeit_sales(id,shop_id,payment,slip_path,total,cost) values(p_request,s,p_payment,p_slip,total,cost);
 for r in select x.id,sum(x.quantity)::integer quantity from jsonb_to_recordset(p_items) as x(id uuid,quantity numeric) group by x.id order by x.id loop
  select * into p from public.makeit_products where id=r.id and shop_id=s;
  insert into public.makeit_sale_items(shop_id,sale_id,product_id,name,quantity,price,cost) values(s,p_request,p.id,p.name,r.quantity,p.price,p.average_cost);
  update public.makeit_products set stock=stock-r.quantity where id=p.id;
  insert into public.makeit_movements(shop_id,product_id,kind,quantity,unit_cost,sale_id) values(s,p.id,'sale',-r.quantity,p.average_cost,p_request);
 end loop;
 return p_request;
end $$;

create function public.makeit_void(p_sale uuid,p_reason text) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare s uuid:=public.makeit_lock_shop(); sale public.makeit_sales; i record; p public.makeit_products; begin
 select * into sale from public.makeit_sales where id=p_sale and shop_id=s for update;
 if not found then raise exception 'ไม่พบบิล'; end if;
 if sale.voided_at is not null then return; end if;
 if length(trim(coalesce(p_reason,'')))=0 then raise exception 'กรุณาระบุเหตุผลยกเลิก'; end if;
 for i in select * from public.makeit_sale_items where sale_id=p_sale order by product_id loop
  select * into p from public.makeit_products where id=i.product_id for update;
  update public.makeit_products set average_cost=(p.stock*p.average_cost+i.quantity*i.cost)/(p.stock+i.quantity),stock=p.stock+i.quantity where id=p.id;
  insert into public.makeit_movements(shop_id,product_id,kind,quantity,unit_cost,reason,sale_id) values(s,p.id,'void',i.quantity,i.cost,trim(p_reason),p_sale);
 end loop;
 update public.makeit_sales set voided_at=now(),void_reason=trim(p_reason) where id=p_sale;
end $$;

create function public.makeit_cash(p_id uuid,p_kind text,p_category text,p_amount numeric,p_note text,p_occurred timestamptz,p_evidence text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare s uuid:=public.makeit_lock_shop(); begin
 if exists(select 1 from public.makeit_cash_entries where id=p_id and shop_id=s) then return p_id; end if;
 if p_kind is null or p_kind not in ('income','expense') or length(trim(coalesce(p_category,'')))=0 then raise exception 'ข้อมูลรายรับรายจ่ายไม่ถูกต้อง'; end if;
 perform public.makeit_check_file(p_evidence);
 insert into public.makeit_cash_entries(id,shop_id,kind,category,amount,note,occurred_at,evidence_path)
 values(p_id,s,p_kind,trim(p_category),p_amount,coalesce(p_note,''),p_occurred,p_evidence);
 return p_id;
end $$;

create function public.makeit_snapshot() returns jsonb language sql stable security invoker set search_path=public,pg_temp as $$
 select jsonb_build_object(
 'shop',(select to_jsonb(s) from public.makeit_shops s where owner_id=auth.uid()),
 'products',coalesce((select jsonb_agg(p order by p.created_at desc) from public.makeit_products p),'[]'::jsonb),
 'sales',coalesce((select jsonb_agg(s order by s.created_at desc) from public.makeit_sales s),'[]'::jsonb),
 'items',coalesce((select jsonb_agg(i) from public.makeit_sale_items i),'[]'::jsonb),
 'entries',coalesce((select jsonb_agg(e order by e.occurred_at desc) from public.makeit_cash_entries e),'[]'::jsonb),
 'movements',coalesce((select jsonb_agg(m order by m.created_at desc) from public.makeit_movements m),'[]'::jsonb))
$$;

create function public.makeit_pay_purchase(p_movement uuid) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare s uuid:=public.makeit_lock_shop(); m public.makeit_movements; begin
 select * into m from public.makeit_movements where id=p_movement and shop_id=s and kind='purchase';
 if not found then raise exception 'ไม่พบรายการรับสินค้า'; end if;
 if m.quantity*m.unit_cost<=0 then return; end if;
 insert into public.makeit_cash_entries(id,shop_id,kind,category,amount,note,movement_id)
 values(gen_random_uuid(),s,'purchase','ซื้อสินค้า',round(m.quantity*m.unit_cost,2),'จ่ายค่าสินค้ารับเข้า',m.id)
 on conflict(movement_id) where movement_id is not null do nothing;
end $$;

-- Mark under the same shop lock used by checkout. Marked uploads cannot be attached,
-- so an asynchronous Storage removal cannot race a successfully committed bill.
create function public.makeit_cleanup_candidates() returns setof text language plpgsql security definer set search_path=public,pg_temp as $$
declare o record; begin
 for o in select name from storage.objects where bucket_id='makeit-private' and created_at<now()-interval '24 hours' order by created_at limit 2000 loop
  perform 1 from public.makeit_shops where id::text=split_part(o.name,'/',1) for update;
  if not exists(select 1 from public.makeit_sales where slip_path=o.name)
    and not exists(select 1 from public.makeit_products where image_path=o.name)
    and not exists(select 1 from public.makeit_cash_entries where evidence_path=o.name) then
   insert into public.makeit_file_gc(path) values(o.name) on conflict do nothing;
   return next o.name;
  end if;
 end loop;
end $$;

-- RPCs are the only client write interface; helper functions are not exposed.
do $$ declare r record; begin
 for r in select oid::regprocedure signature from pg_proc where pronamespace='public'::regnamespace and proname like 'makeit_%' loop
  execute format('revoke all on function %s from public,anon,authenticated',r.signature);
 end loop;
end $$;
grant execute on function public.makeit_shop_id(),public.makeit_setup_shop(text),public.makeit_save_product(uuid,text,text,numeric,numeric,integer,boolean,text),public.makeit_stock(uuid,uuid,text,integer,numeric,boolean,text),public.makeit_checkout(uuid,jsonb,text,text),public.makeit_void(uuid,text),public.makeit_cash(uuid,text,text,numeric,text,timestamptz,text),public.makeit_snapshot() to authenticated;
grant execute on function public.makeit_pay_purchase(uuid) to authenticated;
grant execute on function public.makeit_cleanup_candidates() to service_role;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('makeit-private','makeit-private',false,10485760,array['image/jpeg','image/png','image/webp']);
create policy makeit_file_read on storage.objects for select to authenticated
using(bucket_id='makeit-private' and (storage.foldername(name))[1]=public.makeit_shop_id()::text);
create policy makeit_file_upload on storage.objects for insert to authenticated
with check(bucket_id='makeit-private' and (storage.foldername(name))[1]=public.makeit_shop_id()::text);
-- No client update/delete: attached evidence cannot be replaced or erased.
commit;
