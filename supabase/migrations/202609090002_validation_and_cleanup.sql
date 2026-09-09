begin;
alter table public.makeit_products add constraint makeit_finite_prices
 check(price<1000000000000 and average_cost<1000000000000);
alter table public.makeit_cash_entries add constraint makeit_finite_amount check(amount<1000000000000);
alter table public.makeit_movements add constraint makeit_finite_movement_cost check(unit_cost>=0 and unit_cost<1000000000000);
create or replace function public.makeit_cleanup_candidates() returns setof text language plpgsql security definer set search_path=public,pg_temp as $$
declare o record; begin
 for o in select name from storage.objects obj
  where bucket_id='makeit-private' and created_at<now()-interval '24 hours'
   and not exists(select 1 from public.makeit_sales where slip_path=obj.name)
   and not exists(select 1 from public.makeit_products where image_path=obj.name)
   and not exists(select 1 from public.makeit_cash_entries where evidence_path=obj.name)
  order by created_at,name limit 2000 loop
  perform 1 from public.makeit_shops where id::text=split_part(o.name,'/',1) for update;
  if not exists(select 1 from public.makeit_sales where slip_path=o.name)
    and not exists(select 1 from public.makeit_products where image_path=o.name)
    and not exists(select 1 from public.makeit_cash_entries where evidence_path=o.name) then
   insert into public.makeit_file_gc(path) values(o.name) on conflict do nothing;
   return next o.name;
  end if;
 end loop;
end $$;
commit;
