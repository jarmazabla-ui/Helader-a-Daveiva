import { useState } from 'react'
import { sb } from '../supabase'
import { bs, call, exportCSV, fdate, firstOfMonth, money, num, toast, today, useTable } from '../lib'
import { DateRange, Empty, Field, Modal, Page, Sel, Status, askReason } from '../ui'

// Unidades de compra que se convierten a la unidad base del insumo
const BUY_UNITS: Record<string, [string, number][]> = {
  g: [['g', 1], ['kg', 1000], ['qq (46 kg)', 46000]],
  ml: [['ml', 1], ['litro', 1000]],
  unidad: [['unidad', 1], ['docena', 12], ['ciento', 100]],
}
type Line = { item: string; qty: string; unit: number; total: string }
const blank: Line = { item: '', qty: '', unit: 1, total: '' }

export default function Compras() {
  const [sup] = useTable('suppliers', { filter: q => q.eq('active', true), order: 'name', asc: true })
  const [pm] = useTable('payment_methods', { filter: q => q.eq('active', true) })
  const [items] = useTable('items', { order: 'name', asc: true })
  const [a, setA] = useState(firstOfMonth()), [b, setB] = useState(today())
  const [list, reload] = useTable('v_purchases', { order: 'created_at', filter: q => q.gte('purchase_date', a).lte('purchase_date', b), deps: [a, b] })
  const [f, setF] = useState({ date: today(), supplier: '', pay: '', doc: '', notes: '' })
  const [rows, setRows] = useState<Line[]>([{ ...blank }])
  const [busy, setBusy] = useState(false), [detail, setDetail] = useState<any>(null)

  const itemOf = (id: string) => items.find((x: any) => x.id === id)
  const set = (i: number, p: Partial<Line>) => setRows(rows.map((r, j) => j === i ? { ...r, ...p } : r))
  const valid = rows.filter(r => r.item && +r.qty > 0 && r.total !== '' && +r.total >= 0)
  const total = valid.reduce((s, r) => s + +r.total, 0)

  const save = async () => {
    if (!f.pay) return toast('Elija la forma de pago', 'err')
    if (!valid.length) return toast('Agregue al menos un insumo con cantidad y costo', 'err')
    setBusy(true)
    const its = valid.map(r => { const q = +r.qty * r.unit; return { item_id: r.item, qty_base: q, unit_cost_base: +r.total / q } })
    const id = await call('confirm_purchase', { p_date: f.date, p_supplier: f.supplier || null, p_payment: f.pay, p_document: f.doc, p_notes: f.notes, p_items: its })
    setBusy(false)
    if (id) { setRows([{ ...blank }]); setF({ ...f, doc: '', notes: '' }); reload(); toast('Compra registrada; el stock fue actualizado') }
  }
  const anular = async (id: string) => {
    const m = await askReason('Anular compra'); if (!m) return
    if (await call('void_purchase', { p_id: id, p_reason: m })) { toast('Compra anulada'); reload() }
  }
  const open = async (p: any) => {
    const { data } = await sb.from('purchase_items').select('*').eq('purchase_id', p.id)
    setDetail({ p, items: data || [] })
  }

  return <Page title="Compras de insumos" sub="Cada compra suma stock y recalcula el costo promedio del insumo.">
    <div className="card">
      <div className="form-row">
        <Field label="Fecha"><input type="date" value={f.date} onChange={e => setF({ ...f, date: e.target.value })} /></Field>
        <Field label="Proveedor"><Sel v={f.supplier} set={(v: any) => setF({ ...f, supplier: v })} opts={sup} ph="Sin proveedor" /></Field>
        <Field label="Forma de pago"><Sel v={f.pay} set={(v: any) => setF({ ...f, pay: v })} opts={pm} ph="Elegir…" /></Field>
        <Field label="Factura / recibo"><input value={f.doc} onChange={e => setF({ ...f, doc: e.target.value })} /></Field>
        <Field label="Nota" grow><input value={f.notes} onChange={e => setF({ ...f, notes: e.target.value })} /></Field>
      </div>
      <table className="lines-table"><thead><tr><th>Insumo</th><th>Cantidad</th><th>Unidad</th><th className="r">Costo total (Bs)</th><th className="r">Costo por unidad base</th><th /></tr></thead>
        <tbody>{rows.map((r, i) => {
          const it = itemOf(r.item), units = BUY_UNITS[it?.base_unit || 'unidad']
          const qb = +r.qty * r.unit
          return <tr key={i}>
            <td><Sel v={r.item} set={(v: any) => set(i, { item: v, unit: 1 })} opts={items.filter((x: any) => x.active || x.id === r.item)} ph="Elegir insumo…" lab={(x: any) => `${x.name} (${x.base_unit})`} /></td>
            <td><input type="number" value={r.qty} onChange={e => set(i, { qty: e.target.value })} /></td>
            <td><select value={r.unit} onChange={e => set(i, { unit: +e.target.value })}>{units.map(([l, k]) => <option key={l} value={k}>{l}</option>)}</select></td>
            <td className="r"><input type="number" value={r.total} onChange={e => set(i, { total: e.target.value })} /></td>
            <td className="r num sub">{qb > 0 && r.total !== '' ? `Bs ${num(+r.total / qb, 6)} / ${it?.base_unit || ''}` : ''}</td>
            <td>{rows.length > 1 && <button className="link danger" onClick={() => setRows(rows.filter((_, j) => j !== i))}>Quitar</button>}</td>
          </tr>
        })}</tbody></table>
      <div className="form-row space">
        <button className="btn ghost" onClick={() => setRows([...rows, { ...blank }])}>Agregar otro insumo</button>
        <div className="total-inline">Total <strong>{bs(total)}</strong></div>
        <button className="btn" disabled={busy} onClick={save}>{busy ? 'Guardando…' : 'Confirmar compra'}</button>
      </div>
    </div>

    <div className="toolbar"><DateRange a={a} b={b} setA={setA} setB={setB} /><span className="spacer" />
      <button className="btn ghost" onClick={() => exportCSV('compras', [['number', 'N°'], ['purchase_date', 'Fecha'], ['supplier', 'Proveedor'], ['document', 'Documento'], ['payment_method', 'Pago'], ['total', 'Total'], ['status', 'Estado']], list)}>Exportar</button></div>
    <div className="card flush"><div className="scroll"><table>
      <thead><tr><th>N°</th><th>Fecha</th><th>Proveedor</th><th>Documento</th><th>Pago</th><th className="r">Total</th><th>Estado</th><th /></tr></thead>
      <tbody>{list.map((p: any) => <tr key={p.id}><td>{p.number}</td><td>{fdate(p.purchase_date)}</td><td>{p.supplier}</td><td>{p.document}</td><td>{p.payment_method}</td>
        <td className="r num">{bs(p.total)}</td><td><Status s={p.status} /></td>
        <td className="r nowrap"><button className="link" onClick={() => open(p)}>Ver</button>{p.status === 'confirmado' && <button className="link danger" onClick={() => anular(p.id)}>Anular</button>}</td></tr>)}</tbody>
    </table></div>{!list.length && <Empty>No hay compras en el período.</Empty>}</div>

    {detail && <Modal title={`Compra ${detail.p.number}`} onClose={() => setDetail(null)} wide>
      <p className="sub">{fdate(detail.p.purchase_date)} · {detail.p.supplier || 'Sin proveedor'} · {detail.p.payment_method}{detail.p.notes ? ' · ' + detail.p.notes : ''}</p>
      {detail.p.void_reason && <div className="notice warn">Anulada: {detail.p.void_reason}</div>}
      <table><thead><tr><th>Insumo</th><th className="r">Cantidad</th><th className="r">Costo unitario</th><th className="r">Importe</th></tr></thead>
        <tbody>{detail.items.map((x: any) => { const it = itemOf(x.item_id); return <tr key={x.id}><td>{it?.name || '—'}</td>
          <td className="r num">{num(x.qty_base)} {it?.base_unit}</td><td className="r num">{num(x.unit_cost_base, 6)}</td><td className="r num">{money(x.amount)}</td></tr> })}</tbody></table>
      <p className="total-inline">Total <strong>{bs(detail.p.total)}</strong></p>
    </Modal>}
  </Page>
}
