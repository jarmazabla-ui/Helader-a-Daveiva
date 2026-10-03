-- =====================================================
-- 3A PARTE 2 - Producción, ventas, gastos, anulaciones, cierre
-- Ejecutar DESPUÉS de 3A_schema_heladeria.sql
-- =====================================================

create sequence seq_production; create sequence seq_sale;

create table production_orders (
  id uuid primary key default gen_random_uuid(), number text unique not null,
  order_date date not null, product_id uuid not null references products(id),
  recipe_id uuid references recipes(id), liters_obtained numeric(12,3),
  costing_method text not null, total_cost numeric(14,2) default 0,
  status text not null default 'confirmado' check (status in ('confirmado','anulado')),
  created_by uuid default auth.uid(), created_at timestamptz default now()
);
create table production_consumptions (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references production_orders(id),
  item_id uuid not null references items(id),
  qty_theoretical numeric(14,3), qty_real numeric(14,3) not null,
  cost numeric(14,2) not null, is_packaging boolean default false
);
create table production_outputs (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references production_orders(id),
  pp_id uuid not null references product_presentations(id),
  units numeric(14,3) not null, unit_cost numeric(14,6) not null
);
create table fg_movements (
  id uuid primary key default gen_random_uuid(),
  pp_id uuid not null references product_presentations(id),
  moved_at timestamptz default now(), move_type text not null,
  qty_in numeric(14,3) default 0, qty_out numeric(14,3) default 0,
  unit_cost numeric(14,6), balance_qty numeric(14,3) not null,
  source_table text, source_id uuid, created_by uuid default auth.uid()
);
create table sales (
  id uuid primary key default gen_random_uuid(), number text unique not null,
  sale_date date not null, payment_method_id uuid not null references payment_methods(id),
  notes text, total numeric(14,2) not null,
  status text not null default 'confirmado' check (status in ('confirmado','anulado')),
  void_reason text, voided_by uuid, voided_at timestamptz,
  created_by uuid default auth.uid(), created_at timestamptz default now()
);
create table sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references sales(id),
  pp_id uuid not null references product_presentations(id),
  qty numeric(14,3) not null check (qty > 0),
  unit_price numeric(12,2) not null, amount numeric(14,2) not null,
  unit_cost numeric(14,6) not null, cost_total numeric(14,2) not null  -- costo congelado
);
create table expenses (
  id uuid primary key default gen_random_uuid(), expense_date date not null,
  category_id uuid not null references categories(id),
  payment_method_id uuid not null references payment_methods(id),
  amount numeric(14,2) not null check (amount > 0), description text, document text,
  status text not null default 'confirmado' check (status in ('confirmado','anulado')),
  created_by uuid default auth.uid(), created_at timestamptz default now()
);
create table cash_closures (
  id uuid primary key default gen_random_uuid(), closure_date date not null,
  opening_cash numeric(14,2), total_in numeric(14,2), total_out numeric(14,2),
  theoretical_cash numeric(14,2), counted_cash numeric(14,2), difference numeric(14,2),
  notes text, status text not null default 'cerrado' check (status in ('cerrado','reabierto')),
  reopen_reason text, closed_by uuid default auth.uid(), closed_at timestamptz default now()
);
create unique index one_closed_day on cash_closures(closure_date) where status = 'cerrado';
create table cash_closure_lines (
  closure_id uuid references cash_closures(id),
  payment_method_id uuid references payment_methods(id),
  theoretical numeric(14,2), primary key (closure_id, payment_method_id)
);

create or replace function day_is_open(d date) returns boolean
language sql stable as $$ select not exists (select 1 from cash_closures where closure_date=d and status='cerrado') $$;

-- ---------- SALIDA DE INSUMOS (interna): UEPS / promedio / máximo ----------
create or replace function consume_item(p_item uuid, p_qty numeric, p_method text,
  p_src_table text, p_src_id uuid, p_concept text) returns numeric
language plpgsql security definer set search_path = public as $$
declare it items%rowtype; st app_settings%rowtype; l item_layers%rowtype;
  rem numeric := p_qty; take numeric; cost numeric := 0; mv uuid := gen_random_uuid();
  new_stock numeric; new_avg numeric; layer_val numeric;
