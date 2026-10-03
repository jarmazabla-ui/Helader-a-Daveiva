# Heladería · Sistema de gestión

Sistema web para una fábrica y tienda de helados. Cubre compras de insumos, recetas, producción con costeo, caja (punto de venta), gastos, arqueo y cierre diario, inventario con kárdex y reportes financieros.

Stack: React + Vite + TypeScript, Supabase (base de datos, usuarios y seguridad) y Netlify (publicación).

---

## 1. Instalar la base de datos (Supabase)

1. Crea un proyecto en https://supabase.com.
2. Entra a **SQL Editor** y ejecuta los scripts de la carpeta `sql/`.

**Si es una instalación nueva**, ejecuta un solo archivo:

| Orden | Archivo | Para qué |
|---|---|---|
| 1 | `0_INSTALAR_TODO.sql` | Crea todo el sistema |
| 2 | `5_datos_demo_opcional.sql` | (Opcional) Sabores, recetas y envases de ejemplo |

**Si ya habías ejecutado las partes 1, 2 y 3**, ejecuta solo `4_completar_sistema.sql`. Corrige errores y agrega las funciones nuevas sin borrar tus datos. Se puede ejecutar más de una vez.

3. Crea tu usuario: **Authentication › Users › Add user** (marca "Auto confirm user").
4. Conviértete en administrador. En el SQL Editor ejecuta, cambiando el correo:

```sql
update profiles set role='admin', active=true, full_name='Tu Nombre'
where email = 'TU_CORREO@ejemplo.com';
```

> Para que tu personal pueda crear su cuenta desde la pantalla de ingreso ("Solicitar acceso"), en **Authentication › Sign In / Providers › Email** puedes desactivar "Confirm email". Si lo dejas activo, recibirán un correo de confirmación. En ambos casos la cuenta queda inactiva hasta que tú le asignes un rol en **Usuarios**.

## 2. Conectar la app con Supabase

En Supabase: **Project Settings › API** copia el **Project URL** y la **Publishable key** (o "anon public").

- **En Netlify (recomendado):** Site configuration › Environment variables, crea
  `VITE_SUPABASE_URL` y `VITE_SUPABASE_KEY`.
- **O directo en el código:** pégalos en `src/supabase.ts`.

## 3. Publicar en Netlify

Sube esta carpeta a GitHub e importa el repositorio en Netlify. La configuración ya está en `netlify.toml` (comando `npm run build`, carpeta `dist`).

Para probar en tu computadora o VPS:

```bash
npm install
npm run dev
```

## 4. Primeros pasos dentro del sistema (administrador)

1. **Configuración › Negocio:** nombre, NIT y dirección (salen en el comprobante) y método de costeo por defecto.
2. **Insumos:** materia prima, envases, tapas y etiquetas, con su unidad base (g, ml o unidades).
3. **Productos y precios:** sabores, presentaciones (con su volumen en ml), precios de venta y qué envases lleva cada presentación.
4. **Recetas:** para cada sabor, cuántos litros rinde y qué insumos usa.
5. **Inventario inicial:** en **Inventario y ajustes**, haz una "Entrada" por cada insumo con su valor total. O registra una **Compra**.
6. **Producción:** registra cuántos potes o baldes salieron. El sistema descuenta la receta y los envases.
7. **Caja:** ya puedes vender.

## 5. Roles

| Rol | Puede |
|---|---|
| Administrador | Todo, incluido reabrir días cerrados, ajustes y reportes |
| Caja | Vender, gastos autorizados, ver sus ventas, cerrar la caja del día. No ve costos. Solo registra con la fecha de hoy |
| Producción | Registrar y anular órdenes de producción |
| Compras | Compras, proveedores y kárdex de insumos |

## 6. Cómo funciona el costeo

- **Compras:** cada compra recalcula el costo promedio ponderado del insumo y guarda una "capa" de costo.
- **Producción:** el costo del helado se calcula con uno de tres métodos.
  - **Promedio ponderado:** usa el costo promedio actual del insumo.
  - **UEPS:** consume primero las compras más recientes.
  - **Costo máximo:** usa el precio más alto pagado.
- **Costo por unidad:** el costo del contenido se reparte según el volumen de cada presentación, y se le suma su propio envase.
- **Ventas:** congelan el costo del helado en el momento de la venta. Así el estado de resultados no cambia si después varían los costos.
- **Mermas:** los ajustes de insumos y de helado terminado aparecen como mermas en el estado de resultados.

## 7. Reglas de seguridad

- Toda operación que mueve stock o dinero (compra, producción, venta, gasto, anulación, cierre) se ejecuta en una sola transacción dentro de la base de datos. Si algo falla, no se guarda nada a medias.
- Las anulaciones exigen motivo y quedan en **Auditoría**.
- No se puede anular una compra cuyos insumos ya se usaron, ni una producción cuyos helados ya se vendieron.
- Un día cerrado no acepta movimientos hasta que el administrador lo reabra.
- El sistema impide desactivar o cambiar el rol del último administrador activo.

## Estructura

```
sql/                 Scripts de base de datos
src/App.tsx          Ingreso, menú por rol y navegación
src/lib.ts           Utilidades (formato Bs, fechas Bolivia, avisos, exportar a Excel)
src/ui.tsx           Componentes comunes (ventanas, campos, indicadores)
src/Crud.tsx         Tabla genérica con alta, edición, búsqueda y exportación
src/Ticket.tsx       Comprobante imprimible (58/80 mm)
src/pages/           Una pantalla por módulo
```
