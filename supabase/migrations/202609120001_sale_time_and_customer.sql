begin;

alter table public.makeit_sales add column customer_type text not null default 'Unspecified'
 check(customer_type in ('Student','Office','Family','Unspecified'));
alter table public.makeit_sales add column time_source text not null default 'system'
 check(time_source in ('system','manual','slip_ocr'));
alter table public.makeit_sales add column ocr_detected_at timestamptz;
alter table public.makeit_sales add column recorded_at timestamptz;
update public.makeit_sales set recorded_at=created_at where recorded_at is null;
alter table public.makeit_sales alter column recorded_at set default now(),alter column recorded_at set not null;

create function public.makeit_checkout_v2(p_request uuid,p_items jsonb,p_payment text,p_slip text,p_sold_at timestamptz,p_customer_type text,p_time_source text,p_ocr_detected_at timestamptz default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare s uuid:=public.makeit_lock_shop(); r record; p public.makeit_products; total numeric:=0; cost numeric:=0; begin
 if exists(select 1 from public.makeit_sales where id=p_request and shop_id=s) then return p_request; end if;
 if p_payment is null or p_payment not in ('cash','transfer') then raise exception 'เลือกวิธีชำระเงิน'; end if;
 if p_payment='transfer' and p_slip is null then raise exception 'กรุณาแนบสลิป'; end if;
 if p_sold_at is null or p_sold_at>now()+interval '10 minutes' then raise exception 'เวลาขายไม่ถูกต้อง'; end if;
 if p_customer_type is null or p_customer_type not in ('Student','Office','Family') then raise exception 'กรุณาเลือกประเภทลูกค้า'; end if;
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

revoke all on function public.makeit_checkout_v2(uuid,jsonb,text,text,timestamptz,text,text,timestamptz) from public,anon,authenticated;
grant execute on function public.makeit_checkout_v2(uuid,jsonb,text,text,timestamptz,text,text,timestamptz) to authenticated;

-- Keep customer/time metadata when an Admin replaces a sale through the existing audited workflow.
alter function public.makeit_admin_mutate(uuid,uuid,text,uuid,jsonb,jsonb,text) rename to makeit_admin_mutate_core;
revoke all on function public.makeit_admin_mutate_core(uuid,uuid,text,uuid,jsonb,jsonb,text) from public,anon,authenticated;
create function public.makeit_admin_mutate(p_request uuid,p_shop uuid,p_action text,p_target uuid,p_expected jsonb,p_data jsonb,p_reason text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare result jsonb; source_sale public.makeit_sales; updated_after jsonb; begin
 perform public.makeit_require_admin();
 select * into source_sale from public.makeit_sales where id=p_target and shop_id=p_shop;
 result:=public.makeit_admin_mutate_core(p_request,p_shop,p_action,p_target,p_expected,p_data,p_reason);
 if p_action='sale' and exists(select 1 from public.makeit_sales where id=p_request and shop_id=p_shop) then
  update public.makeit_sales set
   customer_type=case when coalesce(p_data->>'customer_type',source_sale.customer_type) in ('Student','Office','Family','Unspecified') then coalesce(p_data->>'customer_type',source_sale.customer_type) else 'Unspecified' end,
   time_source=case when coalesce(p_data->>'time_source',source_sale.time_source) in ('system','manual','slip_ocr') then coalesce(p_data->>'time_source',source_sale.time_source) else 'manual' end,
   ocr_detected_at=source_sale.ocr_detected_at
  where id=p_request and shop_id=p_shop;
  updated_after:=jsonb_build_object('replaces_sale_id',p_target,'sale',(select to_jsonb(s) from public.makeit_sales s where id=p_request),'items',(select jsonb_agg(si) from public.makeit_sale_items si where sale_id=p_request));
  update public.makeit_admin_audit set after_data=updated_after where request_id=p_request;
  result:=jsonb_build_object('audit_id',(select id from public.makeit_admin_audit where request_id=p_request),'after',updated_after);
 end if;
 return result;
end $$;
revoke all on function public.makeit_admin_mutate(uuid,uuid,text,uuid,jsonb,jsonb,text) from public,anon,authenticated;
grant execute on function public.makeit_admin_mutate(uuid,uuid,text,uuid,jsonb,jsonb,text) to authenticated;

commit;
