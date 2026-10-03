import { ReactNode, useEffect, useState } from 'react'
import { configured, sb } from './supabase'
import { ROLE_LABEL, Role, friendly } from './lib'
import { DialogHost, Toaster } from './ui'
import Dashboard from './pages/Dashboard'
import POS from './pages/POS'
import Ventas from './pages/Ventas'
import Gastos from './pages/Gastos'
import Cierre from './pages/Cierre'
import Compras from './pages/Compras'
import Produccion from './pages/Produccion'
import Recetas from './pages/Recetas'
import Catalogo from './pages/Catalogo'
import Insumos from './pages/Insumos'
import Inventario from './pages/Inventario'
import Kardex from './pages/Kardex'
import Usuarios from './pages/Usuarios'
import Config from './pages/Config'
import { Costos, Estado, RepVentas } from './pages/Reportes'
import { Auditoria, CajaMov, Proveedores } from './pages/Otros'

type Item = { id: string; label: string; roles: Role[]; render: (me: any, go: (p: string) => void) => ReactNode }
const ALL: Role[] = ['admin', 'caja', 'produccion', 'compras']
const MENU: [string, Item[]][] = [
  ['Operación', [
    { id: 'inicio', label: 'Inicio', roles: ALL, render: (me, go) => <Dashboard me={me} go={go} /> },
    { id: 'caja', label: 'Caja', roles: ['admin', 'caja'], render: () => <POS /> },
    { id: 'ventas', label: 'Ventas realizadas', roles: ['admin', 'caja'], render: me => <Ventas me={me} /> },
    { id: 'gastos', label: 'Gastos e ingresos', roles: ['admin', 'caja'], render: me => <Gastos me={me} /> },
    { id: 'cierre', label: 'Arqueo y cierre', roles: ['admin', 'caja'], render: me => <Cierre me={me} /> },
  ]],
  ['Producción', [
    { id: 'produccion', label: 'Producción', roles: ['admin', 'produccion'], render: me => <Produccion me={me} /> },
    { id: 'recetas', label: 'Recetas', roles: ['admin'], render: () => <Recetas /> },
  ]],
  ['Compras e inventario', [
    { id: 'compras', label: 'Compras', roles: ['admin', 'compras'], render: () => <Compras /> },
    { id: 'proveedores', label: 'Proveedores', roles: ['admin', 'compras'], render: () => <Proveedores /> },
    { id: 'insumos', label: 'Insumos', roles: ['admin'], render: () => <Insumos /> },
    { id: 'inventario', label: 'Inventario y ajustes', roles: ['admin'], render: () => <Inventario /> },
    { id: 'kardex', label: 'Kárdex', roles: ['admin', 'compras'], render: me => <Kardex me={me} /> },
  ]],
  ['Reportes', [
    { id: 'resultados', label: 'Estado de resultados', roles: ['admin'], render: () => <Estado /> },
    { id: 'rep-ventas', label: 'Ventas por producto', roles: ['admin'], render: () => <RepVentas /> },
    { id: 'costos', label: 'Costos y márgenes', roles: ['admin'], render: () => <Costos /> },
    { id: 'libro-caja', label: 'Libro de caja', roles: ['admin'], render: () => <CajaMov /> },
  ]],
  ['Administración', [
    { id: 'catalogo', label: 'Productos y precios', roles: ['admin'], render: () => <Catalogo /> },
    { id: 'usuarios', label: 'Usuarios', roles: ['admin'], render: me => <Usuarios me={me} /> },
    { id: 'config', label: 'Configuración', roles: ['admin'], render: () => <Config /> },
    { id: 'auditoria', label: 'Auditoría', roles: ['admin'], render: () => <Auditoria /> },
  ]],
]

