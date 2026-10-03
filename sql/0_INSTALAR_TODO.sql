-- =====================================================
-- INSTALACIÓN COMPLETA EN UN SOLO PASO (base de datos nueva)
-- Equivale a ejecutar 3A_schema + parte2 + parte3 + parte4 en orden.
-- Si YA ejecutaste las partes 1-3, ejecuta SOLO 4_completar_sistema.sql
-- =====================================================

-- >>>>>>>>>> 3A_schema_heladeria.sql
-- =====================================================
-- 3A  BASE DE DATOS - SISTEMA DE GESTIÓN DE HELADOS
-- Pegar completo en Supabase > SQL Editor > Run (una sola vez)
-- =====================================================

-- ---------- SEGURIDAD ----------
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text, full_name text,
  role text check (role in ('admin','caja','produccion','compras')),
  active boolean not null default false,
  created_at timestamptz default now()
);

-- Cada cuenta nueva de Authentication aparece como perfil inactivo y sin rol
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles(id,email) values (new.id,new.email) on conflict do nothing;
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

create or replace function app_role() returns text
language sql stable security definer set search_path = public as
$$ select role from profiles where id = auth.uid() and active $$;

create table app_settings (
  id int primary key default 1 check (id = 1),
  default_costing text not null default 'promedio',
  allow_negative_stock boolean not null default false
);
insert into app_settings default values;

-- ---------- MAESTROS ----------
create table items (            -- insumos, envases, tapas, etiquetas
  id uuid primary key default gen_random_uuid(),
  code text unique not null, name text not null,
  kind text not null default 'materia_prima'
    check (kind in ('materia_prima','envase','tapa','etiqueta','otro')),
  base_unit text not null check (base_unit in ('g','ml','unidad')),
  min_stock numeric(14,3) default 0,
  stock numeric(14,3) not null default 0,
  avg_cost numeric(14,6) not null default 0,
  max_cost numeric(14,6) not null default 0,
  last_cost numeric(14,6) not null default 0,
  active boolean default true,
  created_by uuid default auth.uid(), created_at timestamptz default now()
);
create table products (
  id uuid primary key default gen_random_uuid(),
  name text unique not null, active boolean default true,
  created_by uuid default auth.uid(), created_at timestamptz default now()
);
create table presentations (
  id uuid primary key default gen_random_uuid(),
  name text unique not null, volume_ml numeric(10,2) not null,
  active boolean default true
);
create table product_presentations (   -- producto terminado vendible
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  product_id uuid not null references products(id),
  presentation_id uuid not null references presentations(id),
  sale_price numeric(12,2) not null default 0,
  stock numeric(14,3) not null default 0,
  avg_cost numeric(14,6) not null default 0,
  active boolean default true,
  unique (product_id, presentation_id)
);
create table presentation_packaging (
  presentation_id uuid references presentations(id),
  item_id uuid references items(id),
  qty_per_unit numeric(12,3) not null default 1,
  primary key (presentation_id, item_id)
);
create table suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null, tax_id text, contact text, active boolean default true
);
create table payment_methods (
  id uuid primary key default gen_random_uuid(),
  name text unique not null, is_cash boolean default false, active boolean default true
);
insert into payment_methods(name,is_cash) values
  ('Efectivo',true),('QR',false),('Transferencia',false),('Otras',false);

create table categories (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('ingreso','gasto')),
  name text not null,
  parent_id uuid references categories(id),
  group_name text,  -- personal / administrativo / otros
  cashier_allowed boolean default false
);

-- ---------- RECETAS ----------
create table recipes (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references products(id),
  yield_liters numeric(10,3) not null check (yield_liters > 0),
  active boolean default true
);
create table recipe_items (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references recipes(id) on delete cascade,
  item_id uuid not null references items(id),
  qty_base numeric(14,3) not null check (qty_base > 0)  -- en unidad base
);

-- ---------- INVENTARIO DE INSUMOS ----------
create sequence seq_purchase;
create table purchases (
  id uuid primary key default gen_random_uuid(),
  number text unique not null,
  purchase_date date not null,
  supplier_id uuid references suppliers(id),
  payment_method_id uuid not null references payment_methods(id),
  document text, notes text, total numeric(14,2) not null,
  status text not null default 'confirmado' check (status in ('confirmado','anulado')),
  void_reason text, voided_by uuid, voided_at timestamptz,
  created_by uuid default auth.uid(), created_at timestamptz default now()
);
create table purchase_items (
  id uuid primary key default gen_random_uuid(),
  purchase_id uuid not null references purchases(id),
  item_id uuid not null references items(id),
  qty_base numeric(14,3) not null check (qty_base > 0),
  unit_cost_base numeric(14,6) not null check (unit_cost_base >= 0),
  amount numeric(14,2) not null
);
create table item_layers (            -- capas para UEPS
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references items(id),
  layer_date timestamptz default now(),
  qty_initial numeric(14,3) not null,
  qty_remaining numeric(14,3) not null,
  unit_cost numeric(14,6) not null,
  source_table text, source_id uuid
);
create table item_movements (         -- kárdex
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references items(id),
  moved_at timestamptz default now(),
  move_type text not null, concept text,
  source_table text, source_id uuid,
  qty_in numeric(14,3) default 0, value_in numeric(14,2) default 0,
  qty_out numeric(14,3) default 0, value_out numeric(14,2) default 0,
  balance_qty numeric(14,3) not null, balance_value numeric(14,2) not null,
  unit_cost_applied numeric(14,6), costing_method text,
  created_by uuid default auth.uid()
);
create table item_movement_layers (
  movement_id uuid references item_movements(id),
  layer_id uuid references item_layers(id),
  qty numeric(14,3), unit_cost numeric(14,6)
);

-- ---------- CAJA ----------
create table cash_movements (         -- registro diario central
  id uuid primary key default gen_random_uuid(),
  move_date date not null default (now() at time zone 'America/La_Paz')::date,
  move_type text not null check (move_type in ('venta','compra','gasto','otro_ingreso','otro_gasto')),
  category_id uuid references categories(id),
  description text,
  amount_in numeric(14,2) not null default 0,
  amount_out numeric(14,2) not null default 0,
  payment_method_id uuid references payment_methods(id),
  source_table text, source_id uuid,
  status text not null default 'confirmado' check (status in ('confirmado','anulado')),
  created_by uuid default auth.uid(), created_at timestamptz default now()
);

create table audit_log (
  id bigserial primary key, user_id uuid default auth.uid(),
  at timestamptz default now(), action text, table_name text, record_id uuid, detail jsonb
);

