import { useCallback, useEffect, useState } from 'react'
import { sb } from './supabase'

export type Role = 'admin' | 'caja' | 'produccion' | 'compras'

/* ---------- fechas y números ---------- */
export const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'America/La_Paz' })
export const firstOfMonth = () => today().slice(0, 8) + '01'
export const addDays = (d: string, n: number) => {
  const x = new Date(d + 'T12:00:00'); x.setDate(x.getDate() + n); return x.toLocaleDateString('en-CA')
}
const nf2 = new Intl.NumberFormat('es-BO', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
export const bs = (x: any) => 'Bs ' + nf2.format(Number(x || 0))
export const money = (x: any) => nf2.format(Number(x || 0))
export const num = (x: any, d = 3) => new Intl.NumberFormat('es-BO', { maximumFractionDigits: d }).format(Number(x || 0))
export const fdate = (s?: string) => (s ? s.slice(0, 10).split('-').reverse().join('/') : '')
export const fdt = (s?: string) =>
  s ? new Date(s).toLocaleString('es-BO', { timeZone: 'America/La_Paz', dateStyle: 'short', timeStyle: 'short' }) : ''

/* ---------- etiquetas legibles ---------- */
export const ROLE_LABEL: Record<string, string> = { admin: 'Administrador', caja: 'Caja', produccion: 'Producción', compras: 'Compras' }
export const METHOD_LABEL: Record<string, string> = { promedio: 'Promedio ponderado', ueps: 'UEPS (últimas entradas)', maximo: 'Costo máximo' }
export const MOVE_LABEL: Record<string, string> = {
  compra: 'Compra', consumo: 'Consumo', ajuste: 'Ajuste', anulacion_compra: 'Anulación de compra',
  anulacion_produccion: 'Anulación de producción', produccion: 'Producción', venta: 'Venta',
  anulacion_venta: 'Anulación de venta', gasto: 'Gasto', otro_ingreso: 'Otro ingreso', otro_gasto: 'Otro gasto',
}
export const UNIT_LABEL: Record<string, string> = { g: 'g', ml: 'ml', unidad: 'u' }

/* ---------- avisos ---------- */
type ToastT = { id: number; text: string; kind: 'ok' | 'err' }
let toastListener: ((t: ToastT[]) => void) | null = null
let toasts: ToastT[] = []
export const onToasts = (fn: (t: ToastT[]) => void) => { toastListener = fn }
export function toast(text: string, kind: 'ok' | 'err' = 'ok') {
  const t = { id: Date.now() + Math.random(), text, kind }
  toasts = [...toasts, t]; toastListener?.(toasts)
  setTimeout(() => { toasts = toasts.filter(x => x.id !== t.id); toastListener?.(toasts) }, kind === 'err' ? 6500 : 3000)
}

export function friendly(msg: string) {
  if (/foreign key/i.test(msg)) return 'No se puede eliminar porque ya está en uso. Desactívelo en su lugar.'
  if (/duplicate key|unique/i.test(msg)) return 'Ya existe un registro con ese código o nombre.'
  if (/row-level security|permission denied/i.test(msg)) return 'Tu rol no tiene permiso para esta acción.'
  if (/null value in column "(\w+)"/i.test(msg)) return 'Falta completar un dato obligatorio (' + msg.match(/column "(\w+)"/)![1] + ').'
  if (/Failed to fetch/i.test(msg)) return 'Sin conexión con el servidor. Revisa tu internet.'
  return msg
}

/** Llama una función de la base de datos. Devuelve null si falló (y muestra el error). */
export async function call(fn: string, args: any = {}) {
  const { data, error } = await sb.rpc(fn, args)
  if (error) { toast(friendly(error.message), 'err'); return null }
  return data ?? true
}

/* ---------- lectura de tablas ---------- */
type Opts = { order?: string; asc?: boolean; limit?: number; select?: string; filter?: (q: any) => any; deps?: any[] }
export function useTable<T = any>(table: string, o: Opts = {}) {
  const [rows, setRows] = useState<T[]>([])
  const [loading, setLoading] = useState(true)
  const load = useCallback(async () => {
    setLoading(true)
    let q: any = sb.from(table).select(o.select || '*')
    if (o.filter) q = o.filter(q)
    if (o.order) q = q.order(o.order, { ascending: !!o.asc })
    q = q.limit(o.limit || 1000)
    const { data, error } = await q
    if (error) toast(friendly(error.message), 'err')
    setRows((data as T[]) || []); setLoading(false)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [table, ...(o.deps || [])])
  useEffect(() => { load() }, [load])
  return [rows, load, loading] as const
}

export function useRpc<T = any>(fn: string, args: any, deps: any[] = []) {
  const [data, setData] = useState<T | null>(null)
  const load = useCallback(async () => {
    const { data, error } = await sb.rpc(fn, args)
    if (error) toast(friendly(error.message), 'err'); else setData(data as T)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps)
  useEffect(() => { load() }, [load])
  return [data, load] as const
}

/* ---------- exportar a Excel (CSV) ---------- */
export function exportCSV(name: string, cols: [string, string][], rows: any[]) {
  const esc = (v: any) => { const s = v == null ? '' : String(v); return /[;"\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s }
  const body = [cols.map(c => c[1]).join(';'), ...rows.map(r => cols.map(c => esc(r[c[0]])).join(';'))].join('\n')
  const blob = new Blob(['\ufeff' + body], { type: 'text/csv;charset=utf-8' })
  const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name + '.csv'; a.click()
  setTimeout(() => URL.revokeObjectURL(a.href), 1000)
}

/** Color de cada sabor para las fichas de la caja: [tono, saturación, luminosidad] */
const FLAVORS: [RegExp, [number, number, number]][] = [
  [/frutilla|fresa|frambuesa/i, [345, 70, 72]], [/chocolate|cacao|brownie/i, [22, 38, 42]],
  [/vainilla|crema|nata/i, [44, 75, 82]], [/dulce de leche|caramelo|manjar/i, [32, 62, 60]],
  [/caf[eé]|moka|tiramis/i, [26, 35, 48]], [/lim[oó]n/i, [56, 80, 66]], [/maracuy[aá]|pi[ñn]a/i, [48, 88, 60]],
  [/mango|durazno|naranja|papaya/i, [32, 88, 64]], [/menta|pistacho|kiwi/i, [130, 38, 66]],
  [/uva|mora|ar[aá]ndano|cereza/i, [290, 35, 55]], [/coco|leche|yogur/i, [40, 20, 88]],
  [/canela|galleta|cookie/i, [28, 45, 58]], [/sand[ií]a/i, [355, 72, 66]], [/chirimoya|banana|pl[aá]tano/i, [52, 65, 76]],
]
export function flavorColor(name: string): [number, number, number] {
  for (const [re, c] of FLAVORS) if (re.test(name)) return c
  let h = 0; for (const c of name) h = (h * 31 + c.charCodeAt(0)) % 360
  return [h, 55, 72]
}
