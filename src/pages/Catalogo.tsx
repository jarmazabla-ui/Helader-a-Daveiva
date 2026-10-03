import { useState } from 'react'
import Crud from '../Crud'
import { bs, num } from '../lib'
import { Page } from '../ui'

const TABS: [string, string][] = [['precios', 'Precios de venta'], ['sabores', 'Sabores'], ['presentaciones', 'Presentaciones'], ['envases', 'Envases por presentación']]

export default function Catalogo() {
  const [t, setT] = useState('precios')
  return <Page title="Productos y precios" sub="Un producto vendible es un sabor en una presentación (ej.: Frutilla – Pote 1 L).">
    <div className="seg">{TABS.map(([k, l]) => <button key={k} className={t === k ? 'on' : ''} onClick={() => setT(k)}>{l}</button>)}</div>
    {t === 'sabores' && <Crud embedded key="s" table="products" title="Sabores" order="name" asc
      fields={[{ k: 'name', l: 'Nombre', required: true }, { k: 'active', l: 'Activo', type: 'bool' }]} />}
    {t === 'presentaciones' && <Crud embedded key="p" table="presentations" title="Presentaciones" order="volume_ml" asc
      fields={[{ k: 'name', l: 'Nombre', required: true }, { k: 'volume_ml', l: 'Volumen (ml)', type: 'number', required: true, hint: '1 litro = 1000 ml' }, { k: 'active', l: 'Activo', type: 'bool' }]} />}
    {t === 'precios' && <Crud embedded key="pp" table="product_presentations" title="Precios de venta" order="code" asc
      sub="El stock y el costo se actualizan solos con la producción y las ventas."
      fields={[
        { k: 'code', l: 'Código', required: true },
        { k: 'product_id', l: 'Sabor', ref: { table: 'products', label: 'name' }, required: true },
        { k: 'presentation_id', l: 'Presentación', ref: { table: 'presentations', label: 'name' }, required: true },
        { k: 'sale_price', l: 'Precio (Bs)', type: 'number', required: true, fmt: v => bs(v) },
        { k: 'stock', l: 'Stock', type: 'number', form: false, fmt: v => num(v, 0) },
        { k: 'avg_cost', l: 'Costo prom.', type: 'number', form: false, fmt: v => bs(v) },
        { k: 'active', l: 'A la venta', type: 'bool' }]} />}
    {t === 'envases' && <Crud embedded key="e" table="presentation_packaging" title="Envases por presentación"
      sub="Qué envase, tapa y etiqueta lleva cada unidad producida. Se descuentan solos al producir."
      fields={[
        { k: 'presentation_id', l: 'Presentación', ref: { table: 'presentations', label: 'name' }, required: true },
        { k: 'item_id', l: 'Insumo', ref: { table: 'items', label: (o: any) => `${o.name} (${o.base_unit})` }, required: true },
        { k: 'qty_per_unit', l: 'Cantidad por unidad', type: 'number', required: true }]} />}
  </Page>
}
