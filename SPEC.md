# WhatsApp Contador — Especificación del Producto

**Versión:** 2.1
**Fecha:** 15 de mayo de 2026
**Estado:** Diseño aprobado, listo para implementación

**Cambios desde v2.0:**
- Añadido manejo de préstamos como categoría general de deuda
- Eliminada "transferencia bancaria" como forma de pago independiente (ahora todo lo que no es efectivo es "débito")
- Aclarado el diseño defensivo: nivel mínimo, confiamos en el usuario y damos herramientas fáciles de corrección
- Aclarada la diferencia conceptual entre "pago con TDC" (no afecta saldo) y "préstamo" (sí afecta saldo)

---

## 1. Visión

Un bot de WhatsApp que permite a una persona normal llevar el control de sus finanzas personales conversando: registra ingresos, egresos, transferencias entre formas de pago, deudas y préstamos. Los clasifica con categorías que el usuario define y entrega reportes en Excel listos para entregar a un contador o usarse personalmente.

**Frase de elevator pitch:**
> Tu contador personal en WhatsApp. Mándale lo que gastaste, pídele tu Excel del mes.

---

## 2. Público objetivo

- Personas adultas que manejan finanzas personales (no empresariales).
- Usuarios cómodos con WhatsApp pero no necesariamente con apps financieras.
- Usuarios que valoran la consciencia de sus gastos (de ahí que la forma de pago sea obligatoria).
- Mercado inicial: México.

---

## 3. Principios de diseño

1. **Mensajes cortos y claros.** WhatsApp es conversación, no app. Nada de mensajes largos del bot.
2. **El bot conduce la conversación.** Pregunta campo por campo. El usuario no necesita memorizar sintaxis.
3. **El usuario define sus categorías.** No imponemos taxonomías.
4. **Cada teléfono = una cuenta aislada.** Sin compartir cuentas en esta versión.
5. **Consciencia financiera por encima de velocidad.** Forma de pago obligatoria.
6. **El dinero no se "pierde" en crédito.** El crédito es deuda, no gasto inmediato.
7. **Diseño defensivo mínimo.** Confiamos en el usuario. Si se equivoca, usa `/editar` o `/borrar-ultimo`. Solo confirmamos lo irreversible.

---

## 4. Modelo de datos conceptual

### 4.1 Usuario
- Identificado por su número de teléfono de WhatsApp.
- Cada usuario tiene saldos iniciales por forma de pago, definidos al registrarse.
- Aviso de privacidad aceptado al inicio.

### 4.2 Formas de pago
Fijas en el sistema:
- **Efectivo** (billetes y monedas físicas)
- **Débito** (cualquier cuenta bancaria del usuario: tarjeta de débito, cuenta de cheques, cuenta de nómina, transferencias salen de aquí)
- **Crédito** (tarjeta de crédito; caso especial, se trata como deuda)

### 4.3 Movimientos
Cuatro tipos de movimiento:

| Tipo | Qué hace | Afecta saldos |
|---|---|---|
| Ingreso | Suma a una forma de pago | +saldo |
| Egreso | Resta de una forma de pago (o suma a deuda si es crédito) | -saldo o +deuda |
| Transferencia interna | Mueve dinero entre efectivo y débito | Cero efecto en balance neto |
| Préstamo | Suma a una forma de pago Y suma a deuda | +saldo y +deuda |

Cada movimiento guarda:
- Tipo (ingreso, egreso, transferencia, préstamo)
- Monto
- Categoría (texto libre del usuario, solo para ingreso y egreso)
- Forma de pago (origen y destino si es transferencia)
- Fecha (por defecto hoy, modificable con comando)
- Hora de registro
- Descripción opcional
- Referencia a deuda si aplica (préstamo, pago de deuda)
- ID único

### 4.4 Categorías
- Listas separadas por usuario y por tipo (ingreso vs egreso).
- Texto libre, normalizado (minúsculas, sin espacios extra).
- Las transferencias internas y los préstamos no tienen categoría tradicional.

### 4.5 Saldos
El bot calcula saldos en tiempo real a partir de:
- Saldo inicial registrado por el usuario al darse de alta.
- + suma de ingresos.
- - suma de egresos (excepto crédito, que va a deuda).
- ± transferencias internas.
- + monto recibido en préstamos.
- - abonos a deudas.

**Para crédito:** lleva una "deuda acumulada" en lugar de saldo. El pago de tarjeta resta de otra forma de pago y limpia la deuda.