-- ---------- OPERACIÓN ATÓMICA: CONFIRMAR COMPRA ----------
-- p_items: [{"item_id":"...","qty_base":1000,"unit_cost_base":0.0075}, ...]
create or replace function confirm_purchase(
  p_date date, p_supplier uuid, p_payment uuid,
  p_document text, p_notes text, p_items jsonb
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid := gen_random_uuid(); v_total numeric := 0;
  r jsonb; it items%rowtype; q numeric; c numeric; amt numeric;
  new_qty numeric; new_val numeric; is_cash boolean;
begin
  if app_role() not in ('admin','compras') then raise exception 'Sin permiso'; end if;
  if jsonb_array_length(p_items) = 0 then raise exception 'La compra no tiene ítems'; end if;

  select sum(round((x->>'qty_base')::numeric * (x->>'unit_cost_base')::numeric, 2))
    into v_total from jsonb_array_elements(p_items) x;

  insert into purchases(id,number,purchase_date,supplier_id,payment_method_id,document,notes,total)
  values (v_id,'CP-'||lpad(nextval('seq_purchase')::text,5,'0'),p_date,p_supplier,p_payment,p_document,p_notes,v_total);

  for r in select * from jsonb_array_elements(p_items) loop
    q := (r->>'qty_base')::numeric; c := (r->>'unit_cost_base')::numeric;
    amt := round(q*c,2);
    select * into it from items where id = (r->>'item_id')::uuid for update;
    if not found then raise exception 'Insumo no existe'; end if;

    insert into purchase_items(purchase_id,item_id,qty_base,unit_cost_base,amount)
      values (v_id,it.id,q,c,amt);
    insert into item_layers(item_id,qty_initial,qty_remaining,unit_cost,source_table,source_id)
      values (it.id,q,q,c,'purchases',v_id);

    new_qty := it.stock + q;
    new_val := round(it.stock*it.avg_cost,2) + amt;
    insert into item_movements(item_id,move_type,concept,source_table,source_id,
      qty_in,value_in,balance_qty,balance_value,unit_cost_applied,costing_method)
      values (it.id,'compra','Compra',  'purchases',v_id,q,amt,new_qty,new_val,c,'promedio');

    update items set stock = new_qty,
      avg_cost = case when new_qty>0 then new_val/new_qty else c end,
      max_cost = greatest(max_cost,c), last_cost = c
    where id = it.id;
  end loop;

  select pm.is_cash into is_cash from payment_methods pm where pm.id = p_payment;
  insert into cash_movements(move_type,description,amount_out,payment_method_id,source_table,source_id)
    values ('compra','Compra '||coalesce(p_document,''),v_total,p_payment,'purchases',v_id);

  insert into audit_log(action,table_name,record_id) values ('confirmar_compra','purchases',v_id);
  return v_id;
end $$;

-- ---------- SEGURIDAD POR FILAS (RLS) ----------
do $$
declare t text;
begin
  foreach t in array array['profiles','app_settings','items','products','presentations',
    'product_presentations','presentation_packaging','suppliers','payment_methods','categories',
    'recipes','recipe_items','purchases','purchase_items','item_layers','item_movements',
    'item_movement_layers','cash_movements','audit_log']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy "admin_all" on %I for all using (app_role()=''admin'') with check (app_role()=''admin'')', t);
  end loop;
end $$;

-- Lecturas por rol (escrituras de compras/caja/producción van por funciones)
create policy "perfil_propio" on profiles for select using (id = auth.uid());
create policy "lee_settings" on app_settings for select using (app_role() is not null);
create policy "lee_pagos" on payment_methods for select using (app_role() is not null);
create policy "lee_productos" on products for select using (app_role() is not null);
create policy "lee_presentaciones" on presentations for select using (app_role() is not null);
create policy "lee_items" on items for select using (app_role() in ('produccion','compras'));
create policy "lee_proveedores" on suppliers for select using (app_role()='compras');
create policy "escribe_proveedores" on suppliers for all using (app_role()='compras') with check (app_role()='compras');
create policy "lee_compras" on purchases for select using (app_role()='compras');
create policy "lee_compras_det" on purchase_items for select using (app_role()='compras');
create policy "kardex_compras" on item_movements for select using (app_role()='compras');
create policy "lee_recetas" on recipes for select using (app_role()='produccion');
create policy "lee_recetas_det" on recipe_items for select using (app_role()='produccion');
create policy "caja_movs" on cash_movements for select using (app_role()='caja' and created_by = auth.uid());

-- Caja ve solo precio y stock (sin costos): vista restringida
create view v_pos_products as
  select pp.id, pp.code, p.name as product, pr.name as presentation, pp.sale_price, pp.stock
  from product_presentations pp
  join products p on p.id = pp.product_id
  join presentations pr on pr.id = pp.presentation_id
  where pp.active;
grant select on v_pos_products to authenticated;

grant execute on function confirm_purchase(date,uuid,uuid,text,text,jsonb) to authenticated;
grant execute on function app_role() to authenticated;

-- =====================================================
-- SEGUNDO SCRIPT (ejecutar DESPUÉS de crear tu usuario en
-- Authentication > Users > Add user). Cambia el correo:
-- =====================================================
-- update profiles set role='admin', active=true, full_name='Administrador'
-- where email = 'TU_CORREO@ejemplo.com';

-- >>>>>>>>>> 3A_parte2_operaciones.sql
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

-- >>>>>>>>>> 3A_parte3_reportes.sql
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

-- >>>>>>>>>> 4_completar_sistema.sql
-- =====================================================
-- PARTE 4 - COMPLETAR EL SISTEMA (correcciones + funciones nuevas)
-- Ejecutar DESPUÉS de las partes 1, 2 y 3.
-- Se puede ejecutar más de una vez sin romper nada.
-- =====================================================

-- ---------- CONFIGURACIÓN DEL NEGOCIO ----------
alter table app_settings add column if not exists business_name text not null default 'Heladería';
alter table app_settings add column if not exists business_nit text;
alter table app_settings add column if not exists business_address text;
alter table app_settings add column if not exists ticket_footer text default '¡Gracias por su compra!';

alter table expenses add column if not exists void_reason text;
alter table expenses add column if not exists voided_at timestamptz;
alter table cash_movements add column if not exists void_reason text;
alter table production_orders add column if not exists void_reason text;
alter table production_orders add column if not exists notes text;
-- Orden real de llegada de cada capa (necesario para UEPS)
alter table item_layers add column if not exists seq bigserial;

create or replace function bo_today() returns date
language sql stable as $$ select (now() at time zone 'America/La_Paz')::date $$;
grant execute on function bo_today() to authenticated;

-- Caja solo puede registrar en la fecha de hoy
create or replace function check_cashier_date(p_date date) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if app_role() = 'caja' and p_date <> bo_today() then
    raise exception 'Caja solo puede registrar movimientos con la fecha de hoy';
  end if;
end $$;
revoke execute on function check_cashier_date(date) from public, anon, authenticated;

-- ---------- NUNCA QUEDARSE SIN ADMINISTRADOR ----------
create or replace function protect_last_admin() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.role = 'admin' and old.active
     and (new.role is distinct from 'admin' or not new.active)
     and not exists (select 1 from profiles where id <> old.id and role = 'admin' and active) then
    raise exception 'Debe quedar al menos un administrador activo';
  end if;
  return new;
end $$;
drop trigger if exists trg_protect_last_admin on profiles;
create trigger trg_protect_last_admin before update on profiles
  for each row execute function protect_last_admin();

-- ---------- CORRECCIÓN: SALIDA DE INSUMOS CON UEPS REAL ----------
-- Antes recorría las capas de la más antigua a la más nueva (eso es PEPS).
-- UEPS = últimas entradas, primeras salidas: de la más nueva a la más antigua.
create or replace function consume_item(p_item uuid, p_qty numeric, p_method text,
  p_src_table text, p_src_id uuid, p_concept text) returns numeric
language plpgsql security definer set search_path = public as $$
declare it items%rowtype; st app_settings%rowtype; l item_layers%rowtype;
  rem numeric := p_qty; take numeric; v_cost numeric := 0; mv uuid := gen_random_uuid();
  new_stock numeric; new_avg numeric; layer_val numeric;
begin
  if p_method not in ('promedio','ueps','maximo') then raise exception 'Método inválido'; end if;
  if p_qty is null or p_qty <= 0 then return 0; end if;
  select * into it from items where id = p_item for update;
  if not found then raise exception 'Insumo no existe'; end if;
  select * into st from app_settings;
  if it.stock < p_qty and not st.allow_negative_stock then
    raise exception 'Stock insuficiente de %: disponible % %, se necesita % %',
      it.name, round(it.stock,3), it.base_unit, round(p_qty,3), it.base_unit;
  end if;
  new_stock := it.stock - p_qty;
  insert into item_movements(id,item_id,move_type,concept,source_table,source_id,
    qty_out,value_out,balance_qty,balance_value,costing_method)
  values (mv,p_item,'consumo',p_concept,p_src_table,p_src_id,p_qty,0,0,0,p_method);

  for l in select * from item_layers where item_id = p_item and qty_remaining > 0
           order by seq desc for update loop
    exit when rem <= 0;
    take := least(l.qty_remaining, rem);
    update item_layers set qty_remaining = qty_remaining - take where id = l.id;
    if p_method = 'ueps' then v_cost := v_cost + take * l.unit_cost; end if;
    insert into item_movement_layers values (mv, l.id, take, l.unit_cost);
    rem := rem - take;
  end loop;

  if p_method = 'ueps' then v_cost := v_cost + rem * it.last_cost;
  elsif p_method = 'maximo' then v_cost := p_qty * it.max_cost;
  else v_cost := p_qty * it.avg_cost; end if;
  v_cost := round(v_cost, 2);

  new_avg := it.avg_cost;
  if p_method = 'ueps' and new_stock > 0 then
    select coalesce(sum(qty_remaining * unit_cost), 0) into layer_val from item_layers where item_id = p_item;
    new_avg := layer_val / new_stock;
  end if;
  update item_movements set value_out = v_cost, balance_qty = new_stock,
    balance_value = round(new_stock * new_avg, 2),
    unit_cost_applied = v_cost / p_qty where id = mv;
  update items set stock = new_stock, avg_cost = new_avg where id = p_item;
  return v_cost;
end $$;
revoke execute on function consume_item(uuid,numeric,text,text,uuid,text) from public, anon, authenticated;

create or replace function preview_cost(p_item uuid, p_qty numeric, p_method text) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare it items%rowtype; l record; rem numeric := p_qty; c numeric := 0;
begin
  if app_role() not in ('admin','produccion','compras') then raise exception 'Sin permiso'; end if;
  select * into it from items where id = p_item;
  if p_method = 'ueps' then
    for l in select qty_remaining, unit_cost from item_layers
             where item_id = p_item and qty_remaining > 0 order by seq desc loop
      exit when rem <= 0;
      c := c + least(l.qty_remaining, rem) * l.unit_cost; rem := rem - least(l.qty_remaining, rem);
    end loop;
    return round(c + rem * it.last_cost, 2);
  elsif p_method = 'maximo' then return round(p_qty * it.max_cost, 2);
  else return round(p_qty * it.avg_cost, 2); end if;
end $$;
grant execute on function preview_cost(uuid,numeric,text) to authenticated;

-- ---------- CORRECCIÓN: COMPRA (fecha en caja + validaciones) ----------
create or replace function confirm_purchase(
  p_date date, p_supplier uuid, p_payment uuid,
  p_document text, p_notes text, p_items jsonb
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid := gen_random_uuid(); v_total numeric := 0;
  r jsonb; it items%rowtype; q numeric; c numeric; amt numeric;
  new_qty numeric; new_val numeric;
begin
  if app_role() not in ('admin','compras') then raise exception 'Sin permiso'; end if;
  if p_payment is null then raise exception 'Elija la forma de pago'; end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'La compra no tiene ítems'; end if;
  if not day_is_open(p_date) then raise exception 'El día % ya está cerrado', p_date; end if;

  select sum(round((x->>'qty_base')::numeric * (x->>'unit_cost_base')::numeric, 2))
    into v_total from jsonb_array_elements(p_items) x;

  insert into purchases(id,number,purchase_date,supplier_id,payment_method_id,document,notes,total)
  values (v_id,'CP-'||lpad(nextval('seq_purchase')::text,5,'0'),p_date,p_supplier,p_payment,
          nullif(trim(p_document),''),nullif(trim(p_notes),''),v_total);

  for r in select * from jsonb_array_elements(p_items) loop
    q := (r->>'qty_base')::numeric; c := (r->>'unit_cost_base')::numeric;
    if q is null or q <= 0 then raise exception 'Cantidad inválida en la compra'; end if;
    if c is null or c < 0 then raise exception 'Costo inválido en la compra'; end if;
    amt := round(q * c, 2);
    select * into it from items where id = (r->>'item_id')::uuid for update;
    if not found then raise exception 'Insumo no existe'; end if;

    insert into purchase_items(purchase_id,item_id,qty_base,unit_cost_base,amount)
      values (v_id,it.id,q,c,amt);
    insert into item_layers(item_id,qty_initial,qty_remaining,unit_cost,source_table,source_id)
      values (it.id,q,q,c,'purchases',v_id);

    new_qty := it.stock + q;
    new_val := round(greatest(it.stock,0) * it.avg_cost, 2) + amt;
    insert into item_movements(item_id,move_type,concept,source_table,source_id,
      qty_in,value_in,balance_qty,balance_value,unit_cost_applied,costing_method)
      values (it.id,'compra','Compra','purchases',v_id,q,amt,new_qty,new_val,c,'promedio');

    update items set stock = new_qty,
      avg_cost = case when new_qty > 0 then new_val / new_qty else c end,
      max_cost = greatest(max_cost, c), last_cost = c
    where id = it.id;
  end loop;

  insert into cash_movements(move_date,move_type,description,amount_out,payment_method_id,source_table,source_id)
    values (p_date,'compra','Compra '||coalesce(nullif(trim(p_document),''),''),v_total,p_payment,'purchases',v_id);

  insert into audit_log(action,table_name,record_id) values ('confirmar_compra','purchases',v_id);
  return v_id;
end $$;

-- ---------- CORRECCIÓN: PRODUCCIÓN (error "total_cost is ambiguous") ----------
drop function if exists confirm_production(date,uuid,text,jsonb,jsonb);
create or replace function confirm_production(p_date date, p_product uuid, p_method text,
  p_outputs jsonb, p_overrides jsonb default '[]', p_notes text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare rc recipes%rowtype; v_id uuid := gen_random_uuid(); total_ml numeric; v_liters numeric;
  content_cost numeric := 0; v_total_cost numeric := 0; ri record; pk record; x jsonb;
  pp product_presentations%rowtype; pr presentations%rowtype; v_method text;
  q numeric; theo numeric; c numeric; pack numeric; v_units numeric; ucost numeric; ns numeric;
begin
  if app_role() not in ('admin','produccion') then raise exception 'Sin permiso'; end if;
  v_method := coalesce(nullif(p_method,''), (select default_costing from app_settings));
  select * into rc from recipes where product_id = p_product and active order by id limit 1;
  if not found then raise exception 'El producto no tiene receta activa'; end if;
  if not exists (select 1 from recipe_items where recipe_id = rc.id) then
    raise exception 'La receta no tiene ingredientes'; end if;

  select coalesce(sum((o->>'units')::numeric * presn.volume_ml), 0) into total_ml
    from jsonb_array_elements(coalesce(p_outputs,'[]')) o
    join product_presentations p on p.id = (o->>'pp_id')::uuid and p.product_id = p_product
    join presentations presn on presn.id = p.presentation_id
    where (o->>'units')::numeric > 0;
  if total_ml <= 0 then raise exception 'Indique las unidades obtenidas'; end if;
  v_liters := total_ml / 1000;

  insert into production_orders(id,number,order_date,product_id,recipe_id,liters_obtained,costing_method,notes)
  values (v_id,'OP-'||lpad(nextval('seq_production')::text,5,'0'),p_date,p_product,rc.id,v_liters,v_method,nullif(trim(p_notes),''));

  for ri in select * from recipe_items where recipe_id = rc.id loop
    theo := round(ri.qty_base * v_liters / rc.yield_liters, 3);
    q := null;
    select (o->>'qty_base')::numeric into q from jsonb_array_elements(coalesce(p_overrides,'[]')) o
      where (o->>'item_id')::uuid = ri.item_id limit 1;
    q := coalesce(q, theo);
    if q < 0 then raise exception 'Consumo real inválido'; end if;
    c := consume_item(ri.item_id, q, v_method, 'production_orders', v_id, 'Consumo de receta '||v_liters||' L');
    insert into production_consumptions(order_id,item_id,qty_theoretical,qty_real,cost)
      values (v_id, ri.item_id, theo, q, c);
    content_cost := content_cost + c;
  end loop;

  for x in select * from jsonb_array_elements(p_outputs) loop
    v_units := (x->>'units')::numeric;
    if v_units is null or v_units <= 0 then continue; end if;
    select * into pp from product_presentations where id = (x->>'pp_id')::uuid and product_id = p_product for update;
    if not found then continue; end if;
    select * into pr from presentations where id = pp.presentation_id;
    pack := 0;
    for pk in select * from presentation_packaging where presentation_id = pp.presentation_id loop
      c := consume_item(pk.item_id, pk.qty_per_unit * v_units, v_method, 'production_orders', v_id, 'Envase/tapa/etiqueta');
      insert into production_consumptions(order_id,item_id,qty_theoretical,qty_real,cost,is_packaging)
        values (v_id, pk.item_id, pk.qty_per_unit * v_units, pk.qty_per_unit * v_units, c, true);
      pack := pack + c;
    end loop;
    ucost := (content_cost / total_ml * pr.volume_ml * v_units + pack) / v_units;
    v_total_cost := v_total_cost + ucost * v_units;
    ns := pp.stock + v_units;
    update product_presentations set stock = ns,
      avg_cost = case when ns > 0 then (greatest(pp.stock,0) * pp.avg_cost + ucost * v_units) / (greatest(pp.stock,0) + v_units) else ucost end
      where id = pp.id;
    insert into production_outputs(order_id,pp_id,units,unit_cost) values (v_id, pp.id, v_units, ucost);
    insert into fg_movements(pp_id,move_type,qty_in,unit_cost,balance_qty,source_table,source_id)
      values (pp.id,'produccion',v_units,ucost,ns,'production_orders',v_id);
  end loop;

  update production_orders set total_cost = round(v_total_cost, 2) where id = v_id;
  insert into audit_log(action,table_name,record_id) values ('confirmar_produccion','production_orders',v_id);
  return v_id;
end $$;
grant execute on function confirm_production(date,uuid,text,jsonb,jsonb,text) to authenticated;

-- Vista previa de producción: qué insumos se usarán, stock disponible y costo estimado
create or replace function preview_production(p_product uuid, p_outputs jsonb, p_method text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare rc recipes%rowtype; total_ml numeric; v_liters numeric; v_method text; res jsonb := '[]';
  r record;
begin
  if app_role() not in ('admin','produccion') then raise exception 'Sin permiso'; end if;
  v_method := coalesce(nullif(p_method,''), (select default_costing from app_settings));
  select * into rc from recipes where product_id = p_product and active order by id limit 1;
  if not found then return jsonb_build_object('error','El producto no tiene receta activa','items','[]'::jsonb); end if;
  select coalesce(sum((o->>'units')::numeric * presn.volume_ml), 0) into total_ml
    from jsonb_array_elements(coalesce(p_outputs,'[]')) o
    join product_presentations p on p.id = (o->>'pp_id')::uuid
    join presentations presn on presn.id = p.presentation_id
    where coalesce((o->>'units')::numeric,0) > 0;
  v_liters := total_ml / 1000;
  for r in
    select i.id, i.name, i.base_unit, i.stock, false as pack,
           round(ri.qty_base * v_liters / rc.yield_liters, 3) as qty
      from recipe_items ri join items i on i.id = ri.item_id where ri.recipe_id = rc.id
    union all
    select i.id, i.name, i.base_unit, i.stock, true,
           sum(k.qty_per_unit * (o->>'units')::numeric)
      from jsonb_array_elements(coalesce(p_outputs,'[]')) o
      join product_presentations p on p.id = (o->>'pp_id')::uuid
      join presentation_packaging k on k.presentation_id = p.presentation_id
      join items i on i.id = k.item_id
      where coalesce((o->>'units')::numeric,0) > 0
      group by i.id, i.name, i.base_unit, i.stock
  loop
    res := res || jsonb_build_object('item_id',r.id,'name',r.name,'unit',r.base_unit,'stock',r.stock,
      'qty',r.qty,'packaging',r.pack,'enough',r.stock >= r.qty,
      'cost',case when r.qty > 0 then preview_cost(r.id, r.qty, v_method) else 0 end);
  end loop;
  return jsonb_build_object('liters',v_liters,'yield_liters',rc.yield_liters,'method',v_method,'items',res);
end $$;
grant execute on function preview_production(uuid,jsonb,text) to authenticated;

-- ---------- VENTA: caja solo con fecha de hoy ----------
create or replace function confirm_sale(p_date date, p_payment uuid, p_notes text, p_items jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid := gen_random_uuid(); x jsonb; pp product_presentations%rowtype;
  st app_settings%rowtype; q numeric; amt numeric; v_total numeric := 0; ns numeric;
begin
  if app_role() not in ('admin','caja') then raise exception 'Sin permiso'; end if;
  perform check_cashier_date(p_date);
  if p_payment is null then raise exception 'Elija la forma de pago'; end if;
  if not day_is_open(p_date) then raise exception 'El día % ya está cerrado', p_date; end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'La venta no tiene ítems'; end if;
  select * into st from app_settings;
  insert into sales(id,number,sale_date,payment_method_id,notes,total)
    values (v_id,'VT-'||lpad(nextval('seq_sale')::text,5,'0'),p_date,p_payment,nullif(trim(p_notes),''),0);

  for x in select * from jsonb_array_elements(p_items) loop
    q := (x->>'qty')::numeric;
    if q is null or q <= 0 then raise exception 'Cantidad inválida'; end if;
    select * into pp from product_presentations where id = (x->>'pp_id')::uuid and active for update;
    if not found then raise exception 'Producto no disponible'; end if;
    if pp.stock < q and not st.allow_negative_stock then
      raise exception 'Stock insuficiente de %. Disponible: % unidades', pp.code, pp.stock;
    end if;
    amt := round(q * pp.sale_price, 2); v_total := v_total + amt; ns := pp.stock - q;
    insert into sale_items(sale_id,pp_id,qty,unit_price,amount,unit_cost,cost_total)
      values (v_id,pp.id,q,pp.sale_price,amt,pp.avg_cost,round(q * pp.avg_cost,2));
    update product_presentations set stock = ns where id = pp.id;
    insert into fg_movements(pp_id,move_type,qty_out,unit_cost,balance_qty,source_table,source_id)
      values (pp.id,'venta',q,pp.avg_cost,ns,'sales',v_id);
  end loop;

  update sales set total = v_total where id = v_id;
  insert into cash_movements(move_date,move_type,description,amount_in,payment_method_id,source_table,source_id)
    values (p_date,'venta','Venta '||(select number from sales where id = v_id),v_total,p_payment,'sales',v_id);
  return v_id;
end $$;

-- ---------- GASTOS / OTROS INGRESOS ----------
create or replace function register_expense(p_date date, p_category uuid, p_payment uuid,
  p_amount numeric, p_desc text, p_document text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid := gen_random_uuid(); cat categories%rowtype;
begin
  if app_role() not in ('admin','caja') then raise exception 'Sin permiso'; end if;
  perform check_cashier_date(p_date);
  if not day_is_open(p_date) then raise exception 'El día % ya está cerrado', p_date; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'El monto debe ser mayor a cero'; end if;
  select * into cat from categories where id = p_category and kind = 'gasto';
  if not found then raise exception 'Categoría inválida'; end if;
  if app_role() = 'caja' and not cat.cashier_allowed then
    raise exception 'Esta categoría no está autorizada para Caja'; end if;
  insert into expenses(id,expense_date,category_id,payment_method_id,amount,description,document)
    values (v_id,p_date,p_category,p_payment,p_amount,p_desc,p_document);
  insert into cash_movements(move_date,move_type,category_id,description,amount_out,payment_method_id,source_table,source_id)
    values (p_date,'gasto',p_category,coalesce(nullif(trim(p_desc),''),cat.name),p_amount,p_payment,'expenses',v_id);
  insert into audit_log(action,table_name,record_id) values ('registrar_gasto','expenses',v_id);
  return v_id;
end $$;

create or replace function register_income(p_date date,p_category uuid,p_payment uuid,p_amount numeric,p_desc text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v uuid := gen_random_uuid(); cat categories%rowtype;
begin
  if app_role() not in ('admin','caja') then raise exception 'Sin permiso'; end if;
  perform check_cashier_date(p_date);
  if not day_is_open(p_date) then raise exception 'El día ya está cerrado'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'El monto debe ser mayor a cero'; end if;
  select * into cat from categories where id=p_category and kind='ingreso';
  if not found then raise exception 'Categoría inválida'; end if;
  if app_role()='caja' and not cat.cashier_allowed then raise exception 'Categoría no autorizada para Caja'; end if;
  insert into cash_movements(id,move_date,move_type,category_id,description,amount_in,payment_method_id,source_table,source_id)
    values (v,p_date,'otro_ingreso',p_category,coalesce(nullif(trim(p_desc),''),cat.name),p_amount,p_payment,'incomes',v);
  insert into audit_log(action,table_name,record_id) values ('registrar_ingreso','cash_movements',v);
  return v;
end $$;

create or replace function void_expense(p_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare e expenses%rowtype;
begin
  if coalesce(trim(p_reason),'') = '' then raise exception 'El motivo es obligatorio'; end if;
  select * into e from expenses where id = p_id for update;
  if not found or e.status = 'anulado' then raise exception 'Gasto no válido'; end if;
  if app_role() not in ('admin','caja') or (app_role()='caja' and e.created_by <> auth.uid()) then
    raise exception 'Sin permiso'; end if;
  if not day_is_open(e.expense_date) then raise exception 'El día está cerrado'; end if;
  update expenses set status='anulado', void_reason=p_reason, voided_at=now() where id = p_id;
  update cash_movements set status='anulado', void_reason=p_reason where source_table='expenses' and source_id=p_id;
  insert into audit_log(action,table_name,record_id,detail) values ('anular_gasto','expenses',p_id,jsonb_build_object('motivo',p_reason));
end $$;

create or replace function void_income(p_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare m cash_movements%rowtype;
begin
  if coalesce(trim(p_reason),'') = '' then raise exception 'El motivo es obligatorio'; end if;
  select * into m from cash_movements where id = p_id and move_type = 'otro_ingreso' for update;
  if not found or m.status = 'anulado' then raise exception 'Ingreso no válido'; end if;
  if app_role() not in ('admin','caja') or (app_role()='caja' and m.created_by <> auth.uid()) then
    raise exception 'Sin permiso'; end if;
  if not day_is_open(m.move_date) then raise exception 'El día está cerrado'; end if;
  update cash_movements set status='anulado', void_reason=p_reason where id = p_id;
  insert into audit_log(action,table_name,record_id,detail) values ('anular_ingreso','cash_movements',p_id,jsonb_build_object('motivo',p_reason));
end $$;

-- ---------- ANULAR PRODUCCIÓN (guarda el motivo) ----------
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
    if pp.stock < x.units then raise exception 'No se puede anular: parte de esta producción ya fue vendida o ajustada'; end if;
  end loop;
  for x in select * from production_outputs where order_id=p_id loop
    select * into pp from product_presentations where id=x.pp_id for update; ns:=pp.stock-x.units;
    update product_presentations set stock=ns,
      avg_cost = case when ns > 0 then greatest((pp.stock*pp.avg_cost - x.units*x.unit_cost)/ns, 0) else pp.avg_cost end
      where id=pp.id;
    insert into fg_movements(pp_id,move_type,qty_out,unit_cost,balance_qty,source_table,source_id)
      values (pp.id,'anulacion_produccion',x.units,x.unit_cost,ns,'production_orders',p_id);
  end loop;
  for c in select * from production_consumptions where order_id=p_id and qty_real > 0 loop
    select * into it from items where id=c.item_id for update; ns:=it.stock+c.qty_real;
    insert into item_layers(item_id,qty_initial,qty_remaining,unit_cost,source_table,source_id)
      values (it.id,c.qty_real,c.qty_real,c.cost/c.qty_real,'production_orders',p_id);
    insert into item_movements(item_id,move_type,concept,source_table,source_id,qty_in,value_in,balance_qty,balance_value,unit_cost_applied,costing_method)
      values (it.id,'anulacion_produccion','Anulación de producción '||o.number,'production_orders',p_id,c.qty_real,c.cost,ns,
              round(greatest(it.stock,0)*it.avg_cost+c.cost,2),c.cost/c.qty_real,o.costing_method);
    update items set stock=ns, avg_cost=case when ns>0 then (greatest(it.stock,0)*it.avg_cost+c.cost)/(greatest(it.stock,0)+c.qty_real) else avg_cost end where id=it.id;
  end loop;
  update production_orders set status='anulado', void_reason=p_reason where id=p_id;
  insert into audit_log(action,table_name,record_id,detail) values ('anular_produccion','production_orders',p_id,jsonb_build_object('motivo',p_reason));
end $$;

-- ---------- AJUSTES DE INVENTARIO (con costo para inventario inicial) ----------
drop function if exists adjust_inventory(uuid,numeric,text);
create or replace function adjust_inventory(p_item uuid, p_delta numeric, p_reason text, p_unit_cost numeric default null)
returns void language plpgsql security definer set search_path=public as $$
declare it items%rowtype; ns numeric; uc numeric; nv numeric;
begin
  if app_role()<>'admin' then raise exception 'Solo el administrador'; end if;
  if coalesce(trim(p_reason),'')='' or coalesce(p_delta,0)=0 then raise exception 'Indique cantidad y motivo'; end if;
  if p_delta < 0 then
    perform consume_item(p_item,-p_delta,'promedio','adjustments',null,'Ajuste: '||p_reason);
  else
    select * into it from items where id=p_item for update;
    if not found then raise exception 'Insumo no existe'; end if;
    uc := coalesce(p_unit_cost, it.avg_cost);
    if uc < 0 then raise exception 'Costo inválido'; end if;
    ns := it.stock + p_delta;
    nv := round(greatest(it.stock,0)*it.avg_cost,2) + round(p_delta*uc,2);
    insert into item_layers(item_id,qty_initial,qty_remaining,unit_cost,source_table) values (p_item,p_delta,p_delta,uc,'adjustments');
    insert into item_movements(item_id,move_type,concept,source_table,qty_in,value_in,balance_qty,balance_value,unit_cost_applied,costing_method)
      values (p_item,'ajuste','Ajuste: '||p_reason,'adjustments',p_delta,round(p_delta*uc,2),ns,nv,uc,'promedio');
    update items set stock = ns,
      avg_cost = case when ns > 0 then nv/ns else uc end,
      max_cost = greatest(max_cost, uc),
      last_cost = case when p_unit_cost is not null then uc else last_cost end
    where id=p_item;
  end if;
  insert into audit_log(action,table_name,record_id,detail) values ('ajuste_inventario','items',p_item,
    jsonb_build_object('delta',p_delta,'motivo',p_reason,'costo',p_unit_cost));
end $$;
grant execute on function adjust_inventory(uuid,numeric,text,numeric) to authenticated;

-- Ajuste de producto terminado (helado derretido, muestras, conteo físico)
create or replace function adjust_fg(p_pp uuid, p_delta numeric, p_reason text) returns void
language plpgsql security definer set search_path=public as $$
declare pp product_presentations%rowtype; ns numeric;
begin
  if app_role()<>'admin' then raise exception 'Solo el administrador'; end if;
  if coalesce(trim(p_reason),'')='' or coalesce(p_delta,0)=0 then raise exception 'Indique cantidad y motivo'; end if;
  select * into pp from product_presentations where id=p_pp for update;
  if not found then raise exception 'Producto no existe'; end if;
  ns := pp.stock + p_delta;
  if ns < 0 and not (select allow_negative_stock from app_settings) then
    raise exception 'Stock insuficiente. Disponible: % unidades', pp.stock; end if;
  update product_presentations set stock = ns where id = p_pp;
  insert into fg_movements(pp_id,move_type,qty_in,qty_out,unit_cost,balance_qty,source_table)
    values (p_pp,'ajuste',greatest(p_delta,0),greatest(-p_delta,0),pp.avg_cost,ns,'adjustments');
  insert into audit_log(action,table_name,record_id,detail) values ('ajuste_terminado','product_presentations',p_pp,
    jsonb_build_object('delta',p_delta,'motivo',p_reason));
end $$;
grant execute on function adjust_fg(uuid,numeric,text) to authenticated;

-- ---------- ARQUEO ----------
create or replace function close_day(p_date date, p_counted_cash numeric, p_notes text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid := gen_random_uuid(); opening numeric; tin numeric; tout numeric; theo numeric; diff numeric;
begin
  if app_role() not in ('admin','caja') then raise exception 'Sin permiso'; end if;
  perform check_cashier_date(p_date);
  if p_counted_cash is null or p_counted_cash < 0 then raise exception 'Ingrese el efectivo contado'; end if;
  if not day_is_open(p_date) then raise exception 'El día ya está cerrado'; end if;
  select coalesce((select counted_cash from cash_closures where status='cerrado' and closure_date < p_date
                   order by closure_date desc limit 1),0) into opening;
  select coalesce(sum(cm.amount_in),0), coalesce(sum(cm.amount_out),0) into tin, tout
    from cash_movements cm join payment_methods pm on pm.id = cm.payment_method_id
    where cm.move_date = p_date and cm.status='confirmado' and pm.is_cash;
  theo := opening + tin - tout; diff := p_counted_cash - theo;
  if diff <> 0 and coalesce(trim(p_notes),'') = '' then
    raise exception 'Hay una diferencia de Bs %. Escriba una observación.', round(diff,2); end if;
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

-- Resumen del día antes de cerrar (lo que el sistema espera encontrar en caja)
create or replace function day_summary(p_date date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare opening numeric; lines jsonb; tin numeric; tout numeric;
begin
  if app_role() not in ('admin','caja') then raise exception 'Sin permiso'; end if;
  select coalesce((select counted_cash from cash_closures where status='cerrado' and closure_date < p_date
                   order by closure_date desc limit 1),0) into opening;
  select coalesce(jsonb_agg(jsonb_build_object('method',name,'is_cash',is_cash,'in',i,'out',o) order by is_cash desc, name),'[]')
    into lines from (
      select pm.name, pm.is_cash, coalesce(sum(cm.amount_in),0) i, coalesce(sum(cm.amount_out),0) o
      from payment_methods pm left join cash_movements cm
        on cm.payment_method_id = pm.id and cm.move_date = p_date and cm.status='confirmado'
      group by pm.id, pm.name, pm.is_cash) t;
  select coalesce(sum(cm.amount_in),0), coalesce(sum(cm.amount_out),0) into tin, tout
    from cash_movements cm join payment_methods pm on pm.id = cm.payment_method_id
    where cm.move_date = p_date and cm.status='confirmado' and pm.is_cash;
  return jsonb_build_object('date',p_date,'opening',opening,'cash_in',tin,'cash_out',tout,
    'theoretical',opening+tin-tout,'lines',lines,'is_open',day_is_open(p_date),
    'sales_count',(select count(*) from sales where sale_date=p_date and status='confirmado'),
    'sales_total',(select coalesce(sum(total),0) from sales where sale_date=p_date and status='confirmado'));
end $$;
grant execute on function day_summary(date) to authenticated;

-- ---------- ESTADO DE RESULTADOS (incluye mermas) ----------
create or replace function income_statement(p_from date,p_to date) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v numeric; c numeric; g jsonb; op numeric; og numeric; oi numeric; ub numeric; mi numeric; mf numeric;
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
  select coalesce(sum(value_out - value_in),0) into mi from item_movements
    where source_table='adjustments' and (moved_at at time zone 'America/La_Paz')::date between p_from and p_to;
  select coalesce(sum((qty_out - qty_in) * coalesce(unit_cost,0)),0) into mf from fg_movements
    where move_type='ajuste' and (moved_at at time zone 'America/La_Paz')::date between p_from and p_to;
  ub := v - c;
  return jsonb_build_object('ventas',v,'costo_ventas',c,'utilidad_bruta',ub,
    'margen_bruto',case when v>0 then round(ub/v*100,2) else 0 end,'gastos',g,'total_operativos',op,
    'resultado_operativo',ub-op,'otros_ingresos',oi,'otros_gastos',og,
    'mermas',round(mi+mf,2),'resultado',round(ub-op+oi-og-mi-mf,2));
end $$;

-- ---------- PANEL DE INICIO SEGÚN ROL ----------
create or replace function dashboard() returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare d date := bo_today(); m date := date_trunc('month', bo_today())::date; r text := app_role();
  res jsonb := jsonb_build_object('role', r, 'today', bo_today());
begin
  if r is null then raise exception 'Sin permiso'; end if;
  if r in ('admin','compras') then
    res := res || jsonb_build_object(
      'low_stock',(select coalesce(jsonb_agg(jsonb_build_object('name',name,'stock',stock,'min',min_stock,'unit',base_unit) order by name),'[]')
                   from items where active and stock <= min_stock),
      'compras_mes',(select coalesce(sum(total),0) from purchases where status='confirmado' and purchase_date>=m));
  end if;
  if r = 'admin' then
    res := res || jsonb_build_object(
      'ventas_hoy',(select coalesce(sum(total),0) from sales where status='confirmado' and sale_date=d),
      'ventas_mes',(select coalesce(sum(total),0) from sales where status='confirmado' and sale_date>=m),
      'utilidad_bruta_mes',(select coalesce(sum(si.amount - si.cost_total),0) from sale_items si join sales s on s.id=si.sale_id
                            where s.status='confirmado' and s.sale_date>=m),
      'gastos_mes',(select coalesce(sum(amount),0) from expenses where status='confirmado' and expense_date>=m),
      'valor_insumos',(select round(coalesce(sum(greatest(stock,0)*avg_cost),0),2) from items),
      'valor_terminados',(select round(coalesce(sum(greatest(stock,0)*avg_cost),0),2) from product_presentations),
      'ventas_14d',(select jsonb_agg(jsonb_build_object('d',dd,'t',coalesce(t,0)) order by dd) from
                     (select gs::date dd, (select sum(total) from sales where status='confirmado' and sale_date=gs::date) t
                      from generate_series(d-13, d, interval '1 day') gs) z),
      'top_mes',(select coalesce(jsonb_agg(x order by (x->>'u')::numeric desc),'[]') from
                  (select jsonb_build_object('name',p.name||' '||pr.name,'u',sum(si.qty),'t',sum(si.amount)) x
                   from sale_items si join sales s on s.id=si.sale_id and s.status='confirmado' and s.sale_date>=m
                   join product_presentations pp on pp.id=si.pp_id join products p on p.id=pp.product_id
                   join presentations pr on pr.id=pp.presentation_id group by p.name, pr.name
                   order by sum(si.qty) desc limit 5) z));
  end if;
  if r = 'caja' then
    res := res || jsonb_build_object(
      'mis_ventas_hoy',(select coalesce(sum(total),0) from sales where status='confirmado' and sale_date=d and created_by=auth.uid()),
      'mis_tickets_hoy',(select count(*) from sales where status='confirmado' and sale_date=d and created_by=auth.uid()));
  end if;
  if r in ('admin','caja') then
    res := res || jsonb_build_object('dia_abierto', day_is_open(d));
  end if;
  if r in ('admin','produccion','caja') then
    res := res || jsonb_build_object(
      'terminados',(select coalesce(jsonb_agg(jsonb_build_object('name',p.name||' '||pr.name,'stock',pp.stock) order by p.name, pr.volume_ml),'[]')
                    from product_presentations pp join products p on p.id=pp.product_id
                    join presentations pr on pr.id=pp.presentation_id where pp.active));
  end if;
  if r in ('admin','produccion') then
    res := res || jsonb_build_object(
      'litros_mes',(select coalesce(sum(liters_obtained),0) from production_orders where status='confirmado' and order_date>=m),
      'ordenes_mes',(select count(*) from production_orders where status='confirmado' and order_date>=m));
  end if;
  return res;
end $$;
grant execute on function dashboard() to authenticated;

-- ---------- VISTAS DE CONSULTA ----------
create or replace view v_pos_products as
  select pp.id, pp.code, p.name as product, pr.name as presentation, pp.sale_price, pp.stock
  from product_presentations pp
  join products p on p.id = pp.product_id
  join presentations pr on pr.id = pp.presentation_id
  where pp.active and p.active and app_role() in ('admin','caja');

create or replace view v_catalog as
  select id, code, product_id, presentation_id, stock, active from product_presentations
  where active and app_role() is not null;

drop view if exists v_fg_stock;
create view v_fg_stock as
  select pp.id, pp.code, pp.product_id, p.name as product, pr.name as presentation, pr.volume_ml,
         pp.sale_price, pp.stock, pp.active,
         case when app_role()='admin' then pp.avg_cost end as avg_cost
  from product_presentations pp join products p on p.id=pp.product_id
  join presentations pr on pr.id=pp.presentation_id
  where app_role() in ('admin','produccion','caja');
grant select on v_fg_stock to authenticated;

drop view if exists v_kardex;
create view v_kardex with (security_invoker=true) as
  select m.*, i.code as item_code, i.name as item_name, i.base_unit
  from item_movements m join items i on i.id = m.item_id;
grant select on v_kardex to authenticated;

drop view if exists v_fg_kardex;
create view v_fg_kardex with (security_invoker=true) as
  select m.*, p.name as product, pr.name as presentation
  from fg_movements m join product_presentations pp on pp.id=m.pp_id
  join products p on p.id=pp.product_id join presentations pr on pr.id=pp.presentation_id;
grant select on v_fg_kardex to authenticated;

drop view if exists v_sales;
create view v_sales with (security_invoker=true) as
  select s.*, pm.name as payment_method, pf.full_name as seller, pf.email as seller_email
  from sales s left join payment_methods pm on pm.id=s.payment_method_id
  left join profiles pf on pf.id=s.created_by;
grant select on v_sales to authenticated;

drop view if exists v_purchases;
create view v_purchases with (security_invoker=true) as
  select pu.*, su.name as supplier, pm.name as payment_method
  from purchases pu left join suppliers su on su.id=pu.supplier_id
  left join payment_methods pm on pm.id=pu.payment_method_id;
grant select on v_purchases to authenticated;

drop view if exists v_cash;
create view v_cash with (security_invoker=true) as
  select cm.*, pm.name as payment_method, pm.is_cash, ca.name as category
  from cash_movements cm left join payment_methods pm on pm.id=cm.payment_method_id
  left join categories ca on ca.id=cm.category_id;
grant select on v_cash to authenticated;

drop view if exists v_expenses;
create view v_expenses with (security_invoker=true) as
  select e.*, ca.name as category, ca.group_name, pm.name as payment_method
  from expenses e left join categories ca on ca.id=e.category_id
  left join payment_methods pm on pm.id=e.payment_method_id;
grant select on v_expenses to authenticated;

drop view if exists v_audit;
create view v_audit with (security_invoker=true) as
  select a.*, pf.full_name, pf.email from audit_log a left join profiles pf on pf.id=a.user_id;
grant select on v_audit to authenticated;

-- ---------- PERMISOS DE LECTURA QUE FALTABAN ----------
drop policy if exists "caja_lee_detalle_ventas" on sale_items;
create policy "caja_lee_detalle_ventas" on sale_items for select
  using (app_role()='caja' and exists (select 1 from sales s where s.id = sale_id and s.created_by = auth.uid()));
drop policy if exists "prod_lee_envases" on presentation_packaging;
create policy "prod_lee_envases" on presentation_packaging for select using (app_role()='produccion');

-- ---------- PERMISOS DE EJECUCIÓN ----------
grant execute on function confirm_purchase(date,uuid,uuid,text,text,jsonb) to authenticated;
grant execute on function confirm_sale(date,uuid,text,jsonb) to authenticated;
grant execute on function register_expense(date,uuid,uuid,numeric,text,text) to authenticated;
grant execute on function register_income(date,uuid,uuid,numeric,text) to authenticated;
grant execute on function void_expense(uuid,text) to authenticated;
grant execute on function void_income(uuid,text) to authenticated;
grant execute on function void_production(uuid,text) to authenticated;
grant execute on function close_day(date,numeric,text) to authenticated;
grant execute on function income_statement(date,date) to authenticated;

-- Fin. Si ya tenías tu usuario admin, no hace falta nada más.
