import { useState } from 'react'
import { bs, call, fdate, toast, today, useRpc, useTable } from '../lib'
import { Empty, Field, Page, Stat, Status, askReason } from '../ui'

export default function Cierre({ me }: { me: any }) {
  const isAdmin = me.role === 'admin'
  const [d, setD] = useState(today()), [c, setC] = useState(''), [n, setN] = useState('')
  const [s, reloadS] = useRpc<any>('day_summary', { p_date: d }, [d])
  const [list, reload] = useTable('cash_closures', { order: 'closure_date', limit: 60 })
  const diff = c === '' || !s ? null : +c - +s.theoretical

  const close = async () => {
    if (c === '') return toast('Ingrese el efectivo contado', 'err')
    if (await call('close_day', { p_date: d, p_counted_cash: +c, p_notes: n || null })) { toast('Día cerrado'); setC(''); setN(''); reload(); reloadS() }
  }
  const reopen = async (date: string) => {
    const m = await askReason('Reabrir el día ' + fdate(date), 'Reabrir'); if (!m) return
    if (await call('reopen_day', { p_date: date, p_reason: m })) { toast('Día reabierto'); reload(); reloadS() }
  }

  return <Page title="Arqueo y cierre de caja" sub="Cuenta el efectivo del cajón y compáralo con lo que el sistema espera.">
    <div className="card">
      <div className="form-row">
        <Field label="Día"><input type="date" value={d} disabled={!isAdmin} onChange={e => setD(e.target.value)} /></Field>
        {s && <span className={'badge ' + (s.is_open ? 'good' : 'bad')}>{s.is_open ? 'Abierto' : 'Cerrado'}</span>}
      </div>
      {s && <>
        <div className="stats">
          <Stat label="Efectivo inicial" value={bs(s.opening)} />
          <Stat label="Entradas en efectivo" value={bs(s.cash_in)} />
          <Stat label="Salidas en efectivo" value={bs(s.cash_out)} />
          <Stat label="Efectivo esperado" value={bs(s.theoretical)} />
          <Stat label={`Ventas (${s.sales_count})`} value={bs(s.sales_total)} />
        </div>
        <table className="compact"><thead><tr><th>Forma de pago</th><th className="r">Entradas</th><th className="r">Salidas</th><th className="r">Neto</th></tr></thead>
          <tbody>{s.lines.map((l: any) => <tr key={l.method}><td>{l.method}{l.is_cash && <small className="sub"> (va al cajón)</small>}</td>
            <td className="r num">{bs(l.in)}</td><td className="r num">{bs(l.out)}</td><td className="r num">{bs(l.in - l.out)}</td></tr>)}</tbody></table>
        {s.is_open && <div className="form-row top-gap">
          <Field label="Efectivo contado (Bs)"><input type="number" value={c} onChange={e => setC(e.target.value)} /></Field>
          {diff !== null && <div className={'diff ' + (Math.abs(diff) < 0.005 ? 'good' : 'bad')}>Diferencia: <b>{bs(diff)}</b> {diff > 0 ? '(sobra)' : diff < 0 ? '(falta)' : ''}</div>}
          <Field label={diff ? 'Observación (obligatoria si hay diferencia)' : 'Observación'} grow><input value={n} onChange={e => setN(e.target.value)} /></Field>
          <button className="btn" onClick={close}>Cerrar el día</button>
        </div>}
      </>}
    </div>

    <div className="card flush"><h2 className="pad">Cierres anteriores</h2><div className="scroll"><table>
      <thead><tr><th>Fecha</th><th className="r">Inicial</th><th className="r">Esperado</th><th className="r">Contado</th><th className="r">Diferencia</th><th>Observación</th><th>Estado</th><th /></tr></thead>
      <tbody>{list.map((x: any) => <tr key={x.id}><td>{fdate(x.closure_date)}</td><td className="r num">{bs(x.opening_cash)}</td><td className="r num">{bs(x.theoretical_cash)}</td>
        <td className="r num">{bs(x.counted_cash)}</td><td className={'r num ' + (+x.difference ? 'bad-t' : '')}>{bs(x.difference)}</td><td>{x.notes}{x.reopen_reason && <small className="sub"><br />Reabierto: {x.reopen_reason}</small>}</td>
        <td><Status s={x.status} /></td><td className="r">{isAdmin && x.status === 'cerrado' && <button className="link" onClick={() => reopen(x.closure_date)}>Reabrir</button>}</td></tr>)}</tbody>
    </table></div>{!list.length && <Empty>Todavía no se cerró ningún día.</Empty>}</div>
  </Page>
}
