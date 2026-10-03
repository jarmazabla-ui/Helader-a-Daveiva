import { ReactNode, useEffect, useMemo, useState } from 'react'
import { sb } from './supabase'
import { exportCSV, friendly, toast, useTable } from './lib'
import { Empty, Field, Modal, Page, confirmBox } from './ui'

export type CrudField = {
  k: string; l: string
  type?: 'text' | 'number' | 'bool'
  ref?: { table: string; label: string | ((o: any) => string) }
  opts?: (string | [string, string])[]
  form?: boolean       // se muestra en el formulario (por defecto sí)
  list?: boolean       // se muestra en la tabla (por defecto sí)
  required?: boolean
  fmt?: (v: any, row: any) => ReactNode
  hint?: string
}
type Props = {
  table: string; view?: string; title: string; sub?: ReactNode; fields: CrudField[]
  order?: string; asc?: boolean; canEdit?: boolean; canDelete?: boolean
  filter?: (q: any) => any; deps?: any[]; rowActions?: (r: any, reload: () => void) => ReactNode
  defaults?: Record<string, any>; embedded?: boolean
}

export default function Crud(p: Props) {
  const { fields, canEdit = true, canDelete = true } = p
  const [rows, reload, loading] = useTable(p.view || p.table, { order: p.order, asc: p.asc, filter: p.filter, deps: p.deps })
  const [refs, setRefs] = useState<Record<string, any[]>>({})
  const [edit, setEdit] = useState<any | null>(null)
  const [q, setQ] = useState('')

  useEffect(() => {
    (async () => {
      const r: Record<string, any[]> = {}
      for (const f of fields.filter(f => f.ref)) {
        const { data } = await sb.from(f.ref!.table).select('*').limit(2000)
        r[f.k] = data || []
      }
      setRefs(r)
    })()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [p.table])

  const refLabel = (f: CrudField, o: any) => !o ? '' : typeof f.ref!.label === 'function' ? f.ref!.label(o) : o[f.ref!.label]
  const show = (f: CrudField, r: any): ReactNode => {
    const v = r[f.k]
    if (f.fmt) return f.fmt(v, r)
    if (f.ref) return refLabel(f, (refs[f.k] || []).find(o => o.id === v))
    if (f.type === 'bool') return v ? 'Sí' : 'No'
    if (f.opts) { const o = f.opts.find(o => (Array.isArray(o) ? o[0] : o) === v); return Array.isArray(o) ? o[1] : (v ?? '') }
    return v == null ? '' : String(v)
  }
  const listF = fields.filter(f => f.list !== false)
  const formF = fields.filter(f => f.form !== false)
  const shown = useMemo(() => {
    const s = q.trim().toLowerCase()
    if (!s) return rows
    return rows.filter(r => listF.some(f => String(show(f, r) ?? '').toLowerCase().includes(s)))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rows, q, refs])

  const save = async () => {
    const row: any = {}
    for (const f of formF) {
      let v = edit[f.k]
      if (f.type === 'bool') v = !!v
      else if (v === '' || v === undefined) v = null
      else if (f.type === 'number') v = Number(v)
      if (f.required && (v === null || v === '')) return toast('Complete: ' + f.l, 'err')
      row[f.k] = v
    }
    const res = edit.__new
      ? await sb.from(p.table).insert(row)
      : await sb.from(p.table).update(row).match(keyOf(edit.__orig || edit))
    if (res.error) return toast(friendly(res.error.message), 'err')
    toast(edit.__new ? 'Registro creado' : 'Cambios guardados'); setEdit(null); reload()
  }
  const keyOf = (r: any) => r.id ? { id: r.id } : Object.fromEntries(formF.filter(f => f.ref).map(f => [f.k, r[f.k]]))
  const del = async (r: any) => {
    if (!(await confirmBox('¿Eliminar este registro?', 'Eliminar'))) return
    const { error } = await sb.from(p.table).delete().match(keyOf(r))
    if (error) return toast(friendly(error.message), 'err')
    toast('Eliminado'); reload()
  }

  const input = (f: CrudField) => {
    const v = edit[f.k], set = (x: any) => setEdit({ ...edit, [f.k]: x })
    if (f.type === 'bool') return <label className="check"><input type="checkbox" checked={!!v} onChange={e => set(e.target.checked)} /> {f.l}</label>
    let ctrl: ReactNode
    if (f.ref) ctrl = <select value={v ?? ''} onChange={e => set(e.target.value)}><option value="">Elegir…</option>
      {(refs[f.k] || []).filter(o => o.active !== false || o.id === v).map(o => <option key={o.id} value={o.id}>{refLabel(f, o)}</option>)}</select>
    else if (f.opts) ctrl = <select value={v ?? ''} onChange={e => set(e.target.value)}><option value="">Elegir…</option>
      {f.opts.map(o => Array.isArray(o) ? <option key={o[0]} value={o[0]}>{o[1]}</option> : <option key={o}>{o}</option>)}</select>
    else ctrl = <input type={f.type === 'number' ? 'number' : 'text'} step="any" value={v ?? ''} onChange={e => set(e.target.value)} />
    return <Field label={f.l + (f.required ? ' *' : '')}>{ctrl}{f.hint && <small className="hint">{f.hint}</small>}</Field>
  }

  const body = <>
    <div className="toolbar">
      <input className="search" placeholder="Buscar…" value={q} onChange={e => setQ(e.target.value)} />
      <span className="spacer" />
      <button className="btn ghost" onClick={() => exportCSV(p.title, listF.map(f => [f.k, f.l]), shown.map(r => Object.fromEntries(listF.map(f => [f.k, typeof show(f, r) === 'object' ? r[f.k] : show(f, r)]))))}>Exportar</button>
      {canEdit && <button className="btn" onClick={() => setEdit({ __new: true, ...(fields.some(f => f.k === 'active') ? { active: true } : {}), ...p.defaults })}>Agregar</button>}
    </div>
    <div className="card flush"><div className="scroll"><table>
      <thead><tr>{listF.map(f => <th key={f.k} className={f.type === 'number' ? 'r' : ''}>{f.l}</th>)}{(canEdit || p.rowActions) && <th />}</tr></thead>
      <tbody>
        {shown.map((r, i) => <tr key={r.id || i} className={r.active === false ? 'muted' : ''}>
          {listF.map(f => <td key={f.k} className={f.type === 'number' ? 'r num' : ''}>{show(f, r)}</td>)}
          {(canEdit || p.rowActions) && <td className="r nowrap">
            {p.rowActions?.(r, reload)}
            {canEdit && <button className="link" onClick={() => setEdit({ ...r, __orig: r })}>Editar</button>}
            {canEdit && canDelete && <button className="link danger" onClick={() => del(r)}>Eliminar</button>}
          </td>}
        </tr>)}
      </tbody>
    </table></div>
      {!loading && !shown.length && <Empty>{q ? 'Sin resultados para la búsqueda.' : canEdit ? 'Aún no hay registros. Usa «Agregar» para crear el primero.' : 'Aún no hay movimientos.'}</Empty>}
    </div>
    {edit && <Modal title={(edit.__new ? 'Nuevo: ' : 'Editar: ') + p.title} onClose={() => setEdit(null)}>
      <div className="form-grid">{formF.map(f => <div key={f.k} className={f.type === 'bool' ? 'span' : ''}>{input(f)}</div>)}</div>
      <div className="actions"><button className="btn ghost" onClick={() => setEdit(null)}>Cancelar</button><button className="btn" onClick={save}>Guardar</button></div>
    </Modal>}
  </>
  return p.embedded ? <div className="embedded"><h2>{p.title}</h2>{p.sub && <p className="sub">{p.sub}</p>}{body}</div> : <Page title={p.title} sub={p.sub}>{body}</Page>
}
