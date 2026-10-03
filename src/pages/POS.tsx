import { useMemo, useState } from 'react'
import { bs, call, flavorColor, num, toast, today, useTable } from '../lib'
import { Empty, Page } from '../ui'
import Ticket from '../Ticket'

export default function POS() {
  const [prods, reload] = useTable('v_pos_products', { order: 'product', asc: true })
  const [pm] = useTable('payment_methods', { filter: q => q.eq('active', true), order: 'is_cash' })
  const [cart, setCart] = useState<Record<string, number>>({})
  const [pay, setPay] = useState(''), [q, setQ] = useState(''), [paid, setPaid] = useState(''), [notes, setNotes] = useState('')
  const [busy, setBusy] = useState(false), [ticket, setTicket] = useState<{ id: string; paid?: number } | null>(null)

  const byId = useMemo(() => Object.fromEntries(prods.map((p: any) => [p.id, p])), [prods])
  const lines = Object.entries(cart).filter(([, n]) => n > 0).map(([id, n]) => ({ p: byId[id], n })).filter(l => l.p)
  const total = lines.reduce((s, l) => s + l.n * l.p.sale_price, 0)
  const method = pm.find((m: any) => m.id === pay)
  const add = (id: string, d: number) => setCart(c => ({ ...c, [id]: Math.max(0, (c[id] || 0) + d) }))
  const shown = prods.filter((p: any) => (p.product + ' ' + p.presentation + ' ' + p.code).toLowerCase().includes(q.toLowerCase()))

  const sale = async () => {
    if (!lines.length) return toast('Agregue al menos un producto', 'err')
    if (!pay) return toast('Elija la forma de pago', 'err')
    if (method?.is_cash && paid && +paid < total) return toast('El monto recibido es menor al total', 'err')
    setBusy(true)
    const id = await call('confirm_sale', { p_date: today(), p_payment: pay, p_notes: notes || null, p_items: lines.map(l => ({ pp_id: l.p.id, qty: l.n })) })
    setBusy(false)
    if (id) {
      setTicket({ id, paid: method?.is_cash && paid ? +paid : undefined })
      setCart({}); setPaid(''); setNotes(''); setPay(''); reload(); toast('Venta registrada')
    }
  }

  return <Page title="Caja" sub="Toca un helado para agregarlo a la venta.">
    <div className="pos">
      <div>
        <input className="search big" placeholder="Buscar sabor, presentación o código…" value={q} onChange={e => setQ(e.target.value)} />
        <div className="tiles">
          {shown.map((p: any) => {
            const left = p.stock - (cart[p.id] || 0), [h, sa, l] = flavorColor(p.product)
            return <button key={p.id} className={'tile' + (left <= 0 ? ' out' : '')} style={{ ['--h' as any]: h, ['--s' as any]: sa + '%', ['--l' as any]: l + '%' }}
              onClick={() => add(p.id, 1)} aria-label={`Agregar ${p.product} ${p.presentation}`}>
              <span className="scoop" aria-hidden />
              <b>{p.product}</b><span>{p.presentation}</span>
              <span className="tile-foot"><strong>{bs(p.sale_price)}</strong><small>{num(left, 0)} disp.</small></span>
              {cart[p.id] > 0 && <em className="count">{cart[p.id]}</em>}
            </button>
          })}
        </div>
        {!shown.length && <Empty>{prods.length ? 'Ningún producto coincide con la búsqueda.' : 'No hay productos a la venta. El administrador debe cargar sabores, presentaciones y precios.'}</Empty>}
      </div>

      <aside className="cart card" id="cart">
        <h2>Venta actual</h2>
        {!lines.length ? <p className="sub">Sin productos todavía.</p> :
          <ul className="lines">{lines.map(l => <li key={l.p.id}>
            <div><b>{l.p.product}</b> <span className="sub">{l.p.presentation}</span><br /><small>{bs(l.p.sale_price)} c/u</small></div>
            <div className="qty">
              <button onClick={() => add(l.p.id, -1)} aria-label="Quitar uno">−</button>
              <input type="number" min="0" value={l.n} onChange={e => setCart({ ...cart, [l.p.id]: Math.max(0, +e.target.value) })} />
              <button onClick={() => add(l.p.id, 1)} aria-label="Agregar uno">+</button>
            </div>
            <div className="r num">{bs(l.n * l.p.sale_price)}{l.n > l.p.stock && <small className="bad-t"><br />Stock: {num(l.p.stock, 0)}</small>}</div>
          </li>)}</ul>}
        <div className="total"><span>Total</span><strong>{bs(total)}</strong></div>
        <div className="paygrid">{pm.map((m: any) => <button key={m.id} className={'chip' + (pay === m.id ? ' on' : '')} onClick={() => setPay(m.id)}>{m.name}</button>)}</div>
        {method?.is_cash && <label className="field"><span>Recibido (para calcular el cambio)</span>
          <input type="number" value={paid} onChange={e => setPaid(e.target.value)} placeholder="0.00" /></label>}
        {method?.is_cash && +paid > 0 && <p className="change">Cambio: <b>{bs(+paid - total)}</b></p>}
        <label className="field"><span>Nota (opcional)</span><input value={notes} onChange={e => setNotes(e.target.value)} /></label>
        <div className="actions">
          {lines.length > 0 && <button className="btn ghost" onClick={() => setCart({})}>Vaciar</button>}
          <button className="btn big" disabled={busy || !lines.length} onClick={sale}>{busy ? 'Registrando…' : 'Cobrar ' + bs(total)}</button>
        </div>
      </aside>
    </div>
    {lines.length > 0 && <button className="cartbar" onClick={() => document.getElementById('cart')?.scrollIntoView({ behavior: 'smooth' })}>
      <span>{lines.reduce((s, l) => s + l.n, 0)} producto(s)</span><strong>{bs(total)}</strong><span>Ir a cobrar</span></button>}
    {ticket && <Ticket saleId={ticket.id} paid={ticket.paid} onClose={() => setTicket(null)} />}
  </Page>
}
