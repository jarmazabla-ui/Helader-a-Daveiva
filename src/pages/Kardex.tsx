import { useState } from 'react'
import { MOVE_LABEL, bs, exportCSV, fdt, firstOfMonth, num, today, useTable } from '../lib'
import { DateRange, Empty, Field, Page, Sel } from '../ui'

const TEXT = ['moved_at', 'item_name', 'move_type', 'concept', 'product', 'presentation']
function cell(k: string, v: any) {
  if (k === 'moved_at') return fdt(v)
  if (k === 'move_type') return MOVE_LABEL[v] || v
  if (TEXT.includes(k)) return v
  if (v == null) return ''
  if (k.startsWith('value') || k === 'balance_value' || k === 'unit_cost') return +v || k === 'balance_value' ? bs(v) : ''
  if (k === 'balance_qty') return num(v)
  return +v ? num(v) : ''
}

export default function Kardex({ me }: { me: any }) {
  const [mode, setMode] = useState<'insumos' | 'terminados'>('insumos')
  const [items] = useTable('items', { order: 'name', asc: true })
  const [fg] = useTable(me.role === 'admin' ? 'v_fg_stock' : 'v_catalog', { order: 'code', asc: true })
  const [sel, setSel] = useState(''), [a, setA] = useState(firstOfMonth()), [b, setB] = useState(today())
  const view = mode === 'insumos' ? 'v_kardex' : 'v_fg_kardex'
  const fk = mode === 'insumos' ? 'item_id' : 'pp_id'
  const [rows] = useTable(view, {
    order: 'moved_at', asc: true, limit: 3000, deps: [mode, sel, a, b],
    filter: q => { q = q.gte('moved_at', a + 'T00:00:00-04:00').lte('moved_at', b + 'T23:59:59-04:00'); return sel ? q.eq(fk, sel) : q },
  })
  const cols: [string, string][] = mode === 'insumos'
    ? [['moved_at', 'Fecha'], ['item_name', 'Insumo'], ['move_type', 'Tipo'], ['concept', 'Concepto'], ['qty_in', 'Entra'], ['qty_out', 'Sale'], ['balance_qty', 'Saldo'], ['value_in', 'Valor entra'], ['value_out', 'Valor sale'], ['balance_value', 'Valor saldo']]
    : [['moved_at', 'Fecha'], ['product', 'Sabor'], ['presentation', 'Presentación'], ['move_type', 'Tipo'], ['qty_in', 'Entra'], ['qty_out', 'Sale'], ['balance_qty', 'Saldo'], ['unit_cost', 'Costo unit.']]

  return <Page title="Kárdex" sub="Historial de cada entrada y salida, con su saldo.">
    {me.role === 'admin' && <div className="seg"><button className={mode === 'insumos' ? 'on' : ''} onClick={() => { setMode('insumos'); setSel('') }}>Insumos</button>
      <button className={mode === 'terminados' ? 'on' : ''} onClick={() => { setMode('terminados'); setSel('') }}>Helados terminados</button></div>}
    <div className="toolbar">
      <Field label={mode === 'insumos' ? 'Insumo' : 'Producto'}>{mode === 'insumos'
        ? <Sel v={sel} set={setSel} opts={items} ph="Todos" />
        : <Sel v={sel} set={setSel} opts={fg} ph="Todos" lab={(x: any) => x.product ? `${x.product} ${x.presentation}` : x.code} />}</Field>
      <DateRange a={a} b={b} setA={setA} setB={setB} /><span className="spacer" />
      <button className="btn ghost" onClick={() => exportCSV('kardex-' + mode, cols, rows)}>Exportar</button>
    </div>
    <div className="card flush"><div className="scroll"><table>
      <thead><tr>{cols.map(([k, l]) => <th key={k} className={TEXT.includes(k) ? '' : 'r'}>{l}</th>)}</tr></thead>
      <tbody>{rows.map((r: any) => <tr key={r.id}>{cols.map(([k]) => <td key={k} className={TEXT.includes(k) ? '' : 'r num'}>
        {cell(k, r[k])}
      </td>)}</tr>)}</tbody></table></div>
      {!rows.length && <Empty>Sin movimientos en el período.</Empty>}</div>
  </Page>
}