### 4.6 Deudas
Cada deuda guarda:
- Acreedor (a quién se debe: "Banco X", "Coppel", "Mamá", etc.)
- Tipo (tarjeta de crédito o préstamo)
- Monto total a pagar (con intereses incluidos si el usuario los calculó)
- Monto pagado acumulado
- Saldo restante (calculado: total - pagado)
- Fecha de inicio

La deuda de tarjeta de crédito es una sola, revolvente: sube con cada egreso a crédito y baja con cada pago. Los préstamos son fijos: se registran una vez con el monto total, y se abonan con `/pagar-deuda`.

---

## 5. Flujos conversacionales

### 5.1 Registro inicial
```
Bot: 👋 Bienvenido a WhatsApp Contador.
     Antes de empezar, necesito tus saldos actuales.

     ¿Cuánto tienes en EFECTIVO?
     (billetes y monedas físicas, no incluye tarjetas)
Usuario: 1500
Bot: ¿Cuánto en DÉBITO?
     (tu cuenta del banco, tarjeta de débito o nómina)
Usuario: 8000
Bot: ¿Cuánto DEBES en tu tarjeta de crédito?
     (lo que ya gastaste y aún no pagas; 0 si no tienes o no debes)
Usuario: 0
Bot: ¿Tienes otros préstamos o deudas? (sí/no)
Usuario: no
Bot: ✅ Listo. Tus saldos iniciales están registrados.
     Para empezar, escribe "gasto" o "ingreso".
     Para ver comandos: /ayuda
```

Si responde "sí" a la pregunta de otras deudas, entra al flujo de `/prestamo` (sección 5.7).

### 5.2 Registrar un egreso
```
Usuario: gasto
Bot: 💸 Registrar egreso
     ¿Cuánto?
Usuario: 250
Bot: ¿Categoría? (palabra libre)
Usuario: gasolina
Bot: ¿Forma de pago?
     1. Efectivo  2. Débito  3. Crédito
Usuario: 2
Bot: ✅ Egreso de $250 en "gasolina" con débito.
     Saldo débito: $7,750
```

Si paga con crédito (opción 3), el mensaje final es:
```
Bot: ✅ Egreso de $250 en "gasolina" con crédito.
     Deuda crédito: $2,050
```

### 5.3 Registrar un ingreso
```
Usuario: ingreso
Bot: 💰 Registrar ingreso
     ¿Cuánto?
Usuario: 5000
Bot: ¿Categoría? (palabra libre)
Usuario: sueldo
Bot: ¿A qué forma de pago entra?
     1. Efectivo  2. Débito
Usuario: 2
Bot: ✅ Ingreso de $5,000 en "sueldo" a débito.
     Saldo débito: $12,750
```

### 5.4 Transferencia entre formas de pago
```
Usuario: /transferir
Bot: ¿De dónde sale el dinero?
     1. Efectivo  2. Débito
Usuario: 2
Bot: ¿A dónde entra?
     1. Efectivo
Usuario: 1
Bot: ¿Cuánto?
Usuario: 500
Bot: ✅ Transferiste $500 de débito a efectivo.
     Débito: $12,250 | Efectivo: $2,000
```

### 5.5 Pago de tarjeta de crédito
```
Usuario: /pagar-tarjeta
Bot: Deuda actual de crédito: $2,050
     ¿Cuánto vas a pagar?
Usuario: 2050
Bot: ¿De qué forma de pago sale?
     1. Efectivo  2. Débito
Usuario: 2
Bot: ✅ Pagaste $2,050 de crédito desde débito.
     Débito: $10,200 | Deuda crédito: $0
```

### 5.6 Registro retroactivo
```
Usuario: /gasto-retroactivo
Bot: ¿De qué fecha? (formato dd/mm/aaaa)
Usuario: 10/05/2026
Bot: 💸 Egreso para 10 mayo 2026
     ¿Cuánto?
... (resto del flujo igual)
```

### 5.7 Registrar un préstamo
```
Usuario: /prestamo
Bot: 🏦 Registrar préstamo o deuda nueva
     ¿Quién te prestó? (banco, Coppel, persona, etc.)
Usuario: nu
Bot: ¿Cuánto te llegó?
Usuario: 5000
Bot: ¿A qué forma de pago entró?
     1. Efectivo  2. Débito
Usuario: 2
Bot: ¿Cuánto debes en total? (con intereses si los hay)
Usuario: 6500
Bot: ✅ Préstamo de "Nu" registrado.
     Te llegó: $5,000 a débito
     Total que debes: $6,500
     Saldo débito: $15,200
```

