import { sb } from '../supabase'
import { ROLE_LABEL, fdate, friendly, toast, useTable } from '../lib'
import { Page } from '../ui'

export default function Usuarios({ me }: { me: any }) {
  const [u, load] = useTable('profiles', { order: 'created_at', asc: true })
  const upd = async (id: string, p: any) => {
    const { error } = await sb.from('profiles').update(p).eq('id', id)
    if (error) toast(friendly(error.message), 'err'); else toast('Usuario actualizado')
    load()
  }
  const pending = u.filter((x: any) => !x.active || !x.role).length
  return <Page title="Usuarios" sub={<>Cada persona crea su cuenta desde «Solicitar acceso» en la pantalla de ingreso (o la creas en Supabase › Authentication). Aquí le asignas el rol y la activas.{pending > 0 && <b> Hay {pending} cuenta(s) esperando activación.</b>}</>}>
    <div className="card flush"><div className="scroll"><table>
      <thead><tr><th>Correo</th><th>Nombre</th><th>Rol</th><th>Activo</th><th>Alta</th></tr></thead>
      <tbody>{u.map((x: any) => <tr key={x.id} className={!x.active ? 'muted' : ''}>
        <td>{x.email}{x.id === me.id && <small className="sub"> (tú)</small>}</td>
        <td><input defaultValue={x.full_name || ''} onBlur={e => e.target.value !== (x.full_name || '') && upd(x.id, { full_name: e.target.value })} /></td>
        <td><select value={x.role || ''} onChange={e => upd(x.id, { role: e.target.value || null })}><option value="">Sin rol</option>
          {Object.entries(ROLE_LABEL).map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></td>
        <td><input type="checkbox" checked={!!x.active} onChange={e => upd(x.id, { active: e.target.checked })} aria-label="Activo" /></td>
        <td>{fdate(x.created_at)}</td></tr>)}</tbody></table></div></div>
    <div className="card"><h2>Qué puede hacer cada rol</h2><table className="compact"><tbody>
      <tr><td><b>Administrador</b></td><td>Todo: configuración, precios, recetas, reportes, ajustes, usuarios y reabrir días cerrados.</td></tr>
      <tr><td><b>Caja</b></td><td>Vender, registrar gastos autorizados, ver sus ventas y cerrar la caja del día. No ve costos.</td></tr>
      <tr><td><b>Producción</b></td><td>Registrar y anular órdenes de producción, ver stock de helados.</td></tr>
      <tr><td><b>Compras</b></td><td>Registrar compras, proveedores y consultar el kárdex de insumos.</td></tr>
    </tbody></table></div>
  </Page>
}
