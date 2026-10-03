-- =====================================================
-- PARTE 5 (OPCIONAL) - Datos de ejemplo para probar
-- Carga insumos, sabores, presentaciones, precios, envases y recetas.
-- NO carga stock: el stock entra por Compras o por Ajustes (inventario inicial).
-- Si ya cargaste tus propios datos, NO ejecutes este archivo.
-- =====================================================

insert into items(code,name,kind,base_unit,min_stock) values
 ('LEC','Leche entera','materia_prima','ml',20000),
 ('CRE','Crema de leche','materia_prima','ml',5000),
 ('AZU','Azúcar','materia_prima','g',10000),
 ('EST','Estabilizante','materia_prima','g',500),
 ('FRU','Pulpa de frutilla','materia_prima','g',3000),
 ('CHO','Cacao en polvo','materia_prima','g',2000),
 ('VAI','Esencia de vainilla','materia_prima','ml',200),
 ('V1L','Pote 1 litro','envase','unidad',50),
 ('V5L','Balde 5 litros','envase','unidad',10),
 ('T1L','Tapa pote 1 litro','tapa','unidad',50),
 ('T5L','Tapa balde 5 litros','tapa','unidad',10),
 ('ETQ','Etiqueta','etiqueta','unidad',100)
on conflict (code) do nothing;

insert into products(name) values ('Frutilla'),('Chocolate'),('Vainilla') on conflict (name) do nothing;
insert into presentations(name,volume_ml) values ('Pote 1 L',1000),('Balde 5 L',5000) on conflict (name) do nothing;

insert into product_presentations(code,product_id,presentation_id,sale_price)
select left(upper(p.name),3)||'-'||case when pr.volume_ml=1000 then '1L' else '5L' end, p.id, pr.id,
       case when pr.volume_ml=1000 then 35 else 150 end
from products p cross join presentations pr
where p.name in ('Frutilla','Chocolate','Vainilla') and pr.name in ('Pote 1 L','Balde 5 L')
on conflict do nothing;

insert into presentation_packaging(presentation_id,item_id,qty_per_unit)
select pr.id, i.id, 1 from presentations pr join items i on
  (pr.name='Pote 1 L' and i.code in ('V1L','T1L','ETQ')) or (pr.name='Balde 5 L' and i.code in ('V5L','T5L','ETQ'))
on conflict do nothing;

-- Recetas para 10 litros
do $$
declare p record; r uuid;
begin
  for p in select id, name from products where name in ('Frutilla','Chocolate','Vainilla') loop
    if exists (select 1 from recipes where product_id = p.id) then continue; end if;
    insert into recipes(product_id,yield_liters) values (p.id,10) returning id into r;
    insert into recipe_items(recipe_id,item_id,qty_base)
      select r, id, case code when 'LEC' then 6000 when 'CRE' then 2000 when 'AZU' then 1800 when 'EST' then 60 end
      from items where code in ('LEC','CRE','AZU','EST');
    insert into recipe_items(recipe_id,item_id,qty_base)
      select r, id, case code when 'FRU' then 1500 when 'CHO' then 600 when 'VAI' then 40 end
      from items where (p.name='Frutilla' and code='FRU') or (p.name='Chocolate' and code='CHO') or (p.name='Vainilla' and code='VAI');
  end loop;
end $$;
