import { useState } from 'react'
import { sb } from '../supabase'
import { bs, call, exportCSV, fdate, firstOfMonth, money, num, today, useTable } from '../lib'
import { DateRange, Empty, Page } from '../ui'

export function Costos() {
  const [r] = useTable('v_costs', { order: 'product', asc: true })
  return <Page title="Costos y márgenes" sub="Costo estimado de cada producto con el costo promedio actual de los insumos y envases."
    actions={<button className="btn ghost" onClick={() => exportCSV('costos', [['product', 'Sabor'], ['presentation', 'Presentación'], ['content_cost', 'Contenido'], ['packaging_cost', 'Envase'], ['unit_cost', 'Costo'], ['sale_price', 'Precio']], r)}>Exportar</button>}>
    <div className="card flush"><div className="scroll"><table>
      <thead><tr><th>Sabor</th><th>Presentación</th><th className="r">Contenido</th><th className="r">Envase</th><th className="r">Costo total</th><th className="r">Precio</th><th className="r">Utilidad</th><th className="r">Margen</th><th className="r">Recargo</th></tr></thead>
      <tbody>{r.map((x: any) => {
        const u = x.sale_price - x.unit_cost, m = x.sale_price > 0 ? u / x.sale_price * 100 : null
        return <tr key={x.id}><td>{x.product}</td><td>{x.presentation}</td><td className="r num">{money(x.content_cost)}</td><td className="r num">{money(x.packaging_cost)}</td>
          <td className="r num"><b>{money(x.unit_cost)}</b></td><td className="r num">{money(x.sale_price)}</td><td className={'r num ' + (u < 0 ? 'bad-t' : '')}>{money(u)}</td>
          <td className={'r num ' + (m !== null && m < 30 ? 'bad-t' : '')}>{m === null ? '—' : num(m, 1) + '%'}</td><td className="r num">{x.unit_cost > 0 ? num(u / x.unit_cost * 100, 1) + '%' : '—'}</td></tr>
      })}</tbody></table></div>
      {!r.length && <Empty>Configura sabores, presentaciones, recetas y envases para ver los costos.</Empty>}</div>
    <p className="sub">Margen = utilidad ÷ precio. Recargo = utilidad ÷ costo. En rojo los márgenes menores a 30%.</p>
  </Page>
}

export function RepVentas() {
  const [a, setA] = useState(firstOfMonth()), [b, setB] = useState(today()), [rows, setRows] = useState<any[] | null>(null)
  const go = async () => {
    const { data } = await sb.from('v_sales_lines').select('*').gte('sale_date', a).lte('sale_date', b).limit(20000)
    const m: Record<string, any> = {}
    for (const x of data || []) { const k = x.product + ' · ' + x.presentation; m[k] ||= { k, q: 0, a: 0, c: 0 }; m[k].q += +x.qty; m[k].a += +x.amount; m[k].c += +x.cost_total }
    setRows(Object.values(m).sort((x: any, y: any) => y.a - x.a))
  }
  const T = (rows || []).reduce((s, x) => ({ q: s.q + x.q, a: s.a + x.a, c: s.c + x.c }), { q: 0, a: 0, c: 0 })
  return <Page title="Ventas y márgenes por producto">
    <div className="toolbar"><DateRange a={a} b={b} setA={setA} setB={setB} /><button className="btn" onClick={go}>Consultar</button><span className="spacer" />
      {rows && <button className="btn ghost" onClick={() => exportCSV('ventas-por-producto', [['k', 'Producto'], ['q', 'Unidades'], ['a', 'Ventas'], ['c', 'Costo']], rows)}>Exportar</button>}</div>
    {rows && <div className="card flush"><div className="scroll"><table>
      <thead><tr><th>Producto</th><th className="r">Unidades</th><th className="r">Ventas</th><th className="r">Costo</th><th className="r">Utilidad</th><th className="r">Margen</th><th className="r">% de ventas</th></tr></thead>
      <tbody>{rows.map(x => <tr key={x.k}><td>{x.k}</td><td className="r num">{num(x.q, 0)}</td><td className="r num">{money(x.a)}</td><td className="r num">{money(x.c)}</td>
        <td className="r num">{money(x.a - x.c)}</td><td className="r num">{x.a ? num((x.a - x.c) / x.a * 100, 1) + '%' : '—'}</td><td className="r num">{T.a ? num(x.a / T.a * 100, 1) + '%' : ''}</td></tr>)}
        <tr className="foot"><td>Total</td><td className="r num">{num(T.q, 0)}</td><td className="r num">{money(T.a)}</td><td className="r num">{money(T.c)}</td><td className="r num">{money(T.a - T.c)}</td>
          <td className="r num">{T.a ? num((T.a - T.c) / T.a * 100, 1) + '%' : '—'}</td><td /></tr></tbody></table></div>
      {!rows.length && <Empty>No hubo ventas entre {fdate(a)} y {fdate(b)}.</Empty>}</div>}
  </Page>
}

export function Estado() {
  const [a, setA] = useState(firstOfMonth()), [b, setB] = useState(today()), [r, setR] = useState<any>(null)
  const R = (l: string, v: any, cls = '') => <tr className={cls}><td>{l}</td><td className="r num">{money(v)}</td></tr>
  const grp = (g: string) => (r?.gastos || []).filter((x: any) => x.grupo === g)
  return <Page title="Estado de resultados" sub="Ventas menos costo de lo vendido, gastos y mermas del período.">
    <div className="toolbar"><DateRange a={a} b={b} setA={setA} setB={setB} />
      <button className="btn" onClick={async () => setR(await call('income_statement', { p_from: a, p_to: b }))}>Generar</button>
      {r && <button className="btn ghost" onClick={() => window.print()}>Imprimir</button>}</div>
    {r && <div className="card statement">
      <h2>Del {fdate(a)} al {fdate(b)}</h2>
      <table><tbody>
        {R('Ventas', r.ventas, 'strong')}{R('(−) Costo de lo vendido', r.costo_ventas)}
        {R('Utilidad bruta', r.utilidad_bruta, 'strong line')}
        <tr><td className="sub">Margen bruto</td><td className="r num sub">{num(r.margen_bruto, 2)}%</td></tr>
        <tr><td colSpan={2} className="group">Gastos de personal</td></tr>{grp('personal').map((g: any) => R('  ' + g.categoria, g.monto, 'indent'))}
        <tr><td colSpan={2} className="group">Gastos administrativos</td></tr>{grp('administrativo').map((g: any) => R('  ' + g.categoria, g.monto, 'indent'))}
        {R('Total gastos operativos', r.total_operativos, 'strong')}
        {R('Resultado operativo', r.resultado_operativo, 'strong line')}
        {R('(+) Otros ingresos', r.otros_ingresos)}
        {R('(−) Otros gastos', r.otros_gastos)}
        {grp('otros').map((g: any) => R('  ' + g.categoria, g.monto, 'indent sub'))}
        {R('(−) Mermas y ajustes de inventario', r.mermas)}
        <tr className={'total ' + (+r.resultado < 0 ? 'bad-t' : 'good-t')}><td>Resultado del período</td><td className="r num">{bs(r.resultado)}</td></tr>
      </tbody></table>
    </div>}
  </Page>
}