function Login({ onDone }: { onDone: () => void }) {
  const [mode, setMode] = useState<'in' | 'up'>('in'), [em, setEm] = useState(''), [pw, setPw] = useState(''), [name, setName] = useState('')
  const [msg, setMsg] = useState<{ t: string; bad?: boolean } | null>(null), [busy, setBusy] = useState(false)
  const go = async () => {
    if (!em || !pw) return setMsg({ t: 'Escribe tu correo y contraseña.', bad: true })
    setBusy(true); setMsg(null)
    if (mode === 'in') {
      const { error } = await sb.auth.signInWithPassword({ email: em.trim(), password: pw })
      setBusy(false)
      if (error) return setMsg({ t: /confirm/i.test(error.message) ? 'Confirma tu correo con el enlace que te enviamos y vuelve a intentar.' : 'Correo o contraseña incorrectos.', bad: true })
      onDone()
    } else {
      if (pw.length < 6) { setBusy(false); return setMsg({ t: 'La contraseña debe tener al menos 6 caracteres.', bad: true }) }
      const { data, error } = await sb.auth.signUp({ email: em.trim(), password: pw })
      if (error) { setBusy(false); return setMsg({ t: friendly(error.message), bad: true }) }
      if (data.session && name) await sb.from('profiles').update({ full_name: name }).eq('id', data.user!.id)
      setBusy(false)
      if (data.session) onDone()
      else setMsg({ t: 'Cuenta creada. Si te llega un correo, confírmalo. Luego pide al administrador que active tu cuenta.' })
    }
  }
  return <div className="login-wrap"><div className="login">
    <div className="brand big"><span className="cone" aria-hidden />Heladería</div>
    <p className="sub">{mode === 'in' ? 'Ingresa con tu cuenta.' : 'Crea tu cuenta. El administrador debe activarla antes de que puedas usar el sistema.'}</p>
    {mode === 'up' && <label className="field"><span>Nombre</span><input value={name} onChange={e => setName(e.target.value)} /></label>}
    <label className="field"><span>Correo</span><input type="email" autoComplete="email" value={em} onChange={e => setEm(e.target.value)} /></label>
    <label className="field"><span>Contraseña</span><input type="password" autoComplete={mode === 'in' ? 'current-password' : 'new-password'} value={pw} onChange={e => setPw(e.target.value)} onKeyDown={e => e.key === 'Enter' && go()} /></label>
    {msg && <div className={'notice ' + (msg.bad ? 'bad' : 'good')}>{msg.t}</div>}
    <button className="btn big full" disabled={busy} onClick={go}>{busy ? 'Un momento…' : mode === 'in' ? 'Ingresar' : 'Crear cuenta'}</button>
    <button className="link center" onClick={() => { setMode(mode === 'in' ? 'up' : 'in'); setMsg(null) }}>{mode === 'in' ? '¿No tienes cuenta? Solicitar acceso' : 'Ya tengo cuenta, ingresar'}</button>
  </div></div>
}

export default function App() {
  const [me, setMe] = useState<any>(null), [ready, setReady] = useState(false)
  const [page, setPage] = useState(() => location.hash.slice(1)), [nav, setNav] = useState(false)

  const loadMe = async () => {
    const { data: { session } } = await sb.auth.getSession()
    if (!session) { setMe(null); setReady(true); return }
    const { data } = await sb.from('profiles').select('*').eq('id', session.user.id).single()
    setMe(data || { id: session.user.id, email: session.user.email }); setReady(true)
  }
  useEffect(() => {
    if (!configured) { setReady(true); return }
    loadMe()
    const { data } = sb.auth.onAuthStateChange(ev => { if (ev === 'SIGNED_OUT') setMe(null) })
    return () => data.subscription.unsubscribe()
  }, [])
  const go = (p: string) => { setPage(p); location.hash = p; setNav(false); window.scrollTo(0, 0) }
  const logout = async () => { await sb.auth.signOut(); setMe(null); go('') }

  if (!configured) return <div className="login-wrap"><div className="login">
    <div className="brand big"><span className="cone" aria-hidden />Heladería</div>
    <div className="notice warn">Falta conectar la base de datos. Abre <code>src/supabase.ts</code> y pega tu Project URL y tu Publishable key de Supabase, o configura las variables <code>VITE_SUPABASE_URL</code> y <code>VITE_SUPABASE_KEY</code> en Netlify.</div>
  </div></div>
  if (!ready) return <div className="login-wrap"><p className="sub">Cargando…</p></div>
  if (!me) return <><Login onDone={loadMe} /><Toaster /></>
  if (!me.active || !me.role) return <div className="login-wrap"><div className="login">
    <div className="brand big"><span className="cone" aria-hidden />Heladería</div>
    <p>Hola{me.email ? ', ' + me.email : ''}. Tu cuenta aún no está activa.</p>
    <p className="sub">Pide al administrador que te asigne un rol en «Usuarios». Después vuelve a ingresar.</p>
    <div className="actions"><button className="btn ghost" onClick={loadMe}>Ya me activaron</button><button className="btn" onClick={logout}>Salir</button></div>
  </div></div>

  const groups = MENU.map(([g, items]) => [g, items.filter(i => i.roles.includes(me.role))] as const).filter(([, i]) => i.length)
  const flat = groups.flatMap(([, i]) => i)
  const cur = flat.find(i => i.id === page) || flat[0]

  return <div className="layout">
    <aside className={'side' + (nav ? ' open' : '')}>
      <div className="side-top">
        <div className="brand"><span className="cone" aria-hidden />Heladería</div>
        <button className="menu-btn" onClick={() => setNav(!nav)} aria-label="Menú" aria-expanded={nav}>{nav ? 'Cerrar' : 'Menú'}</button>
      </div>
      <nav>
        {groups.map(([g, items]) => <div key={g} className="nav-group"><small>{g}</small>
          {items.map(i => <button key={i.id} className={cur.id === i.id ? 'on' : ''} aria-current={cur.id === i.id ? 'page' : undefined} onClick={() => go(i.id)}>{i.label}</button>)}
        </div>)}
      </nav>
      <div className="who"><b>{me.full_name || me.email}</b><span>{ROLE_LABEL[me.role]}</span><button className="link light" onClick={logout}>Cerrar sesión</button></div>
    </aside>
    <main className="main" key={cur.id}>{cur.render(me, go)}</main>
    <Toaster /><DialogHost />
  </div>
}
