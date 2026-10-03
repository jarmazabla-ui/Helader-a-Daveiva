-- 3A PARTE 3 - Ejecutar DESPUÉS de las partes 1 y 2
create view v_catalog as   -- sin costos, para Producción
  select id, code, product_id, presentation_id, stock, active from product_presentations where active;
grant select on v_catalog to authenticated;

create view v_costs with (security_invoker=true) as
select pp.id, p.name as product, pr.name as presentation, pp.sale_price,
  coalesce(rc.cpl,0)*pr.volume_ml/1000 as content_cost,
  coalesce(pk.cost,0) as packaging_cost,
  coalesce(rc.cpl,0)*pr.volume_ml/1000 + coalesce(pk.cost,0) as unit_cost
from product_presentations pp
join products p on p.id=pp.product_id join presentations pr on pr.id=pp.presentation_id
left join (select r.product_id, sum(ri.qty_base*i.avg_cost)/r.yield_liters as cpl
  from recipes r join recipe_items ri on ri.recipe_id=r.id join items i on i.id=ri.item_id
  where r.active group by r.id,r.product_id,r.yield_liters) rc on rc.product_id=pp.product_id
left join (select k.presentation_id, sum(k.qty_per_unit*i.avg_cost) as cost
  from presentation_packaging k join items i on i.id=k.item_id group by 1) pk on pk.presentation_id=pp.presentation_id;
grant select on v_costs to authenticated;

create view v_sales_lines with (security_invoker=true) as
select s.sale_date, p.name as product, pr.name as presentation, si.qty, si.amount, si.cost_total
from sale_items si join sales s on s.id=si.sale_id and s.status='confirmado'
join product_presentations pp on pp.id=si.pp_id
join products p on p.id=pp.product_id join presentations pr on pr.id=pp.presentation_id;
grant select on v_sales_lines to authenticated;

