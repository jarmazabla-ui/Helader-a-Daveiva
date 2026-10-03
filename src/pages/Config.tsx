import { useEffect, useState } from 'react'
import { sb } from '../supabase'
import Crud from '../Crud'
import { METHOD_LABEL, friendly, toast, useTable } from '../lib'
import { Field, Page } from '../ui'

export default function Config() {
  const [rows, reload] = useTable('app_settings')
  const [s, setS] = useState<any>(null), [t, setT] = useState('negocio')
  useEffect(() => { if (rows[0]) setS(rows[0]) }, [rows])
  const save = async () => {
    const { id, ...rest } = s
    const { error } = await sb.from('app_settings').update(rest).eq('id', id)
    if (error) toast(friendly(error.message), 'err'); else { toast('Configuración guardada'); reload() }
  }
  return <Page title="Configuración">
    <div className="seg">{[['negocio', 'Negocio'], ['categorias', 'Categorías de gastos e ingresos'], ['pagos', 'Formas de pago']].map(([k, l]) =>
      <button key={k} className={t === k ? 'on' : ''} onClick={() => setT(k)}>{l}</button>)}</div>
    {t === 'negocio' && s && <div className="card">
      <div className="form-grid">
        <Field label="Nombre del negocio (sale en el comprobante)"><input value={s.business_name || ''} onChange={e => setS({ ...s, business_name: e.target.value })} /></Field>
        <Field label="NIT"><input value={s.business_nit || ''} onChange={e => setS({ ...s, business_nit: e.target.value })} /></Field>
        <Field label="Dirección"><input value={s.business_address || ''} onChange={e => setS({ ...s, business_address: e.target.value })} /></Field>
        <Field label="Mensaje al pie del comprobante"><input value={s.ticket_footer || ''} onChange={e => setS({ ...s, ticket_footer: e.target.value })} /></Field>
        <Field label="Método de costeo por defecto en producción"><select value={s.default_costing} onChange={e => setS({ ...s, default_costing: e.target.value })}>
          {Object.entries(METHOD_LABEL).map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></Field>
        <label className="check span"><input type="checkbox" checked={!!s.allow_negative_stock} onChange={e => setS({ ...s, allow_negative_stock: e.target.checked })} />
          Permitir vender o producir sin stock suficiente (no recomendado)</label>
      </div>
      <div className="actions"><button className="btn" onClick={save}>Guardar configuración</button></div>
    </div>}
    {t === 'categorias' && <Crud embedded key="c" table="categories" title="Categorías" order="kind" asc
      sub="El grupo decide dónde aparece en el Estado de resultados: personal y administrativo son gastos operativos; otros va abajo."
      fields={[
        { k: 'kind', l: 'Tipo', required: true, opts: [['gasto', 'Gasto'], ['ingreso', 'Ingreso']] },
        { k: 'name', l: 'Nombre', required: true },
        { k: 'group_name', l: 'Grupo', opts: [['personal', 'Personal'], ['administrativo', 'Administrativo'], ['otros', 'Otros'], ['ventas', 'Ventas']] },
        { k: 'cashier_allowed', l: 'Caja puede usarla', type: 'bool' }]} />}
    {t === 'pagos' && <Crud embedded key="p" table="payment_methods" title="Formas de pago" order="name" asc
      sub="Solo las formas marcadas como efectivo se cuentan en el arqueo del cajón."
      fields={[{ k: 'name', l: 'Nombre', required: true }, { k: 'is_cash', l: 'Es efectivo (va al cajón)', type: 'bool' }, { k: 'active', l: 'Activa', type: 'bool' }]} />}
  </Page>
}