### 5.8 Pagar un préstamo o deuda
```
Usuario: /pagar-deuda
Bot: ¿Cuál deuda?
     1. Tarjeta de crédito - debes $2,050
     2. Nu - debes $6,500
Usuario: 2
Bot: ¿Cuánto vas a abonar?
Usuario: 500
Bot: ¿De qué forma de pago sale?
     1. Efectivo  2. Débito
Usuario: 2
Bot: ✅ Abonaste $500 a "Nu".
     Débito: $14,700 | Deuda Nu: $6,000
```

### 5.9 Editar movimiento
```
Usuario: /editar
Bot: ¿Qué mes? (mm/aaaa o "actual")
Usuario: actual
Bot: Últimos 5 movimientos:
     1. 15/05 14:30 - Egreso $250 gasolina (débito)
     2. 15/05 12:15 - Egreso $80 café (efectivo)
     ...
     Escribe el número, o "más" para ver más.
Usuario: 2
Bot: Editando: Egreso $80 café (efectivo)
     ¿Qué cambias?
     1. Monto  2. Categoría  3. Forma de pago  4. Fecha
Usuario: 1
Bot: Nuevo monto:
Usuario: 120
Bot: ✅ Actualizado. Egreso ahora es $120.
     Saldo recalculado.
```

### 5.10 Borrar último movimiento
```
Usuario: /borrar-ultimo
Bot: Último movimiento: Egreso $250 gasolina (débito) 14:30
     ¿Confirmas borrar? (sí/no)
Usuario: sí
Bot: ✅ Borrado. Saldo recalculado.
```

---

## 6. Comandos

### 6.1 Comandos de registro
| Comando | Función |
|---|---|
| `gasto` o `egreso` | Registrar un egreso (hoy) |
| `ingreso` | Registrar un ingreso (hoy) |
| `/gasto-retroactivo` | Registrar egreso de otra fecha |
| `/ingreso-retroactivo` | Registrar ingreso de otra fecha |
| `/transferir` | Mover dinero entre efectivo y débito |
| `/pagar-tarjeta` | Pagar deuda de tarjeta de crédito |
| `/prestamo` | Registrar un préstamo nuevo |
| `/pagar-deuda` | Abonar a una deuda (TDC o préstamo) |

### 6.2 Comandos de información
| Comando | Función |
|---|---|
| `/saldo` | Saldo actual por forma de pago + deudas |
| `/deudas` | Detalle de todas las deudas activas |
| `/resumen` | Resumen financiero del mes actual |
| `/resumen mm/aaaa` | Resumen financiero de un mes específico |
| `/resumen aaaa` | Resumen anual |
| `/ultimos` | Últimos 5 movimientos |
| `/categorias` | Lista de categorías que has usado, con totales |

### 6.3 Comandos de gestión
| Comando | Función |
|---|---|
| `/editar` | Editar un movimiento (cualquier mes) |
| `/borrar-ultimo` | Borrar el último movimiento con confirmación |
| `/excel` | Excel del mes actual |
| `/excel mm/aaaa` | Excel de un mes específico |
| `/excel aaaa` | Excel anual |

### 6.4 Comandos de sistema
| Comando | Función |
|---|---|
| `/start` | Inicia o reinicia el registro |
| `/ayuda` | Muestra todos los comandos |
| `/privacidad` | Muestra el aviso de privacidad |
| `/borrar-cuenta` | Elimina todos los datos del usuario (con confirmación) |
| `/cancelar` | Cancela el flujo en curso |

---

## 7. Información financiera (las 8 métricas)

El comando `/resumen` devuelve un mensaje con:

1. **Ingresos totales del periodo** (mes o año)
2. **Egresos totales del periodo**
3. **Balance del periodo** (ingresos − egresos)
4. **Saldo actual por forma de pago** (efectivo, débito) + deudas (crédito + préstamos)
5. **Últimos 5 movimientos** del periodo
6. **Egresos agrupados por categoría**, ordenados de mayor a menor
7. **Promedio diario de gasto** del periodo
8. **Comparación con el periodo anterior** (mes anterior si es resumen mensual, año anterior si es anual). Si no hay periodo anterior, se omite esa línea.

### Formato del resumen mensual
```
📊 Resumen de mayo 2026

💰 Ingresos: $12,500
💸 Egresos: $8,340
✅ Balance: +$4,160

📍 Saldos actuales:
  Efectivo: $1,200
  Débito: $9,400
  Deuda crédito: $1,800
  Deudas: $6,000 (Nu)

🏷️ Top categorías de gasto:
  1. Comida: $2,800
  2. Gasolina: $1,500
  3. Renta: $3,000
  ...

📈 Promedio diario: $278
🔁 vs abril: -8% en egresos
```

