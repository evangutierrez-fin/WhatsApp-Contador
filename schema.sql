-- ============================================================================
-- WhatsApp Contador — Esquema de Base de Datos
-- Versión: 1.0
-- Fecha: 16 de mayo de 2026
-- ============================================================================
-- 
-- Este archivo define la estructura de la base de datos del bot.
-- Está escrito para PostgreSQL, pero SQLAlchemy lo traduce automáticamente
-- a SQLite para desarrollo local.
--
-- Convenciones:
-- - IDs en formato UUID (no autoincremental)
-- - Soft delete vía columna 'deleted_at' (NULL = no borrado)
-- - Timestamps en UTC, conversión a zona horaria local en la app
-- - Montos en DECIMAL(12,2) — soporta hasta $9,999,999,999.99
-- - Nombres de tablas en plural, en español
-- ============================================================================


-- ============================================================================
-- TABLA: usuarios
-- ----------------------------------------------------------------------------
-- Cada usuario está identificado por su número de teléfono de WhatsApp.
-- Un usuario nuevo se crea al recibir su primer mensaje.
-- ============================================================================
CREATE TABLE usuarios (
    -- Identificador único del usuario
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Número de WhatsApp (formato internacional: +521234567890)
    -- UNIQUE: no puede haber dos usuarios con el mismo número
    telefono            VARCHAR(20) NOT NULL UNIQUE,
    
    -- Nombre del usuario (opcional, lo puede dar el usuario o WhatsApp)
    nombre              VARCHAR(100),
    
    -- Estado del usuario en su flujo conversacional actual
    -- Usado por la máquina de estados conversacional
    -- Ejemplos: 'esperando_comando', 'capturando_monto', 'capturando_categoria'
    estado_actual       VARCHAR(50) DEFAULT 'esperando_comando',
    
    -- Datos temporales del flujo en curso (formato JSON)
    -- Ejemplo: {"tipo": "egreso", "monto": 250, "categoria": "gasolina"}
    -- Se limpia cuando el flujo termina o se cancela
    contexto_flujo      JSONB DEFAULT '{}',
    
    -- ¿Aceptó el aviso de privacidad?
    privacidad_aceptada BOOLEAN DEFAULT FALSE,
    fecha_aceptacion    TIMESTAMP,
    
    -- Auditoría
    created_at          TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMP  -- NULL = activo, fecha = borrado
);

-- Índice para búsquedas rápidas por teléfono (el bot lo usa en cada mensaje)
CREATE INDEX idx_usuarios_telefono ON usuarios(telefono);


-- ============================================================================
-- TABLA: saldos_iniciales
-- ----------------------------------------------------------------------------
-- Captura los saldos que el usuario reporta al registrarse.
-- NO se modifica después. Para ajustes posteriores se usa 'movimientos'.
-- Esto da trazabilidad: siempre sabemos cuánto declaró al inicio.
-- ============================================================================
CREATE TABLE saldos_iniciales (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- A qué usuario pertenecen
    usuario_id      UUID NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    
    -- Saldos por forma de pago
    -- DECIMAL(12,2) maneja dinero sin errores de precisión
    efectivo        DECIMAL(12,2) NOT NULL DEFAULT 0,
    debito          DECIMAL(12,2) NOT NULL DEFAULT 0,
    deuda_credito   DECIMAL(12,2) NOT NULL DEFAULT 0,
    
    -- Cuándo se registró
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    
    -- Restricción: solo puede haber UN saldo inicial por usuario
    UNIQUE(usuario_id)
);


-- ============================================================================
-- TABLA: categorias
-- ----------------------------------------------------------------------------
-- Categorías que el usuario va creando con su uso.
-- Texto libre, normalizadas (minúsculas, sin espacios extra).
-- Separadas por tipo: las de ingreso y egreso son listas distintas.
-- ============================================================================
CREATE TABLE categorias (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id      UUID NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    
    -- Tipo: 'ingreso' o 'egreso'
    tipo            VARCHAR(10) NOT NULL CHECK (tipo IN ('ingreso', 'egreso')),
    
    -- Nombre normalizado (lo que se usa para comparar)
    -- Ejemplo: "gasolina"
    nombre          VARCHAR(50) NOT NULL,
    
    -- Nombre original como lo escribió el usuario (para mostrarlo bonito)
    -- Ejemplo: "Gasolina"
    nombre_original VARCHAR(50) NOT NULL,
    
    -- Auditoría
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    
    -- Una categoría es única por usuario+tipo+nombre
    -- (un usuario no puede tener dos categorías "gasolina" de egreso)
    UNIQUE(usuario_id, tipo, nombre)
);