begin
  if p_method not in ('promedio','ueps','maximo') then raise exception 'Método inválido'; end if;
  select * into it from items where id = p_item for update;
  select * into st from app_settings;
  if it.stock < p_qty and not st.allow_negative_stock then
    raise exception 'Stock insuficiente de %: disponible % %', it.name, it.stock, it.base_unit;
  end if;
  new_stock := it.stock - p_qty;
  insert into item_movements(id,item_id,move_type,concept,source_table,source_id,
    qty_out,value_out,balance_qty,balance_value,costing_method)
  values (mv,p_item,'consumo',p_concept,p_src_table,p_src_id,p_qty,0,0,0,p_method);

  for l in select * from item_layers where item_id=p_item and qty_remaining>0
           order by layer_date, id for update loop
    exit when rem <= 0;
    take := least(l.qty_remaining, rem);
    update item_layers set qty_remaining = qty_remaining - take where id = l.id;
    if p_method = 'ueps' then cost := cost + take*l.unit_cost; end if;
    insert into item_movement_layers values (mv, l.id, take, l.unit_cost);
    rem := rem - take;
  end loop;

  if p_method = 'ueps' then cost := cost + rem*it.last_cost;
  elsif p_method = 'maximo' then cost := p_qty*it.max_cost;
  else cost := p_qty*it.avg_cost; end if;
  cost := round(cost,2);

  new_avg := it.avg_cost;
  if p_method = 'ueps' and new_stock > 0 then
    select coalesce(sum(qty_remaining*unit_cost),0) into layer_val from item_layers where item_id=p_item;
    new_avg := layer_val/new_stock;
  end if;
  update item_movements set value_out=cost, balance_qty=new_stock,
    balance_value=round(new_stock*new_avg,2),
    unit_cost_applied = case when p_qty>0 then cost/p_qty end where id = mv;
  update items set stock=new_stock, avg_cost=new_avg where id = p_item;
  return cost;
end $$;
revoke execute on function consume_item(uuid,numeric,text,text,uuid,text) from public, anon, authenticated;

-- Vista previa del costo (no modifica nada)
create or replace function preview_cost(p_item uuid, p_qty numeric, p_method text) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare it items%rowtype; l record; rem numeric := p_qty; c numeric := 0;
begin
  if app_role() not in ('admin','produccion','compras') then raise exception 'Sin permiso'; end if;
  select * into it from items where id = p_item;
  if p_method = 'ueps' then
    for l in select qty_remaining, unit_cost from item_layers
             where item_id=p_item and qty_remaining>0 order by layer_date, id loop
      exit when rem <= 0;
      c := c + least(l.qty_remaining,rem)*l.unit_cost; rem := rem - least(l.qty_remaining,rem);
    end loop;
    return round(c + rem*it.last_cost, 2);
  elsif p_method = 'maximo' then return round(p_qty*it.max_cost,2);
  else return round(p_qty*it.avg_cost,2); end if;
end $$;
grant execute on function preview_cost(uuid,numeric,text) to authenticated;

-- ---------- PRODUCCIÓN ----------
-- p_outputs:   [{"pp_id":"...","units":4}, ...]
-- p_overrides: [{"item_id":"...","qty_base":1200}]  (consumo real distinto del teórico)
create or replace function confirm_production(p_date date, p_product uuid, p_method text,
  p_outputs jsonb, p_overrides jsonb default '[]') returns uuid
language plpgsql security definer set search_path = public as $$
declare rc recipes%rowtype; v_id uuid := gen_random_uuid(); total_ml numeric; liters numeric;
  content_cost numeric := 0; total_cost numeric := 0; ri record; pk record; x jsonb;
  pp product_presentations%rowtype; pr presentations%rowtype;
  q numeric; theo numeric; c numeric; pack numeric; units numeric; ucost numeric; ns numeric;