create or replace function register_income(p_date date,p_category uuid,p_payment uuid,p_amount numeric,p_desc text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v uuid := gen_random_uuid(); cat categories%rowtype;
begin
  if app_role() not in ('admin','caja') then raise exception 'Sin permiso'; end if;
  if not day_is_open(p_date) then raise exception 'El día ya está cerrado'; end if;
  select * into cat from categories where id=p_category and kind='ingreso';
  if not found then raise exception 'Categoría inválida'; end if;
  if app_role()='caja' and not cat.cashier_allowed then raise exception 'Categoría no autorizada para Caja'; end if;
  insert into cash_movements(id,move_date,move_type,category_id,description,amount_in,payment_method_id,source_table,source_id)
    values (v,p_date,'otro_ingreso',p_category,p_desc,p_amount,p_payment,'incomes',v);
  return v;
end $$;

create or replace function income_statement(p_from date,p_to date) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v numeric; c numeric; g jsonb; op numeric; og numeric; oi numeric; ub numeric;
begin
  if app_role()<>'admin' then raise exception 'Solo el administrador'; end if;
  select coalesce(sum(total),0) into v from sales where status='confirmado' and sale_date between p_from and p_to;
  select coalesce(sum(si.cost_total),0) into c from sale_items si join sales s on s.id=si.sale_id
    where s.status='confirmado' and s.sale_date between p_from and p_to;
  select coalesce(jsonb_agg(jsonb_build_object('grupo',grp,'categoria',nm,'monto',m)),'[]') into g from
    (select coalesce(ca.group_name,'otros') grp, ca.name nm, sum(e.amount) m from expenses e
     join categories ca on ca.id=e.category_id where e.status='confirmado' and e.expense_date between p_from and p_to
     group by 1,2 order by 1,2) t;
  select coalesce(sum(e.amount),0) into op from expenses e join categories ca on ca.id=e.category_id
    where e.status='confirmado' and e.expense_date between p_from and p_to and coalesce(ca.group_name,'otros') in ('personal','administrativo');
  select coalesce(sum(e.amount),0) into og from expenses e join categories ca on ca.id=e.category_id
    where e.status='confirmado' and e.expense_date between p_from and p_to and coalesce(ca.group_name,'otros') not in ('personal','administrativo');
  select coalesce(sum(amount_in),0) into oi from cash_movements
    where move_type='otro_ingreso' and status='confirmado' and move_date between p_from and p_to;
  ub := v - c;
  return jsonb_build_object('ventas',v,'costo_ventas',c,'utilidad_bruta',ub,
    'margen_bruto',case when v>0 then round(ub/v*100,2) else 0 end,'gastos',g,'total_operativos',op,
    'resultado_operativo',ub-op,'otros_ingresos',oi,'otros_gastos',og,'resultado',ub-op+oi-og);
end $$;

create or replace function dashboard_admin() returns jsonb
language plpgsql security definer set search_path=public as $$
declare d date := (now() at time zone 'America/La_Paz')::date; m date := date_trunc('month',d)::date;
begin
  if app_role()<>'admin' then raise exception 'Solo el administrador'; end if;
  return jsonb_build_object(
   'ventas_hoy',(select coalesce(sum(total),0) from sales where status='confirmado' and sale_date=d),
   'ventas_mes',(select coalesce(sum(total),0) from sales where status='confirmado' and sale_date>=m),
   'compras_mes',(select coalesce(sum(total),0) from purchases where status='confirmado' and purchase_date>=m),
   'gastos_mes',(select coalesce(sum(amount),0) from expenses where status='confirmado' and expense_date>=m),
   'valor_inventario_insumos',(select round(coalesce(sum(stock*avg_cost),0),2) from items),
   'insumos_bajo_minimo',(select count(*) from items where active and stock<=min_stock),
   'unidades_terminadas',(select coalesce(sum(stock),0) from product_presentations));
end $$;

create or replace function adjust_inventory(p_item uuid,p_delta numeric,p_reason text) returns void
language plpgsql security definer set search_path=public as $$
declare it items%rowtype; ns numeric;
begin
  if app_role()<>'admin' then raise exception 'Solo el administrador'; end if;
  if coalesce(trim(p_reason),'')='' or p_delta=0 then raise exception 'Indique cantidad y motivo'; end if;
  if p_delta<0 then perform consume_item(p_item,-p_delta,'promedio','adjustments',null,'Ajuste: '||p_reason);
  else
    select * into it from items where id=p_item for update; ns:=it.stock+p_delta;
    insert into item_layers(item_id,qty_initial,qty_remaining,unit_cost,source_table) values (p_item,p_delta,p_delta,it.avg_cost,'adjustments');
    insert into item_movements(item_id,move_type,concept,source_table,qty_in,value_in,balance_qty,balance_value,unit_cost_applied,costing_method)
      values (p_item,'ajuste','Ajuste: '||p_reason,'adjustments',p_delta,round(p_delta*it.avg_cost,2),ns,round(ns*it.avg_cost,2),it.avg_cost,'promedio');
    update items set stock=ns where id=p_item;
  end if;
  insert into audit_log(action,table_name,record_id,detail) values ('ajuste_inventario','items',p_item,jsonb_build_object('delta',p_delta,'motivo',p_reason));
end $$;

create or replace function void_production(p_id uuid,p_reason text) returns void
language plpgsql security definer set search_path=public as $$
declare o production_orders%rowtype; x record; c record; pp product_presentations%rowtype; it items%rowtype; ns numeric;
begin
  if app_role() not in ('admin','produccion') then raise exception 'Sin permiso'; end if;
  if coalesce(trim(p_reason),'')='' then raise exception 'El motivo es obligatorio'; end if;
  select * into o from production_orders where id=p_id for update;
  if not found or o.status='anulado' then raise exception 'Orden no válida'; end if;
  for x in select * from production_outputs where order_id=p_id loop
    select * into pp from product_presentations where id=x.pp_id for update;
    if pp.stock < x.units then raise exception 'No se puede anular: parte de esta producción ya fue vendida'; end if;
  end loop;
  for x in select * from production_outputs where order_id=p_id loop
    select * into pp from product_presentations where id=x.pp_id for update; ns:=pp.stock-x.units;
    update product_presentations set stock=ns where id=pp.id;
    insert into fg_movements(pp_id,move_type,qty_out,unit_cost,balance_qty,source_table,source_id)
      values (pp.id,'anulacion_produccion',x.units,x.unit_cost,ns,'production_orders',p_id);
  end loop;
  for c in select * from production_consumptions where order_id=p_id loop
    select * into it from items where id=c.item_id for update; ns:=it.stock+c.qty_real;
    insert into item_layers(item_id,qty_initial,qty_remaining,unit_cost,source_table,source_id)
      values (it.id,c.qty_real,c.qty_real,case when c.qty_real>0 then c.cost/c.qty_real else 0 end,'production_orders',p_id);
    insert into item_movements(item_id,move_type,concept,source_table,source_id,qty_in,value_in,balance_qty,balance_value,costing_method)
      values (it.id,'anulacion_produccion','Anulación de producción','production_orders',p_id,c.qty_real,c.cost,ns,round(it.stock*it.avg_cost+c.cost,2),o.costing_method);
    update items set stock=ns, avg_cost=case when ns>0 then (it.stock*it.avg_cost+c.cost)/ns else avg_cost end where id=it.id;
  end loop;
  update production_orders set status='anulado' where id=p_id;
  insert into audit_log(action,table_name,record_id,detail) values ('anular_produccion','production_orders',p_id,jsonb_build_object('motivo',p_reason));
end $$;

grant execute on function register_income(date,uuid,uuid,numeric,text) to authenticated;
grant execute on function income_statement(date,date) to authenticated;
grant execute on function dashboard_admin() to authenticated;
grant execute on function adjust_inventory(uuid,numeric,text) to authenticated;
grant execute on function void_production(uuid,text) to authenticated;