CREATE INDEX idx_categorias_usuario ON categorias(usuario_id);


-- ============================================================================
-- TABLA: deudas
-- ----------------------------------------------------------------------------
-- Una deuda por cada préstamo + una deuda especial para tarjeta de crédito.
-- La de TDC es 'revolvente': sube con cada egreso a crédito, baja con pagos.
-- Los préstamos son 'fijos': se crean una vez con el monto total.
-- ============================================================================
CREATE TABLE deudas (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id      UUID NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    
    -- Tipo: 'tarjeta_credito' o 'prestamo'
    tipo            VARCHAR(20) NOT NULL CHECK (tipo IN ('tarjeta_credito', 'prestamo')),
    
    -- A quién se le debe
    -- Para TDC: "Tarjeta de crédito" o nombre del banco
    -- Para préstamo: lo que ponga el usuario ("Nu", "Coppel", "Mamá")
    acreedor        VARCHAR(100) NOT NULL,
    
    -- Monto total que se debe pagar
    -- Para TDC: arranca en 0 y crece con cada egreso a crédito
    -- Para préstamo: arranca con el monto total con intereses
    monto_total     DECIMAL(12,2) NOT NULL DEFAULT 0,
    
    -- Cuánto se ha pagado acumulado
    monto_pagado    DECIMAL(12,2) NOT NULL DEFAULT 0,
    
    -- Estado: 'activa' o 'pagada'
    estado          VARCHAR(20) NOT NULL DEFAULT 'activa' 
                    CHECK (estado IN ('activa', 'pagada')),
    
    -- Auditoría
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP
);

CREATE INDEX idx_deudas_usuario ON deudas(usuario_id);
CREATE INDEX idx_deudas_usuario_estado ON deudas(usuario_id, estado);


-- ============================================================================
-- TABLA: movimientos
-- ----------------------------------------------------------------------------
-- El corazón del sistema. Cada acción financiera del usuario es un movimiento.
-- Cuatro tipos: ingreso, egreso, transferencia interna, préstamo.
-- También guardamos pagos de deuda como tipo 'pago_deuda'.
-- ============================================================================
CREATE TABLE movimientos (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id          UUID NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    
    -- Tipo de movimiento
    -- ingreso: suma a una forma de pago
    -- egreso: resta de forma de pago (o suma a deuda si es crédito)
    -- transferencia: mueve entre efectivo y débito
    -- prestamo: suma a una forma de pago + crea/aumenta deuda
    -- pago_deuda: resta de forma de pago + reduce deuda
    tipo                VARCHAR(20) NOT NULL 
                        CHECK (tipo IN ('ingreso', 'egreso', 'transferencia', 'prestamo', 'pago_deuda')),
    
    -- Monto del movimiento
    monto               DECIMAL(12,2) NOT NULL,
    
    -- Categoría (solo para ingreso y egreso)
    -- NULL para transferencia, préstamo y pago_deuda
    categoria_id        UUID REFERENCES categorias(id),
    
    -- Forma de pago origen
    -- Para ingreso: a dónde entra (efectivo, debito)
    -- Para egreso: de dónde sale (efectivo, debito, credito)
    -- Para transferencia: de dónde sale (efectivo, debito)
    -- Para préstamo: a dónde entra (efectivo, debito)
    -- Para pago_deuda: de dónde sale (efectivo, debito)
    forma_pago_origen   VARCHAR(20) NOT NULL 
                        CHECK (forma_pago_origen IN ('efectivo', 'debito', 'credito')),
    
    -- Forma de pago destino (solo para transferencia)
    forma_pago_destino  VARCHAR(20) 
                        CHECK (forma_pago_destino IS NULL OR 
                               forma_pago_destino IN ('efectivo', 'debito')),
    
    -- Referencia a deuda (solo para prestamo y pago_deuda)
    deuda_id            UUID REFERENCES deudas(id),
    
    -- Fecha contable del movimiento (puede ser retroactiva)
    fecha               DATE NOT NULL DEFAULT CURRENT_DATE,
    
    -- Descripción opcional libre
    descripcion         TEXT,
    
    -- Auditoría
    created_at          TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMP,  -- soft delete
    
    -- Validación: monto siempre positivo
    CHECK (monto >= 0)
);

