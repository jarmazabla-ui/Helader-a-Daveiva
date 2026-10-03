import { ReactNode, useEffect, useState } from 'react'
import { onToasts } from './lib'

/* ---------- Avisos flotantes ---------- */
export function Toaster() {
  const [t, setT] = useState<any[]>([])
  useEffect(() => onToasts(setT), [])
  return <div className="toasts" role="status">{t.map(x => <div key={x.id} className={'toast ' + x.kind}>{x.text}</div>)}</div>
}

/* ---------- Ventana modal ---------- */
export function Modal({ title, onClose, children, wide }: { title: string; onClose: () => void; children: ReactNode; wide?: boolean }) {
  useEffect(() => {
    const k = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    window.addEventListener('keydown', k); return () => window.removeEventListener('keydown', k)
  }, [onClose])
  return <div className="overlay" onMouseDown={e => e.target === e.currentTarget && onClose()}>
    <div className={'modal' + (wide ? ' wide' : '')} role="dialog" aria-label={title}>
      <div className="modal-head"><h3>{title}</h3><button className="x" onClick={onClose} aria-label="Cerrar">×</button></div>
      {children}
    </div>
  </div>
}

/* ---------- Preguntar motivo / confirmar (reemplaza prompt y confirm) ---------- */
type Ask = { title: string; label?: string; ok: string; danger?: boolean; resolve: (v: string | null) => void }
let askHost: ((a: Ask | null) => void) | null = null
export const askReason = (title: string, ok = 'Anular') =>
  new Promise<string | null>(resolve => askHost?.({ title, label: 'Motivo (obligatorio)', ok, danger: true, resolve }))
export const confirmBox = (title: string, ok = 'Sí, continuar') =>
  new Promise<boolean>(resolve => askHost?.({ title, ok, resolve: v => resolve(v !== null) }))

export function DialogHost() {
  const [a, setA] = useState<Ask | null>(null), [v, setV] = useState('')
  useEffect(() => { askHost = x => { setV(''); setA(x) } }, [])
  if (!a) return null
  const done = (val: string | null) => { a.resolve(val); setA(null) }
  const canOk = !a.label || v.trim() !== ''
  return <Modal title={a.title} onClose={() => done(null)}>
    {a.label && <label className="field"><span>{a.label}</span>
      <input autoFocus value={v} onChange={e => setV(e.target.value)} onKeyDown={e => e.key === 'Enter' && canOk && done(v.trim())} /></label>}
    <div className="actions">
      <button className="btn ghost" onClick={() => done(null)}>Cancelar</button>
      <button className={'btn ' + (a.danger ? 'danger' : '')} disabled={!canOk} onClick={() => done(a.label ? v.trim() : 'ok')}>{a.ok}</button>
    </div>
  </Modal>
}

/* ---------- Controles ---------- */
export const Sel = ({ v, set, opts, ph, lab = 'name', disabled }: any) =>
  <select value={v ?? ''} onChange={e => set(e.target.value)} disabled={disabled} aria-label={ph}>
    <option value="">{ph}</option>
    {opts.map((o: any) => <option key={o.id} value={o.id}>{typeof lab === 'function' ? lab(o) : o[lab]}</option>)}
  </select>

export const Field = ({ label, children, grow }: { label: string; children: ReactNode; grow?: boolean }) =>
  <label className={'field' + (grow ? ' grow' : '')}><span>{label}</span>{children}</label>

export const Page = ({ title, sub, actions, children }: { title: string; sub?: ReactNode; actions?: ReactNode; children: ReactNode }) =>
  <section className="page">
    <header className="page-head"><div><h1>{title}</h1>{sub && <p className="sub">{sub}</p>}</div>{actions && <div className="head-actions">{actions}</div>}</header>
    {children}
  </section>

export const Empty = ({ children }: { children: ReactNode }) => <div className="empty">{children}</div>

export const Status = ({ s }: { s: string }) => <span className={'badge ' + (s === 'anulado' ? 'bad' : s === 'reabierto' ? 'warn' : 'good')}>{s}</span>

export const Stat = ({ label, value, tone }: { label: string; value: ReactNode; tone?: 'good' | 'bad' | 'warn' }) =>
  <div className={'stat ' + (tone || '')}><span>{label}</span><strong>{value}</strong></div>

export function DateRange({ a, b, setA, setB }: any) {
  return <>
    <Field label="Desde"><input type="date" value={a} onChange={e => setA(e.target.value)} /></Field>
    <Field label="Hasta"><input type="date" value={b} onChange={e => setB(e.target.value)} /></Field>
  </>
}