---

## 8. Generación de Excel

### 8.1 Formato del Excel mensual
- Hoja 1: **Resumen** (los 8 indicadores en formato tabla)
- Hoja 2: **Ingresos** (tabla completa: fecha, categoría, monto, forma de pago, descripción)
- Hoja 3: **Egresos** (tabla completa)
- Hoja 4: **Transferencias internas** (origen, destino, monto, fecha)
- Hoja 5: **Préstamos y pagos de deuda** (tipo, acreedor, monto, fecha, forma de pago)
- Hoja 6: **Por categoría** (totales agrupados con %)

### 8.2 Formato del Excel anual
- Hoja 1: **Resumen anual** + totales por mes
- Hoja 2: **Ingresos del año**
- Hoja 3: **Egresos del año**
- Hoja 4: **Transferencias del año**
- Hoja 5: **Préstamos y pagos del año**
- Hoja 6: **Por categoría (año)** con desglose mensual
- Hoja 7: **Comparativos mensuales** (tabla 12 meses × categorías)

### 8.3 Entrega
- Archivo enviado como documento adjunto por WhatsApp.
- Nombre del archivo: `contador_[usuario]_[mes-aaaa].xlsx` o `contador_[usuario]_[aaaa].xlsx`.

---

## 9. Stack técnico

| Componente | Tecnología |
|---|---|
| Lenguaje | Python 3.11+ |
| Framework web | FastAPI |
| ORM | SQLAlchemy |
| Base de datos | PostgreSQL (producción), SQLite (desarrollo local) |
| Mensajería | WhatsApp Cloud API (Meta) |
| Excel | openpyxl |
| Variables de entorno | python-dotenv |
| Hosting (sugerido) | Railway o Render |
| Base de datos gestionada | Supabase o el Postgres del hosting |
| Control de versiones | Git + GitHub |

---

## 10. Seguridad y privacidad

### 10.1 Medidas obligatorias del MVP
- **HTTPS** en todos los endpoints (requerido por Meta).
- **Variables de entorno** para todos los secretos. Archivo `.env` en `.gitignore`.
- **Base de datos cifrada en reposo**, con backups automáticos diarios (incluido en servicios gestionados como Railway o Supabase).
- **Logs sin datos sensibles**: no se loguean montos, categorías ni descripciones. Solo IDs y tipos de evento.
- **Comando `/borrar-cuenta`** que elimina permanentemente todos los datos del usuario.
- **Aviso de privacidad** accesible vía `/privacidad`, mostrado obligatoriamente al registrarse.

### 10.2 No incluido en esta versión
- PIN de acceso (queda para futura versión).
- Cifrado de campos a nivel aplicación (queda para futura versión).
- Cuentas compartidas (queda para futura versión).

### 10.3 Cumplimiento legal
Operación en México obliga a cumplir con la Ley Federal de Protección de Datos Personales en Posesión de los Particulares (LFPDPPP):
- Aviso de privacidad visible y aceptado.
- Derecho del usuario a acceder, rectificar, cancelar y oponerse (ARCO) cubierto por los comandos `/editar`, `/borrar-ultimo`, `/borrar-cuenta`, `/excel`.

---

## 11. Reglas de negocio importantes

1. **Cero efecto neto en transferencias internas y pagos de deuda:** estas operaciones no aparecen como ingreso ni egreso en los totales del resumen.
2. **El crédito acumula deuda, no resta saldo:** cuando registras un egreso con crédito, no baja ningún saldo, sube la deuda de crédito.
3. **Un préstamo es ingreso Y deuda al mismo tiempo:** cuando registras un préstamo, sube tu saldo de débito (o efectivo) Y sube tu deuda total. En el resumen mensual, **el préstamo NO cuenta como ingreso** (no es dinero ganado, es dinero prestado). Aparece en su propia sección.
4. **Editar un movimiento recalcula saldos desde esa fecha:** el sistema debe poder recalcular saldos cuando se edita o borra un movimiento, sin importar el mes.
5. **Categorías normalizadas:** "Gasolina", "gasolina ", "GASOLINA" se tratan como la misma categoría (minúsculas + trim).
6. **Una conversación a la vez:** mientras el usuario está en medio de un flujo, un mensaje suelto se interpreta como respuesta a la pregunta actual. El comando `/cancelar` aborta el flujo.
7. **Cero pesos no se rechazan:** si el usuario quiere registrar $0 (caso raro), se permite sin preguntar.
8. **Confirmaciones solo en lo irreversible:** únicamente `/borrar-ultimo`, `/borrar-cuenta` y operaciones similares piden confirmación. El resto se ejecuta directo.

