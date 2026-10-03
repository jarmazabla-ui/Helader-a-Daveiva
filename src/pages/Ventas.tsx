import { useState } from 'react'
import { bs, call, exportCSV, fdate, fdt, firstOfMonth, toast, today, useTable } from '../lib'
import { DateRange, Empty, Page, Stat, Status, askReason } from '../ui'
import Ticket from '../Ticket'

export default function Ventas({ me }: { me: any }) {
  const [a, setA] = useState(me.role === 'caja' ? today() : firstOfMonth()), [b, setB] = useState(today())
  const [rows, reload] = useTable('v_sales', { order: 'created_at', filter: q => q.gte('sale_date', a).lte('sale_date', b), deps: [a, b] })
  const [open, setOpen] = useState<string | null>(null)
  const ok = rows.filter((r: any) => r.status === 'confirmado')
  const anular = async (id: string) => {
    const m = await askReason('Anular venta'); if (!m) return
    if (await call('void_sale', { p_id: id, p_reason: m })) { toast('Venta anulada; el stock fue devuelto'); reload() }
  }
  return <Page title="Ventas realizadas" sub={me.role === 'caja' ? 'Solo ves tus propias ventas.' : undefined}
    actions={<button className="btn ghost" onClick={() => exportCSV('ventas', [['number', 'N°'], ['sale_date', 'Fecha'], ['payment_method', 'Pago'], ['total', 'Total'], ['status', 'Estado'], ['seller_email', 'Usuario']], rows)}>Exportar</button>}>
    <div className="toolbar"><DateRange a={a} b={b} setA={setA} setB={setB} /></div>
    <div className="stats"><Stat label="Ventas válidas" value={ok.length} /><Stat label="Total vendido" value={bs(ok.reduce((s: number, r: any) => s + +r.total, 0))} />
      <Stat label="Anuladas" value={rows.length - ok.length} tone={rows.length - ok.length ? 'warn' : undefined} /></div>
    <div className="card flush"><div className="scroll"><table>
      <thead><tr><th>N°</th><th>Fecha y hora</th><th>Pago</th>{me.role === 'admin' && <th>Usuario</th>}<th className="r">Total</th><th>Estado</th><th /></tr></thead>
      <tbody>{rows.map((v: any) => <tr key={v.id}>
        <td>{v.number}</td><td>{fdt(v.created_at)}</td><td>{v.payment_method}</td>{me.role === 'admin' && <td>{v.seller || v.seller_email}</td>}
        <td className="r num">{bs(v.total)}</td><td><Status s={v.status} />{v.void_reason && <small className="sub"> {v.void_reason}</small>}</td>
        <td className="r nowrap"><button className="link" onClick={() => setOpen(v.id)}>Ver</button>
          {v.status === 'confirmado' && <button className="link danger" onClick={() => anular(v.id)}>Anular</button>}</td>
      </tr>)}</tbody></table></div>
      {!rows.length && <Empty>No hay ventas entre {fdate(a)} y {fdate(b)}.</Empty>}
    </div>
    {open && <Ticket saleId={open} onClose={() => setOpen(null)} />}
  </Page>
}