-- Índices: los movimientos se consultan muy seguido por usuario y por fecha
CREATE INDEX idx_movimientos_usuario ON movimientos(usuario_id);
CREATE INDEX idx_movimientos_usuario_fecha ON movimientos(usuario_id, fecha);
CREATE INDEX idx_movimientos_usuario_tipo ON movimientos(usuario_id, tipo);
CREATE INDEX idx_movimientos_categoria ON movimientos(categoria_id);


-- ============================================================================
-- TABLA: mensajes_log
-- ----------------------------------------------------------------------------
-- Bitácora de eventos importantes. Útil para debugging.
-- NO guarda contenido sensible (montos, categorías). Solo IDs y tipos.
-- Cumple con el principio de "logs sin datos sensibles" del SPEC.
-- ============================================================================
CREATE TABLE mensajes_log (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id      UUID REFERENCES usuarios(id) ON DELETE CASCADE,
    
    -- Tipo de evento
    -- Ejemplos: 'mensaje_recibido', 'mensaje_enviado', 'comando_ejecutado',
    --           'movimiento_creado', 'movimiento_editado', 'error'
    tipo_evento     VARCHAR(50) NOT NULL,
    
    -- Detalles NO sensibles (formato JSON)
    -- Ejemplo: {"comando": "saldo", "estado_previo": "esperando_comando"}
    -- PROHIBIDO: guardar montos, categorías, descripciones, números de teléfono
    detalles        JSONB DEFAULT '{}',
    
    -- Timestamp del evento
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_mensajes_log_usuario ON mensajes_log(usuario_id);
CREATE INDEX idx_mensajes_log_fecha ON mensajes_log(created_at);


-- ============================================================================
-- TABLA: avisos_privacidad
-- ----------------------------------------------------------------------------
-- Versiones del aviso de privacidad. Cuando se actualiza, los usuarios 
-- deben aceptar la nueva versión.
-- ============================================================================
CREATE TABLE avisos_privacidad (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Número de versión: "1.0", "1.1", "2.0"
    version         VARCHAR(10) NOT NULL UNIQUE,
    
    -- Texto completo del aviso
    contenido       TEXT NOT NULL,
    
    -- ¿Esta es la versión vigente?
    vigente         BOOLEAN NOT NULL DEFAULT FALSE,
    
    -- Fechas
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    fecha_vigencia  DATE NOT NULL
);

-- Solo puede haber UN aviso vigente a la vez
CREATE UNIQUE INDEX idx_aviso_vigente ON avisos_privacidad(vigente) WHERE vigente = TRUE;


-- ============================================================================
-- NOTAS DE IMPLEMENTACIÓN PARA CLAUDE CODE
-- ============================================================================
-- 
-- 1. Para SQLite (desarrollo local):
--    - 'gen_random_uuid()' no existe en SQLite. Usar Python uuid4() y pasar como string.
--    - JSONB se convierte automáticamente a TEXT por SQLAlchemy.
--    - NOW() se traduce a CURRENT_TIMESTAMP.
--
-- 2. SQLAlchemy generará estas tablas a partir de modelos en /app/models/.
--    No correr este SQL directamente; usar migraciones con Alembic.
--
-- 3. El cálculo de saldos NO se guarda en la DB. Se calcula bajo demanda:
--    saldo_efectivo = saldo_inicial.efectivo
--                   + SUM(ingresos efectivo) 
--                   - SUM(egresos efectivo)
--                   + SUM(transferencias entrantes a efectivo)
--                   - SUM(transferencias salientes de efectivo)
--                   + SUM(prestamos a efectivo)
--                   - SUM(pagos_deuda desde efectivo)
--    
--    Si esto se vuelve lento (>1000 movimientos por usuario), considerar
--    una tabla 'saldos_cache' que se actualiza por trigger o evento.
--
-- 4. El comando '/borrar-cuenta' debe hacer DELETE real (no soft delete)
--    para cumplir con LFPDPPP. Usar 'ON DELETE CASCADE' borra todo
--    automáticamente al borrar el usuario.
--
-- 5. Los movimientos editados deben recalcular saldos desde la fecha del
--    movimiento hacia adelante. La lógica vive en la capa de servicio.
