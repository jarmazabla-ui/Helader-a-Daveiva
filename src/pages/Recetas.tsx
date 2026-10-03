import { useEffect, useState } from 'react'
import { sb } from '../supabase'
import { bs, friendly, num, toast, useTable } from '../lib'
import { Empty, Field, Page, Sel, confirmBox } from '../ui'

export default function Recetas() {
  const [prods] = useTable('products', { order: 'name', asc: true })
  const [items] = useTable('items', { order: 'name', asc: true })
  const [recipes, reloadR] = useTable('recipes')
  const [prod, setProd] = useState('')
  const rc = recipes.find((r: any) => r.product_id === prod && r.active) || recipes.find((r: any) => r.product_id === prod)
  const [lines, setLines] = useState<any[]>([])
  const [yieldL, setYieldL] = useState(''), [newI, setNewI] = useState(''), [newQ, setNewQ] = useState('')

  const loadLines = async () => {
    if (!rc) { setLines([]); return }
    const { data } = await sb.from('recipe_items').select('*').eq('recipe_id', rc.id)
    setLines(data || [])
  }
  useEffect(() => { loadLines(); setYieldL(rc ? String(rc.yield_liters) : '10') /* eslint-disable-next-line */ }, [rc?.id, prod])

  const it = (id: string) => items.find((x: any) => x.id === id)
  const costBatch = lines.reduce((s, l) => s + +l.qty_base * +(it(l.item_id)?.avg_cost || 0), 0)
  const err = (e: any) => { if (e) { toast(friendly(e.message), 'err'); return true } return false }

  const createRecipe = async () => {
    if (!(+yieldL > 0)) return toast('Indique cuántos litros rinde la receta', 'err')
    if (err((await sb.from('recipes').insert({ product_id: prod, yield_liters: +yieldL })).error)) return
    toast('Receta creada. Ahora agrega los ingredientes.'); reloadR()
  }
  const saveYield = async () => {
    if (!(+yieldL > 0)) return toast('El rendimiento debe ser mayor a cero', 'err')
    if (!err((await sb.from('recipes').update({ yield_liters: +yieldL }).eq('id', rc.id)).error)) { toast('Rendimiento guardado'); reloadR() }
  }
  const addLine = async () => {
    if (!newI || !(+newQ > 0)) return toast('Elija el insumo y la cantidad', 'err')
    if (lines.some(l => l.item_id === newI)) return toast('Ese insumo ya está en la receta; edita su cantidad', 'err')
    if (!err((await sb.from('recipe_items').insert({ recipe_id: rc.id, item_id: newI, qty_base: +newQ })).error)) { setNewI(''); setNewQ(''); loadLines() }
  }
  const updLine = async (l: any, q: string) => {
    if (!(+q > 0) || +q === +l.qty_base) return
    if (!err((await sb.from('recipe_items').update({ qty_base: +q }).eq('id', l.id)).error)) { toast('Cantidad actualizada'); loadLines() }
  }
  const delLine = async (l: any) => {
    if (!(await confirmBox('¿Quitar este ingrediente de la receta?', 'Quitar'))) return
    if (!err((await sb.from('recipe_items').delete().eq('id', l.id)).error)) loadLines()
  }

  return <Page title="Recetas" sub="Cantidades en la unidad base del insumo (g, ml o unidades) para el rendimiento indicado.">
    <div className="card"><div className="form-row">
      <Field label="Sabor"><Sel v={prod} set={setProd} opts={prods} ph="Elegir sabor…" /></Field>
      {prod && <Field label="La receta rinde (litros)"><input type="number" value={yieldL} onChange={e => setYieldL(e.target.value)} /></Field>}
      {prod && (rc ? <button className="btn ghost" onClick={saveYield}>Guardar rendimiento</button> : <button className="btn" onClick={createRecipe}>Crear receta</button>)}
    </div></div>

    {!prod && <Empty>Elige un sabor para ver o crear su receta.</Empty>}
    {rc && <div className="card">
      <h2>Ingredientes</h2>
      <table><thead><tr><th>Insumo</th><th className="r">Cantidad</th><th className="r">Costo actual</th><th /></tr></thead>
        <tbody>{lines.map(l => { const x = it(l.item_id); return <tr key={l.id}><td>{x?.name}</td>
          <td className="r"><input className="narrow" type="number" defaultValue={l.qty_base} onBlur={e => updLine(l, e.target.value)} /> {x?.base_unit}</td>
          <td className="r num">{bs(+l.qty_base * +(x?.avg_cost || 0))}</td>
          <td className="r"><button className="link danger" onClick={() => delLine(l)}>Quitar</button></td></tr> })}
          <tr className="add-row"><td><Sel v={newI} set={setNewI} opts={items.filter((x: any) => x.active && x.kind !== 'envase' && x.kind !== 'tapa' && x.kind !== 'etiqueta')} ph="Agregar insumo…" lab={(x: any) => `${x.name} (${x.base_unit})`} /></td>
            <td className="r"><input className="narrow" type="number" placeholder="Cantidad" value={newQ} onChange={e => setNewQ(e.target.value)} onKeyDown={e => e.key === 'Enter' && addLine()} /> {it(newI)?.base_unit}</td>
            <td /><td className="r"><button className="btn" onClick={addLine}>Agregar</button></td></tr>
        </tbody></table>
      <div className="stats top-gap">
        <div className="stat"><span>Costo del lote ({num(rc.yield_liters, 2)} L)</span><strong>{bs(costBatch)}</strong></div>
        <div className="stat"><span>Costo por litro (sin envase)</span><strong>{bs(costBatch / (+rc.yield_liters || 1))}</strong></div>
      </div>
      <p className="sub">Los envases, tapas y etiquetas se configuran por presentación en «Productos y precios».</p>
    </div>}
  </Page>
}
