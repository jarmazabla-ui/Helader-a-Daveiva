import { useState } from 'react'
import { bs, call, exportCSV, num, toast, useTable } from '../lib'
import { Field, Page, Sel } from '../ui'

export default function Inventario() {
  const [items, reloadI] = useTable('items', { order: 'name', asc: true })
  const [fg, reloadF] = useTable('v_fg_stock', { order: 'product', asc: true })
  const [i, setI] = useState(''), [mode, setMode] = useState<'in' | 'out'>('in'), [q, setQ] = useState(''), [cost, setCost] = useState(''), [r, setR] = useState('')
  const [p, setP] = useState(''), [pq, setPq] = useState(''), [pr, setPr] = useState(''), [pmode, setPmode] = useState<'in' | 'out'>('out')
  const it = items.find((x: any) => x.id === i)

  const adjItem = async () => {
    if (!i || !(+q > 0) || !r.trim()) return toast('Elija el insumo, la cantidad y el motivo', 'err')
    const ok = await call('adjust_inventory', { p_item: i, p_delta: mode === 'in' ? +q : -q, p_reason: r, p_unit_cost: mode === 'in' && cost !== '' ? +cost / +q : null })
    if (ok) { toast('Ajuste registrado'); setQ(''); setCost(''); setR(''); reloadI() }
  }
  const adjFg = async () => {
    if (!p || !(+pq > 0) || !pr.trim()) return toast('Elija el producto, la cantidad y el motivo', 'err')
    if (await call('adjust_fg', { p_pp: p, p_delta: pmode === 'in' ? +pq : -pq, p_reason: pr })) { toast('Ajuste registrado'); setPq(''); setPr(''); reloadF() }
  }
  const totI = items.reduce((s: number, x: any) => s + Math.max(+x.stock, 0) * +x.avg_cost, 0)
  const totF = fg.reduce((s: number, x: any) => s + Math.max(+x.stock, 0) * +(x.avg_cost || 0), 0)

  return <Page title="Inventario y ajustes" sub="Usa los ajustes para el inventario inicial, mermas, roturas o diferencias de conteo.">
    <div className="grid2">
      <div className="card">
        <h2>Ajustar insumo</h2>
        <div className="seg small"><button className={mode === 'in' ? 'on' : ''} onClick={() => setMode('in')}>Entrada</button><button className={mode === 'out' ? 'on' : ''} onClick={() => setMode('out')}>Salida / merma</button></div>
        <div className="form-row">
          <Field label="Insumo"><Sel v={i} set={setI} opts={items} ph="Elegir…" lab={(x: any) => `${x.name} (${x.base_unit})`} /></Field>
          <Field label={`Cantidad${it ? ' (' + it.base_unit + ')' : ''}`}><input type="number" value={q} onChange={e => setQ(e.target.value)} /></Field>
          {mode === 'in' && <Field label="Valor total (Bs)"><input type="number" placeholder={it ? 'Costo prom.: ' + num(+it.avg_cost * (+q || 0), 2) : ''} value={cost} onChange={e => setCost(e.target.value)} /></Field>}
          <Field label="Motivo" grow><input value={r} onChange={e => setR(e.target.value)} placeholder={mode === 'in' ? 'Inventario inicial' : 'Merma, vencido, conteo…'} /></Field>
        </div>
        {it && <p className="sub">Stock actual: {num(it.stock)} {it.base_unit} · costo promedio Bs {num(it.avg_cost, 6)} por {it.base_unit}</p>}
        <button className="btn" onClick={adjItem}>Registrar ajuste</button>
      </div>
      <div className="card">
        <h2>Ajustar helado terminado</h2>
        <div className="seg small"><button className={pmode === 'out' ? 'on' : ''} onClick={() => setPmode('out')}>Salida / merma</button><button className={pmode === 'in' ? 'on' : ''} onClick={() => setPmode('in')}>Entrada</button></div>
        <div className="form-row">
          <Field label="Producto"><Sel v={p} set={setP} opts={fg} ph="Elegir…" lab={(x: any) => `${x.product} ${x.presentation}`} /></Field>
          <Field label="Unidades"><input type="number" value={pq} onChange={e => setPq(e.target.value)} /></Field>
          <Field label="Motivo" grow><input value={pr} onChange={e => setPr(e.target.value)} placeholder="Derretido, muestra, conteo…" /></Field>
        </div>
        <button className="btn" onClick={adjFg}>Registrar ajuste</button>
      </div>
    </div>

    <div className="card flush"><div className="toolbar pad"><h2>Valor de insumos · {bs(totI)}</h2><span className="spacer" />
      <button className="btn ghost" onClick={() => exportCSV('inventario-insumos', [['code', 'Código'], ['name', 'Insumo'], ['base_unit', 'Unidad'], ['stock', 'Stock'], ['avg_cost', 'Costo promedio'], ['value', 'Valor']], items.map((x: any) => ({ ...x, value: (Math.max(+x.stock, 0) * +x.avg_cost).toFixed(2) })))}>Exportar</button></div>
      <div className="scroll"><table><thead><tr><th>Código</th><th>Insumo</th><th className="r">Stock</th><th className="r">Mínimo</th><th className="r">Costo prom.</th><th className="r">Valor</th></tr></thead>
        <tbody>{items.map((x: any) => <tr key={x.id} className={x.active ? '' : 'muted'}><td>{x.code}</td><td>{x.name}</td>
          <td className={'r num ' + (+x.stock <= +x.min_stock ? 'bad-t' : '')}>{num(x.stock)} {x.base_unit}</td><td className="r num">{num(x.min_stock)}</td>
          <td className="r num">{num(x.avg_cost, 6)}</td><td className="r num">{bs(Math.max(+x.stock, 0) * +x.avg_cost)}</td></tr>)}</tbody></table></div></div>

    <div className="card flush"><h2 className="pad">Valor de helados terminados · {bs(totF)}</h2>
      <div className="scroll"><table><thead><tr><th>Producto</th><th className="r">Stock</th><th className="r">Costo prom.</th><th className="r">Precio</th><th className="r">Valor al costo</th></tr></thead>
        <tbody>{fg.map((x: any) => <tr key={x.id}><td>{x.product} {x.presentation}</td><td className="r num">{num(x.stock, 0)}</td>
          <td className="r num">{bs(x.avg_cost)}</td><td className="r num">{bs(x.sale_price)}</td><td className="r num">{bs(Math.max(+x.stock, 0) * +(x.avg_cost || 0))}</td></tr>)}</tbody></table></div></div>
  </Page>
}