begin
  if app_role() not in ('admin','produccion') then raise exception 'Sin permiso'; end if;
  select * into rc from recipes where product_id=p_product and active limit 1;
  if not found then raise exception 'El producto no tiene receta activa'; end if;
  select coalesce(sum((o->>'units')::numeric * presn.volume_ml),0) into total_ml
    from jsonb_array_elements(p_outputs) o
    join product_presentations p on p.id=(o->>'pp_id')::uuid
    join presentations presn on presn.id=p.presentation_id;
  if total_ml <= 0 then raise exception 'Indique la producción obtenida'; end if;
  liters := total_ml/1000;

  insert into production_orders(id,number,order_date,product_id,recipe_id,liters_obtained,costing_method)
  values (v_id,'OP-'||lpad(nextval('seq_production')::text,5,'0'),p_date,p_product,rc.id,liters,p_method);

  for ri in select * from recipe_items where recipe_id = rc.id loop
    theo := ri.qty_base*liters/rc.yield_liters;
    select (o->>'qty_base')::numeric into q from jsonb_array_elements(p_overrides) o
      where (o->>'item_id')::uuid = ri.item_id limit 1;
    q := coalesce(q, theo);
    c := consume_item(ri.item_id,q,p_method,'production_orders',v_id,'Consumo de receta');
    insert into production_consumptions(order_id,item_id,qty_theoretical,qty_real,cost)
      values (v_id,ri.item_id,theo,q,c);
    content_cost := content_cost + c;
  end loop;

  for x in select * from jsonb_array_elements(p_outputs) loop
    units := (x->>'units')::numeric;
    if units <= 0 then continue; end if;
    select * into pp from product_presentations where id=(x->>'pp_id')::uuid for update;
    select * into pr from presentations where id = pp.presentation_id;
    pack := 0;
    for pk in select * from presentation_packaging where presentation_id = pp.presentation_id loop
      c := consume_item(pk.item_id, pk.qty_per_unit*units, p_method,'production_orders',v_id,'Envase/tapa/etiqueta');
      insert into production_consumptions(order_id,item_id,qty_theoretical,qty_real,cost,is_packaging)
        values (v_id,pk.item_id,pk.qty_per_unit*units,pk.qty_per_unit*units,c,true);
      pack := pack + c;
    end loop;
    ucost := (content_cost/total_ml*pr.volume_ml*units + pack)/units;
    total_cost := total_cost + ucost*units;
    ns := pp.stock + units;
    update product_presentations set stock = ns,
      avg_cost = (pp.stock*pp.avg_cost + ucost*units)/ns where id = pp.id;
    insert into production_outputs(order_id,pp_id,units,unit_cost) values (v_id,pp.id,units,ucost);
    insert into fg_movements(pp_id,move_type,qty_in,unit_cost,balance_qty,source_table,source_id)
      values (pp.id,'produccion',units,ucost,ns,'production_orders',v_id);
  end loop;

  update production_orders set total_cost = round(total_cost,2) where id = v_id;
  insert into audit_log(action,table_name,record_id) values ('confirmar_produccion','production_orders',v_id);
  return v_id;
end $$;

