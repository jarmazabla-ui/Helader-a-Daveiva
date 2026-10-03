import { useState } from 'react'
import { bs, call, fdate, firstOfMonth, toast, today, useTable } from '../lib'
import { DateRange, Empty, Field, Page, Sel, Status, askReason } from '../ui'

export default function Gastos({ me }: { me: any }) {
  const isCaja = me.role === 'caja'
  const [cats] = useTable('categories', { order: 'name', asc: true })
  const [pm] = useTable('payment_methods', { filter: q => q.eq('active', true) })
  const [a, setA] = useState(isCaja ? today() : firstOfMonth()), [b, setB] = useState(today())
  const [exps, reloadE] = useTable('v_expenses', { order: 'created_at', filter: q => q.gte('expense_date', a).lte('expense_date', b), deps: [a, b] })
  const [incs, reloadI] = useTable('v_cash', { order: 'created_at', filter: q => q.eq('move_type', 'otro_ingreso').gte('move_date', a).lte('move_date', b), deps: [a, b] })
  const [kind, setKind] = useState<'gasto' | 'ingreso'>('gasto')
  const [f, setF] = useState<any>({ c: '', p: '', a: '', d: '', doc: '', date: today() })
  const opts = cats.filter((c: any) => c.kind === kind && (!isCaja || c.cashier_allowed))

  const save = async () => {
    if (!f.c || !f.p || !(+f.a > 0)) return toast('Complete categoría, forma de pago y un monto mayor a cero', 'err')
    const date = isCaja ? today() : f.date
    const ok = kind === 'gasto'
      ? await call('register_expense', { p_date: date, p_category: f.c, p_payment: f.p, p_amount: +f.a, p_desc: f.d || null, p_document: f.doc || null })
      : await call('register_income', { p_date: date, p_category: f.c, p_payment: f.p, p_amount: +f.a, p_desc: f.d || null })
    if (ok) { setF({ ...f, c: '', a: '', d: '', doc: '' }); reloadE(); reloadI(); toast(kind === 'gasto' ? 'Gasto registrado' : 'Ingreso registrado') }
  }
  const voidE = async (id: string) => { const m = await askReason('Anular gasto'); if (m && await call('void_expense', { p_id: id, p_reason: m })) { toast('Gasto anulado'); reloadE() } }
  const voidI = async (id: string) => { const m = await askReason('Anular ingreso'); if (m && await call('void_income', { p_id: id, p_reason: m })) { toast('Ingreso anulado'); reloadI() } }

  return <Page title="Gastos y otros ingresos" sub={isCaja ? 'Caja solo puede usar las categorías autorizadas por el administrador.' : undefined}>
    <div className="card">
      <div className="seg">
        <button className={kind === 'gasto' ? 'on' : ''} onClick={() => { setKind('gasto'); setF({ ...f, c: '' }) }}>Gasto</button>
        <button className={kind === 'ingreso' ? 'on' : ''} onClick={() => { setKind('ingreso'); setF({ ...f, c: '' }) }}>Otro ingreso</button>
      </div>
      <div className="form-row">
        {!isCaja && <Field label="Fecha"><input type="date" value={f.date} onChange={e => setF({ ...f, date: e.target.value })} /></Field>}
        <Field label="Categoría"><Sel v={f.c} set={(v: any) => setF({ ...f, c: v })} opts={opts} ph="Elegir…" /></Field>
        <Field label="Forma de pago"><Sel v={f.p} set={(v: any) => setF({ ...f, p: v })} opts={pm} ph="Elegir…" /></Field>
        <Field label="Monto (Bs)"><input type="number" value={f.a} onChange={e => setF({ ...f, a: e.target.value })} /></Field>
        <Field label="Descripción" grow><input value={f.d} onChange={e => setF({ ...f, d: e.target.value })} /></Field>
        {kind === 'gasto' && <Field label="N° factura/recibo"><input value={f.doc} onChange={e => setF({ ...f, doc: e.target.value })} /></Field>}
        <button className="btn" onClick={save}>{kind === 'gasto' ? 'Registrar gasto' : 'Registrar ingreso'}</button>
      </div>
      {!opts.length && <p className="sub">No hay categorías de {kind} {isCaja ? 'autorizadas para Caja' : 'creadas'}. {isCaja ? 'Pide al administrador que las habilite.' : 'Créalas en Configuración.'}</p>}
    </div>

    <div className="toolbar"><DateRange a={a} b={b} setA={setA} setB={setB} /></div>
    <div className="grid2">
      <div className="card flush"><h2 className="pad">Gastos · {bs(exps.filter((e: any) => e.status === 'confirmado').reduce((s: number, e: any) => s + +e.amount, 0))}</h2>
        <div className="scroll"><table><thead><tr><th>Fecha</th><th>Categoría</th><th>Detalle</th><th className="r">Monto</th><th /></tr></thead>
          <tbody>{exps.map((e: any) => <tr key={e.id} className={e.status === 'anulado' ? 'muted' : ''}>
            <td>{fdate(e.expense_date)}</td><td>{e.category}</td><td>{e.description}{e.document && <small className="sub"> · Doc. {e.document}</small>}</td>
            <td className="r num">{bs(e.amount)}</td>
            <td className="r">{e.status === 'confirmado' ? <button className="link danger" onClick={() => voidE(e.id)}>Anular</button> : <Status s="anulado" />}</td></tr>)}</tbody></table></div>
        {!exps.length && <Empty>Sin gastos en el período.</Empty>}</div>
      <div className="card flush"><h2 className="pad">Otros ingresos · {bs(incs.filter((e: any) => e.status === 'confirmado').reduce((s: number, e: any) => s + +e.amount_in, 0))}</h2>
        <div className="scroll"><table><thead><tr><th>Fecha</th><th>Categoría</th><th>Detalle</th><th className="r">Monto</th><th /></tr></thead>
          <tbody>{incs.map((e: any) => <tr key={e.id} className={e.status === 'anulado' ? 'muted' : ''}>
            <td>{fdate(e.move_date)}</td><td>{e.category}</td><td>{e.description}</td><td className="r num">{bs(e.amount_in)}</td>
            <td className="r">{e.status === 'confirmado' ? <button className="link danger" onClick={() => voidI(e.id)}>Anular</button> : <Status s="anulado" />}</td></tr>)}</tbody></table></div>
        {!incs.length && <Empty>Sin otros ingresos en el período.</Empty>}</div>
    </div>
  </Page>
}