---

## 12. Manejo de errores humanos (nivel mínimo)

Según el principio 7 (diseño defensivo mínimo), el bot:

**Sí valida:**
- Que el monto sea numérico (acepta formato libre: "2500", "2,500", "$2,500", "2500.00"). Si no es parseable, repregunta.
- Que la opción seleccionada en menús numerados sea válida (1-3, etc.). Si no, repregunta.
- Que el formato de fecha sea correcto en flujos retroactivos. Si no, repregunta con ejemplo.

**No valida:**
- Que los montos sean "razonables" (no hay umbrales de "demasiado alto").
- Que los saldos iniciales sean consistentes con otros datos.
- Que el usuario no esté registrando duplicados (lo verá en `/ultimos` y puede usar `/borrar-ultimo`).

**Confirma solo en:**
- `/borrar-ultimo`
- `/borrar-cuenta`

**Ignora:**
- Mensajes de tipo audio, foto, sticker, video, ubicación → responde "Solo entiendo texto. Escribe /ayuda."
- Mensajes fuera del flujo conversacional cuando el bot espera respuesta de campo específico → repregunta el campo.

**Recuperación de errores del usuario:**
- `/editar` permite cambiar cualquier movimiento de cualquier mes.
- `/borrar-ultimo` deshace rápido el último error.
- `/cancelar` aborta un flujo en curso sin guardar nada.

---

## 13. Fuera del alcance de esta versión

Lo siguiente NO se implementa ahora, pero queda documentado para versiones futuras:

- PDF como alternativa al Excel
- PIN o autenticación adicional
- Cifrado de campos sensibles
- Cuentas compartidas (parejas, familias)
- OCR de tickets fotografiados
- Integración con cuentas bancarias reales
- Presupuestos / metas / alertas
- Inversiones y activos
- Múltiples monedas
- Recurrencias automáticas (sueldo mensual, suscripciones)
- Dashboard web complementario
- Notificaciones proactivas del bot
- Modo familia / múltiples cuentas por usuario
- Seguimiento de plazos e intereses de préstamos
- Validaciones inteligentes (montos sospechosos, etc.)

---

## 14. Criterios de éxito del MVP

El MVP se considera funcional y listo cuando:

1. Un usuario nuevo puede registrarse y dejar sus saldos iniciales en menos de 2 minutos.
2. Registrar un egreso típico toma 4 mensajes o menos.
3. El comando `/saldo` responde en menos de 3 segundos.
4. El comando `/excel` genera y envía un archivo en menos de 10 segundos.
5. Editar un movimiento de cualquier mes ajusta saldos correctamente (verificable con pruebas).
6. 3 usuarios reales (familia/amigos) lo usan durante 2 semanas seguidas sin reportar bugs bloqueantes.
7. El bot no pierde mensajes ni duplica registros bajo uso normal.
8. El comando `/borrar-cuenta` elimina efectivamente todos los datos.
9. Los préstamos y pagos de deuda se reflejan correctamente en saldos y reportes.

---

## 15. Glosario

- **MVP:** Minimum Viable Product. Versión mínima funcional del producto.
- **Webhook:** URL pública donde un servicio externo (WhatsApp) envía eventos a tu servidor.
- **Forma de pago:** medio del dinero (efectivo, débito, crédito).
- **Movimiento:** cualquier registro financiero en el sistema (ingreso, egreso, transferencia, préstamo).
- **Categoría:** etiqueta libre que el usuario asigna a un ingreso o egreso.
- **Periodo:** lapso de tiempo para reportes (mensual o anual).
- **Saldo:** dinero disponible actualmente en una forma de pago.
- **Deuda:** monto pendiente de pago (tarjeta de crédito o préstamo).
- **Transferencia interna:** movimiento de dinero entre efectivo y débito del mismo usuario (no es ingreso ni egreso).
- **Préstamo:** dinero recibido que genera una deuda. Sube saldo Y deuda al mismo tiempo. No es un ingreso real.
- **Pago de deuda:** abono a una deuda existente. Resta de una forma de pago y reduce la deuda. No es un egreso real.

---

*Documento vivo. Cualquier cambio sustancial al alcance debe versionarse (v2.2, v3.0, etc.) y registrar fecha y motivo.*
