import { useEffect, useState } from 'react'
import { sb } from './supabase'
import { bs, fdt, money, num } from './lib'
import { Modal } from './ui'

/** Comprobante de venta imprimible (impresora térmica de 58/80 mm o A4). */
export default function Ticket({ saleId, onClose, paid }: { saleId: string; onClose: () => void; paid?: number }) {
  const [d, setD] = useState<any>(null)
  useEffect(() => {
    (async () => {
      const [s, it, st, cfg] = await Promise.all([
        sb.from('v_sales').select('*').eq('id', saleId).single(),
        sb.from('sale_items').select('*').eq('sale_id', saleId),
        sb.from('v_fg_stock').select('id,product,presentation'),
        sb.from('app_settings').select('*').single(),
      ])
      const names = Object.fromEntries((st.data || []).map((x: any) => [x.id, `${x.product} ${x.presentation}`]))
      setD({ s: s.data, items: (it.data || []).map((x: any) => ({ ...x, name: names[x.pp_id] || 'Producto' })), cfg: cfg.data || {} })
    })()
  }, [saleId])
  const print = () => { document.body.classList.add('printing'); window.print(); document.body.classList.remove('printing') }
  return <Modal title="Comprobante de venta" onClose={onClose}>
    {!d ? <p>Cargando…</p> : <>
      <div className="ticket">
        <h3>{d.cfg.business_name || 'Heladería'}</h3>
        {d.cfg.business_nit && <p>NIT {d.cfg.business_nit}</p>}
        {d.cfg.business_address && <p>{d.cfg.business_address}</p>}
        <hr />
        <p><b>{d.s?.number}</b> · {fdt(d.s?.created_at)}</p>
        {d.s?.status === 'anulado' && <p><b>*** VENTA ANULADA ***</b></p>}
        <table><tbody>{d.items.map((x: any) => <tr key={x.id}><td>{num(x.qty, 0)} × {x.name}<br /><small>a {money(x.unit_price)}</small></td><td className="r">{money(x.amount)}</td></tr>)}</tbody></table>
        <hr />
        <p className="tot"><span>Total</span><span>{bs(d.s?.total)}</span></p>
        <p><span>Pago: {d.s?.payment_method}</span></p>
        {paid != null && paid > 0 && <><p className="row-b"><span>Recibido</span><span>{bs(paid)}</span></p>
          <p className="row-b"><span>Cambio</span><span>{bs(paid - (+d.s?.total || 0))}</span></p></>}
        {d.s?.notes && <p>{d.s.notes}</p>}
        <hr /><p>{d.cfg.ticket_footer}</p>
      </div>
      <div className="actions"><button className="btn ghost" onClick={onClose}>Cerrar</button><button className="btn" onClick={print}>Imprimir</button></div>
    </>}
  </Modal>
}
