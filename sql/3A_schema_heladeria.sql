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
