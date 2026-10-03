import Crud from '../Crud'
import { bs, num } from '../lib'

export default function Insumos() {
  return <Crud table="items" title="Insumos" order="name" asc
    sub="Materia prima, envases, tapas y etiquetas. El stock entra por Compras o por Ajustes (inventario inicial)."
    fields={[
      { k: 'code', l: 'Código', required: true },
      { k: 'name', l: 'Nombre', required: true },
      { k: 'kind', l: 'Tipo', required: true, opts: [['materia_prima', 'Materia prima'], ['envase', 'Envase'], ['tapa', 'Tapa'], ['etiqueta', 'Etiqueta'], ['otro', 'Otro']] },
      { k: 'base_unit', l: 'Unidad base', required: true, opts: [['g', 'Gramos (g)'], ['ml', 'Mililitros (ml)'], ['unidad', 'Unidades']], hint: 'Kilos y litros se convierten al comprar.' },
      { k: 'min_stock', l: 'Stock mínimo', type: 'number', fmt: (v, r) => `${num(v)} ${r.base_unit}` },
      { k: 'stock', l: 'Stock', type: 'number', form: false, fmt: (v, r) => <span className={+v <= +r.min_stock ? 'bad-t' : ''}>{num(v)} {r.base_unit}</span> },
      { k: 'avg_cost', l: 'Costo prom.', type: 'number', form: false, fmt: v => num(v, 6) },
      { k: 'last_cost', l: 'Último costo', type: 'number', form: false, fmt: v => num(v, 6) },
      { k: 'value', l: 'Valor', type: 'number', form: false, fmt: (_, r) => bs(Math.max(+r.stock, 0) * +r.avg_cost) },
      { k: 'active', l: 'Activo', type: 'bool' }]} />
}
