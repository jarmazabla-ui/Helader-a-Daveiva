import { bs, fdate, num, useRpc } from '../lib'
import { Empty, Page, Stat } from '../ui'

export default function Dashboard({ me, go }: { me: any; go: (p: string) => void }) {
  const [d] = useRpc<any>('dashboard', {})
  const hello = (me.full_name || me.email || '').split(' ')[0]
  if (!d) return <Page title={`Hola, ${hello}`}><p className="sub">Cargando resumen…</p></Page>
  const max = Math.max(1, ...(d.ventas_14d || []).map((x: any) => +x.t))
  return <Page title={`Hola, ${hello}`} sub={`Resumen al ${fdate(d.today)}`}>
    {'dia_abierto' in d && !d.dia_abierto && <div className="notice warn">La caja de hoy ya fue cerrada. Para registrar más ventas, el administrador debe reabrir el día.</div>}

    <div className="stats">
      {d.role === 'caja' && <><Stat label="Mis ventas de hoy" value={bs(d.mis_ventas_hoy)} /><Stat label="Tickets de hoy" value={d.mis_tickets_hoy} /></>}
      {d.role === 'admin' && <>
        <Stat label="Ventas de hoy" value={bs(d.ventas_hoy)} />
        <Stat label="Ventas del mes" value={bs(d.ventas_mes)} />
        <Stat label="Utilidad bruta del mes" value={bs(d.utilidad_bruta_mes)} tone="good" />
        <Stat label="Gastos del mes" value={bs(d.gastos_mes)} />
        <Stat label="Inventario de insumos" value={bs(d.valor_insumos)} />
        <Stat label="Inventario de helados" value={bs(d.valor_terminados)} />
      </>}
      {(d.role === 'admin' || d.role === 'compras') && <Stat label="Compras del mes" value={bs(d.compras_mes)} />}
      {(d.role === 'admin' || d.role === 'produccion') && <>
        <Stat label="Litros producidos en el mes" value={num(d.litros_mes, 1) + ' L'} />
        <Stat label="Órdenes de producción" value={d.ordenes_mes} /></>}
      {d.low_stock && <Stat label="Insumos bajo el mínimo" value={d.low_stock.length} tone={d.low_stock.length ? 'bad' : undefined} />}
    </div>

    <div className="grid2">
      {d.ventas_14d && <div className="card">
        <h2>Ventas de los últimos 14 días</h2>
        <div className="bars" role="img" aria-label="Gráfico de ventas diarias">
          {d.ventas_14d.map((x: any) => <div key={x.d} className="bar" title={`${fdate(x.d)}: ${bs(x.t)}`}>
            <i style={{ height: (+x.t / max * 100) + '%' }} /><small>{x.d.slice(8)}</small></div>)}
        </div>
      </div>}

      {d.top_mes && <div className="card"><h2>Más vendidos del mes</h2>
        {d.top_mes.length ? <table><tbody>{d.top_mes.map((x: any) => <tr key={x.name}><td>{x.name}</td><td className="r num">{num(x.u, 0)} u</td><td className="r num">{bs(x.t)}</td></tr>)}</tbody></table>
          : <Empty>Todavía no hay ventas este mes.</Empty>}</div>}

      {d.low_stock && <div className="card"><h2>Insumos por reponer</h2>
        {d.low_stock.length ? <table><thead><tr><th>Insumo</th><th className="r">Stock</th><th className="r">Mínimo</th></tr></thead>
          <tbody>{d.low_stock.map((x: any) => <tr key={x.name}><td>{x.name}</td><td className="r num bad-t">{num(x.stock)} {x.unit}</td><td className="r num">{num(x.min)} {x.unit}</td></tr>)}</tbody></table>
          : <Empty>Todo el stock está sobre el mínimo.</Empty>}
        {d.low_stock.length > 0 && me.role !== 'produccion' && <button className="btn ghost" onClick={() => go('compras')}>Registrar compra</button>}
      </div>}

      {d.terminados && <div className="card"><h2>Helados disponibles</h2>
        {d.terminados.length ? <table><tbody>{d.terminados.map((x: any) => <tr key={x.name}><td>{x.name}</td>
          <td className={'r num ' + (+x.stock <= 0 ? 'bad-t' : '')}>{num(x.stock, 0)} u</td></tr>)}</tbody></table>
          : <Empty>Aún no hay productos configurados.</Empty>}</div>}
    </div>
  </Page>
}
