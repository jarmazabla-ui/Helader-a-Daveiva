import { useEffect, useState } from 'react'
import { sb } from '../supabase'
import { METHOD_LABEL, bs, call, fdate, firstOfMonth, num, toast, today, useTable } from '../lib'
import { DateRange, Empty, Field, Modal, Page, Sel, Status, askReason } from '../ui'

export default function Produccion({ me }: { me: any }) {
  const [prods] = useTable('products', { filter: q => q.eq('active', true), order: 'name', asc: true })
  const [cat] = useTable('v_fg_stock', { order: 'volume_ml', asc: true })
  const [items] = useTable('items')
  const [settings] = useTable('app_settings')
  const [a, setA] = useState(firstOfMonth()), [b, setB] = useState(today())
  const [orders, reload] = useTable('production_orders', { order: 'created_at', filter: q => q.gte('order_date', a).lte('order_date', b), deps: [a, b] })
  const [prod, setProd] = useState(''), [method, setMethod] = useState(''), [date, setDate] = useState(today()), [notes, setNotes] = useState('')
  const [out, setOut] = useState<Record<string, string>>({}), [real, setReal] = useState<Record<string, string>>({})
  const [pv, setPv] = useState<any>(null), [busy, setBusy] = useState(false), [detail, setDetail] = useState<any>(null)

  useEffect(() => { if (!method && settings[0]) setMethod(settings[0].default_costing) }, [settings, method])
  const mine = cat.filter((x: any) => x.product_id === prod && x.active)
  const outputs = mine.filter((x: any) => +out[x.id] > 0).map((x: any) => ({ pp_id: x.id, units: +out[x.id] }))
  const key = JSON.stringify([prod, outputs, method])

  // Vista previa de insumos (se recalcula al cambiar producto, unidades o método)
  useEffect(() => {
    if (!prod || !outputs.length) { setPv(null); return }
    const t = setTimeout(async () => {
      const { data, error } = await sb.rpc('preview_production', { p_product: prod, p_outputs: outputs, p_method: method })
      setPv(error ? { error: error.message } : data)
    }, 350)
    return () => clearTimeout(t)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key])

  const go = async () => {
    if (!prod || !outputs.length) return toast('Elija el sabor e indique las unidades obtenidas', 'err')
    const overrides = Object.entries(real).filter(([, v]) => v !== '').map(([item_id, v]) => ({ item_id, qty_base: +v }))
    setBusy(true)
    const id = await call('confirm_production', { p_date: date, p_product: prod, p_method: method, p_outputs: outputs, p_overrides: overrides, p_notes: notes || null })
    setBusy(false)
    if (id) { setOut({}); setReal({}); setNotes(''); reload(); toast('Producción registrada: los helados ya están en stock') }
  }
  const anular = async (id: string) => {
    const m = await askReason('Anular orden de producción'); if (!m) return
    if (await call('void_production', { p_id: id, p_reason: m })) { toast('Orden anulada; los insumos volvieron al stock'); reload() }
  }
  const open = async (o: any) => {
    const [c, s] = await Promise.all([
      sb.from('production_consumptions').select('*').eq('order_id', o.id),
      sb.from('production_outputs').select('*').eq('order_id', o.id)])
    setDetail({ o, cons: c.data || [], outs: s.data || [] })
  }
  const itemName = (id: string) => items.find((x: any) => x.id === id)
  const ppName = (id: string) => { const x = cat.find((c: any) => c.id === id); return x ? `${x.product} ${x.presentation}` : '—' }
  const prodName = (id: string) => prods.find((p: any) => p.id === id)?.name || cat.find((c: any) => c.product_id === id)?.product || '—'
  const missing = pv?.items?.some((x: any) => !x.packaging ? (real[x.item_id] !== undefined && real[x.item_id] !== '' ? +real[x.item_id] > x.stock : !x.enough) : !x.enough)

  return <Page title="Producción" sub="Registra cuántos potes o baldes salieron; el sistema descuenta la receta y los envases.">
    <div className="card">
      <div className="form-row">
        <Field label="Fecha"><input type="date" value={date} onChange={e => setDate(e.target.value)} /></Field>
        <Field label="Sabor"><Sel v={prod} set={(v: any) => { setProd(v); setOut({}); setReal({}) }} opts={prods} ph="Elegir…" /></Field>
        <Field label="Método de costeo"><select value={method} onChange={e => setMethod(e.target.value)}>
          {Object.entries(METHOD_LABEL).map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></Field>
      </div>
      {prod && <>
        <h3>Unidades obtenidas</h3>
        {mine.length ? <div className="form-row">{mine.map((x: any) => <Field key={x.id} label={`${x.presentation} (${num(x.volume_ml, 0)} ml)`}>
          <input type="number" min="0" value={out[x.id] || ''} onChange={e => setOut({ ...out, [x.id]: e.target.value })} placeholder="0" /></Field>)}</div>
          : <p className="sub">Este sabor no tiene presentaciones con precio. Créalas en «Productos y precios».</p>}
      </>}
      {pv?.error && <div className="notice bad">{pv.error}</div>}
      {pv?.items && <>
        <h3>Insumos a descontar · {num(pv.liters, 2)} L <small className="sub">(receta rinde {num(pv.yield_liters, 2)} L)</small></h3>
        <div className="scroll"><table className="compact"><thead><tr><th>Insumo</th><th className="r">Según receta</th><th className="r">Consumo real</th><th className="r">Stock</th>{me.role === 'admin' && <th className="r">Costo estimado</th>}</tr></thead>
          <tbody>{pv.items.map((x: any) => <tr key={x.item_id + x.packaging}>
            <td>{x.name}{x.packaging && <small className="sub"> (envase)</small>}</td>
            <td className="r num">{num(x.qty)} {x.unit}</td>
            <td className="r">{x.packaging ? <span className="sub">—</span> :
              <input className="narrow" type="number" placeholder={num(x.qty)} value={real[x.item_id] ?? ''} onChange={e => setReal({ ...real, [x.item_id]: e.target.value })} />}</td>
            <td className={'r num ' + (x.enough ? '' : 'bad-t')}>{num(x.stock)} {x.unit}</td>
            {me.role === 'admin' && <td className="r num">{bs(x.cost)}</td>}
          </tr>)}</tbody></table></div>
        <p className="sub">Deja «Consumo real» vacío si se usó exactamente lo de la receta.</p>
        {missing && <div className="notice bad">Hay insumos sin stock suficiente. Registra una compra o un ajuste antes de producir.</div>}
      </>}
      {prod && <div className="form-row space">
        <Field label="Observación" grow><input value={notes} onChange={e => setNotes(e.target.value)} /></Field>
        <button className="btn" disabled={busy || !outputs.length} onClick={go}>{busy ? 'Registrando…' : 'Confirmar producción'}</button>
      </div>}
    </div>

    <div className="toolbar"><DateRange a={a} b={b} setA={setA} setB={setB} /></div>
    <div className="card flush"><div className="scroll"><table>
      <thead><tr><th>Orden</th><th>Fecha</th><th>Sabor</th><th className="r">Litros</th><th className="r">Costo</th><th>Método</th><th>Estado</th><th /></tr></thead>
      <tbody>{orders.map((o: any) => <tr key={o.id}><td>{o.number}</td><td>{fdate(o.order_date)}</td><td>{prodName(o.product_id)}</td>
        <td className="r num">{num(o.liters_obtained, 2)}</td><td className="r num">{bs(o.total_cost)}</td><td>{METHOD_LABEL[o.costing_method]}</td><td><Status s={o.status} /></td>
        <td className="r nowrap"><button className="link" onClick={() => open(o)}>Ver</button>{o.status === 'confirmado' && <button className="link danger" onClick={() => anular(o.id)}>Anular</button>}</td></tr>)}</tbody>
    </table></div>{!orders.length && <Empty>No hay órdenes en el período.</Empty>}</div>

    {detail && <Modal title={`Orden ${detail.o.number}`} onClose={() => setDetail(null)} wide>
      <p className="sub">{fdate(detail.o.order_date)} · {prodName(detail.o.product_id)} · {num(detail.o.liters_obtained, 2)} L · {METHOD_LABEL[detail.o.costing_method]}{detail.o.notes ? ' · ' + detail.o.notes : ''}</p>
      {detail.o.void_reason && <div className="notice warn">Anulada: {detail.o.void_reason}</div>}
      <h3>Salida</h3>
      <table className="compact"><thead><tr><th>Producto</th><th className="r">Unidades</th><th className="r">Costo unitario</th></tr></thead>
        <tbody>{detail.outs.map((x: any) => <tr key={x.id}><td>{ppName(x.pp_id)}</td><td className="r num">{num(x.units, 0)}</td><td className="r num">{bs(x.unit_cost)}</td></tr>)}</tbody></table>
      <h3>Insumos consumidos</h3>
      <table className="compact"><thead><tr><th>Insumo</th><th className="r">Teórico</th><th className="r">Real</th><th className="r">Costo</th></tr></thead>
        <tbody>{detail.cons.map((x: any) => { const it = itemName(x.item_id); return <tr key={x.id}><td>{it?.name}{x.is_packaging && <small className="sub"> (envase)</small>}</td>
          <td className="r num">{num(x.qty_theoretical)} {it?.base_unit}</td><td className={'r num ' + (+x.qty_real > +x.qty_theoretical ? 'bad-t' : '')}>{num(x.qty_real)} {it?.base_unit}</td><td className="r num">{bs(x.cost)}</td></tr> })}</tbody></table>
      <p className="total-inline">Costo total <strong>{bs(detail.o.total_cost)}</strong></p>
    </Modal>}
  </Page>
}
