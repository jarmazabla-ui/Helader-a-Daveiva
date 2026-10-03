import { useState } from 'react'
import Crud from '../Crud'
import { MOVE_LABEL, bs, exportCSV, fdate, fdt, firstOfMonth, today, useTable } from '../lib'
import { DateRange, Empty, Page, Stat, Status } from '../ui'

export const Proveedores = () => <Crud table="suppliers" title="Proveedores" order="name" asc
  fields={[{ k: 'name', l: 'Nombre', required: true }, { k: 'tax_id', l: 'NIT' }, { k: 'contact', l: 'Contacto / teléfono' }, { k: 'active', l: 'Activo', type: 'bool' }]} />

export const Auditoria = () => <Crud table="audit_log" view="v_audit" title="Auditoría" order="at" canEdit={false}
  sub="Registro de operaciones importantes: quién, qué y cuándo."
  fields={[{ k: 'at', l: 'Fecha', fmt: v => fdt(v) }, { k: 'full_name', l: 'Usuario', fmt: (v, r) => v || r.email }, { k: 'action', l: 'Acción', fmt: v => (v || '').replace(/_/g, ' ') },
    { k: 'table_name', l: 'Tabla' }, { k: 'detail', l: 'Detalle', fmt: v => v ? Object.entries(v).map(([k, x]) => `${k}: ${x}`).join(', ') : '' }]} />

export function CajaMov() {
  const [a, setA] = useState(firstOfMonth()), [b, setB] = useState(today())
  const [rows] = useTable('v_cash', { order: 'created_at', limit: 5000, filter: q => q.gte('move_date', a).lte('move_date', b), deps: [a, b] })
  const ok = rows.filter((r: any) => r.status === 'confirmado')
  const tin = ok.reduce((s: number, r: any) => s + +r.amount_in, 0), tout = ok.reduce((s: number, r: any) => s + +r.amount_out, 0)
  return <Page title="Libro diario de caja" sub="Todas las entradas y salidas de dinero: ventas, compras, gastos y otros ingresos."
    actions={<button className="btn ghost" onClick={() => exportCSV('libro-caja', [['move_date', 'Fecha'], ['move_type', 'Tipo'], ['description', 'Descripción'], ['category', 'Categoría'], ['payment_method', 'Pago'], ['amount_in', 'Entrada'], ['amount_out', 'Salida'], ['status', 'Estado']], rows)}>Exportar</button>}>
    <div className="toolbar"><DateRange a={a} b={b} setA={setA} setB={setB} /></div>
    <div className="stats"><Stat label="Entradas" value={bs(tin)} /><Stat label="Salidas" value={bs(tout)} /><Stat label="Neto" value={bs(tin - tout)} tone={tin - tout < 0 ? 'bad' : 'good'} /></div>
    <div className="card flush"><div className="scroll"><table>
      <thead><tr><th>Fecha</th><th>Tipo</th><th>Descripción</th><th>Pago</th><th className="r">Entrada</th><th className="r">Salida</th><th>Estado</th></tr></thead>
      <tbody>{rows.map((r: any) => <tr key={r.id} className={r.status === 'anulado' ? 'muted' : ''}><td>{fdate(r.move_date)}</td><td>{MOVE_LABEL[r.move_type] || r.move_type}</td>
        <td>{r.description}{r.category && <small className="sub"> · {r.category}</small>}</td><td>{r.payment_method}</td>
        <td className="r num">{+r.amount_in ? bs(r.amount_in) : ''}</td><td className="r num">{+r.amount_out ? bs(r.amount_out) : ''}</td><td><Status s={r.status} /></td></tr>)}</tbody>
    </table></div>{!rows.length && <Empty>Sin movimientos en el período.</Empty>}</div>
  </Page>
}