-- ---------- VENTA (POS) ----------
-- p_items: [{"pp_id":"...","qty":5}]  (el precio lo toma el servidor)
create or replace function confirm_sale(p_date date, p_payment uuid, p_notes text, p_items jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid := gen_random_uuid(); x jsonb; pp product_presentations%rowtype;
  st app_settings%rowtype; q numeric; amt numeric; v_total numeric := 0; ns numeric;
begin
  if app_role() not in ('admin','caja') then raise exception 'Sin permiso'; end if;
  if not day_is_open(p_date) then raise exception 'El día % ya está cerrado', p_date; end if;
  if jsonb_array_length(p_items) = 0 then raise exception 'La venta no tiene ítems'; end if;
  select * into st from app_settings;
  insert into sales(id,number,sale_date,payment_method_id,notes,total)
    values (v_id,'VT-'||lpad(nextval('seq_sale')::text,5,'0'),p_date,p_payment,p_notes,0);

  for x in select * from jsonb_array_elements(p_items) loop
    q := (x->>'qty')::numeric;
    select * into pp from product_presentations where id=(x->>'pp_id')::uuid and active for update;
    if not found then raise exception 'Producto no disponible'; end if;
    if pp.stock < q and not st.allow_negative_stock then
      raise exception 'Stock insuficiente. Disponible: % unidades', pp.stock;
    end if;
    amt := round(q*pp.sale_price,2); v_total := v_total + amt; ns := pp.stock - q;
    insert into sale_items(sale_id,pp_id,qty,unit_price,amount,unit_cost,cost_total)
      values (v_id,pp.id,q,pp.sale_price,amt,pp.avg_cost,round(q*pp.avg_cost,2));
    update product_presentations set stock = ns where id = pp.id;
    insert into fg_movements(pp_id,move_type,qty_out,unit_cost,balance_qty,source_table,source_id)
      values (pp.id,'venta',q,pp.avg_cost,ns,'sales',v_id);
  end loop;

  update sales set total = v_total where id = v_id;
  insert into cash_movements(move_date,move_type,description,amount_in,payment_method_id,source_table,source_id)
    values (p_date,'venta','Venta',v_total,p_payment,'sales',v_id);
  return v_id;
end $$;

-- ---------- GASTO ----------
create or replace function register_expense(p_date date, p_category uuid, p_payment uuid,
  p_amount numeric, p_desc text, p_document text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid := gen_random_uuid(); cat categories%rowtype;
begin
  if app_role() not in ('admin','caja') then raise exception 'Sin permiso'; end if;
  if not day_is_open(p_date) then raise exception 'El día % ya está cerrado', p_date; end if;
  select * into cat from categories where id = p_category and kind = 'gasto';
  if not found then raise exception 'Categoría inválida'; end if;
  if app_role() = 'caja' and not cat.cashier_allowed then
    raise exception 'Esta categoría no está autorizada para Caja'; end if;
  insert into expenses(id,expense_date,category_id,payment_method_id,amount,description,document)
    values (v_id,p_date,p_category,p_payment,p_amount,p_desc,p_document);
  insert into cash_movements(move_date,move_type,category_id,description,amount_out,payment_method_id,source_table,source_id)
    values (p_date,'gasto',p_category,p_desc,p_amount,p_payment,'expenses',v_id);
  return v_id;
end $$;

-- ---------- ANULACIONES ----------
create or replace function void_sale(p_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare s sales%rowtype; si record; pp product_presentations%rowtype; ns numeric;
begin
  if coalesce(trim(p_reason),'') = '' then raise exception 'El motivo es obligatorio'; end if;
  select * into s from sales where id = p_id for update;
  if not found or s.status = 'anulado' then raise exception 'Venta no válida'; end if;
  if app_role() not in ('admin','caja') or (app_role()='caja' and s.created_by <> auth.uid()) then
    raise exception 'Sin permiso'; end if;
  if not day_is_open(s.sale_date) then raise exception 'El día está cerrado'; end if;
  for si in select * from sale_items where sale_id = p_id loop
    select * into pp from product_presentations where id = si.pp_id for update;
    ns := pp.stock + si.qty;
    update product_presentations set stock = ns,
      avg_cost = (pp.stock*pp.avg_cost + si.cost_total)/ns where id = pp.id;
    insert into fg_movements(pp_id,move_type,qty_in,unit_cost,balance_qty,source_table,source_id)
      values (pp.id,'anulacion_venta',si.qty,si.unit_cost,ns,'sales',p_id);
  end loop;
  update sales set status='anulado', void_reason=p_reason, voided_by=auth.uid(), voided_at=now() where id = p_id;
  update cash_movements set status='anulado' where source_table='sales' and source_id = p_id;
  insert into audit_log(action,table_name,record_id,detail) values ('anular_venta','sales',p_id,jsonb_build_object('motivo',p_reason));
end $$;

create or replace function void_purchase(p_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare p purchases%rowtype; pi record; it items%rowtype; ns numeric;
begin
  if app_role() not in ('admin','compras') then raise exception 'Sin permiso'; end if;
  if coalesce(trim(p_reason),'') = '' then raise exception 'El motivo es obligatorio'; end if;
  select * into p from purchases where id = p_id for update;
  if not found or p.status = 'anulado' then raise exception 'Compra no válida'; end if;
  if not day_is_open(p.purchase_date) then raise exception 'El día está cerrado'; end if;
  if exists (select 1 from item_layers where source_id=p_id and qty_remaining < qty_initial) then
    raise exception 'No se puede anular: parte de estos insumos ya fue consumida. Use un ajuste.'; end if;
  for pi in select * from purchase_items where purchase_id = p_id loop
    select * into it from items where id = pi.item_id for update;
    ns := it.stock - pi.qty_base;
    if ns < 0 then raise exception 'Stock insuficiente para anular'; end if;
    insert into item_movements(item_id,move_type,concept,source_table,source_id,qty_out,value_out,
      balance_qty,balance_value,unit_cost_applied,costing_method)
    values (it.id,'anulacion_compra','Anulación de compra','purchases',p_id,pi.qty_base,pi.amount,
      ns, round(greatest(it.stock*it.avg_cost - pi.amount,0),2), pi.unit_cost_base,'promedio');
    update items set stock = ns,
      avg_cost = case when ns > 0 then greatest(it.stock*it.avg_cost - pi.amount,0)/ns else avg_cost end
      where id = it.id;
  end loop;
  update item_layers set qty_remaining = 0 where source_id = p_id;
  update purchases set status='anulado', void_reason=p_reason, voided_by=auth.uid(), voided_at=now() where id = p_id;
  update cash_movements set status='anulado' where source_table='purchases' and source_id = p_id;
  insert into audit_log(action,table_name,record_id,detail) values ('anular_compra','purchases',p_id,jsonb_build_object('motivo',p_reason));
end $$;

-- ---------- ARQUEO Y CIERRE ----------
create or replace function close_day(p_date date, p_counted_cash numeric, p_notes text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid := gen_random_uuid(); opening numeric; tin numeric; tout numeric; theo numeric; diff numeric;
begin
  if app_role() not in ('admin','caja') then raise exception 'Sin permiso'; end if;
  if not day_is_open(p_date) then raise exception 'El día ya está cerrado'; end if;
  select coalesce((select counted_cash from cash_closures where status='cerrado' and closure_date < p_date
                   order by closure_date desc limit 1),0) into opening;
  select coalesce(sum(cm.amount_in),0), coalesce(sum(cm.amount_out),0) into tin, tout
    from cash_movements cm join payment_methods pm on pm.id = cm.payment_method_id
    where cm.move_date = p_date and cm.status='confirmado' and pm.is_cash;
  theo := opening + tin - tout; diff := p_counted_cash - theo;
  if diff <> 0 and coalesce(trim(p_notes),'') = '' then
    raise exception 'Hay una diferencia de %. Escriba una observación.', diff; end if;
  insert into cash_closures(id,closure_date,opening_cash,total_in,total_out,theoretical_cash,counted_cash,difference,notes)
    values (v_id,p_date,opening,tin,tout,theo,p_counted_cash,diff,p_notes);
  insert into cash_closure_lines
    select v_id, pm.id, coalesce(sum(cm.amount_in - cm.amount_out),0)
    from payment_methods pm left join cash_movements cm
      on cm.payment_method_id = pm.id and cm.move_date = p_date and cm.status='confirmado'
    group by pm.id;
  insert into audit_log(action,table_name,record_id) values ('cerrar_dia','cash_closures',v_id);
  return v_id;
end $$;

create or replace function reopen_day(p_date date, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if app_role() <> 'admin' then raise exception 'Solo el administrador puede reabrir'; end if;
  if coalesce(trim(p_reason),'') = '' then raise exception 'El motivo es obligatorio'; end if;
  update cash_closures set status='reabierto', reopen_reason=p_reason where closure_date=p_date and status='cerrado';
  insert into audit_log(action,table_name,detail) values ('reabrir_dia','cash_closures',jsonb_build_object('fecha',p_date,'motivo',p_reason));
end $$;

-- ---------- SEGURIDAD DE LAS TABLAS NUEVAS ----------
do $$
declare t text;
begin
  foreach t in array array['production_orders','production_consumptions','production_outputs',
    'fg_movements','sales','sale_items','expenses','cash_closures','cash_closure_lines']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy "admin_all" on %I for all using (app_role()=''admin'') with check (app_role()=''admin'')', t);
  end loop;
end $$;

create policy "prod_lee_ordenes" on production_orders for select using (app_role()='produccion');
create policy "prod_lee_consumos" on production_consumptions for select using (app_role()='produccion');
create policy "prod_lee_salidas" on production_outputs for select using (app_role()='produccion');
create policy "caja_lee_ventas" on sales for select using (app_role()='caja' and created_by = auth.uid());
create policy "caja_lee_gastos" on expenses for select using (app_role()='caja' and created_by = auth.uid());
create policy "caja_lee_cierres" on cash_closures for select using (app_role()='caja');
create policy "caja_lee_cierres_det" on cash_closure_lines for select using (app_role()='caja');
create policy "caja_lee_categorias" on categories for select using (app_role() in ('caja','admin'));

grant execute on function confirm_production(date,uuid,text,jsonb,jsonb) to authenticated;
grant execute on function confirm_sale(date,uuid,text,jsonb) to authenticated;
grant execute on function register_expense(date,uuid,uuid,numeric,text,text) to authenticated;
grant execute on function void_sale(uuid,text) to authenticated;
grant execute on function void_purchase(uuid,text) to authenticated;
grant execute on function close_day(date,numeric,text) to authenticated;
grant execute on function reopen_day(date,text) to authenticated;
grant execute on function day_is_open(date) to authenticated;

-- Categorías iniciales
insert into categories(kind,name,group_name,cashier_allowed) values
 ('ingreso','Ventas de helados','ventas',false),('ingreso','Otros ingresos','otros',true),
 ('gasto','Sueldos','personal',false),('gasto','Otros gastos de personal','personal',false),
 ('gasto','Alquiler','administrativo',false),('gasto','Energía eléctrica','administrativo',false),
 ('gasto','Agua','administrativo',false),('gasto','Transporte','administrativo',true),
 ('gasto','Comunicaciones','administrativo',false),('gasto','Otros administrativos','administrativo',true),
 ('gasto','Otros gastos','otros',false);
