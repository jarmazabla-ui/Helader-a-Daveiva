import { createClient } from '@supabase/supabase-js'

// Opción A (recomendada en Netlify): variables de entorno VITE_SUPABASE_URL y VITE_SUPABASE_KEY.
// Opción B: pega tus datos aquí abajo (Supabase > Project Settings > API).
const URL_MANUAL = 'PEGA_AQUI_TU_PROJECT_URL'
const KEY_MANUAL = 'PEGA_AQUI_TU_PUBLISHABLE_KEY'

export const SUPABASE_URL: string = import.meta.env.VITE_SUPABASE_URL || URL_MANUAL
export const SUPABASE_KEY: string = import.meta.env.VITE_SUPABASE_KEY || KEY_MANUAL
export const configured = SUPABASE_URL.startsWith('http') && !SUPABASE_KEY.startsWith('PEGA_')

export const sb = createClient(configured ? SUPABASE_URL : 'http://localhost', configured ? SUPABASE_KEY : 'x')
