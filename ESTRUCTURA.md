# Estructura del Proyecto

Notas sobre cómo organizo el código de WhatsApp Contador.

---

## Árbol de carpetas

```
whatsapp-contador/
│
├── README.md
├── SPEC.md
├── schema.sql
├── ESTRUCTURA.md
│
├── .gitignore
├── .env.example
├── .env
│
├── requirements.txt
├── pyproject.toml
│
├── app/
│   ├── __init__.py
│   │
│   ├── main.py                  # arranca FastAPI
│   ├── config.py                # lee variables de entorno
│   │
│   ├── api/
│   │   ├── __init__.py
│   │   ├── webhook.py           # recibe mensajes de WhatsApp
│   │   └── health.py            # endpoint /health
│   │
│   ├── bot/
│   │   ├── __init__.py
│   │   ├── router.py            # decide qué handler ejecutar
│   │   ├── state_machine.py     # máquina de estados conversacional
│   │   ├── messages.py          # plantillas de mensajes del bot
│   │   │
│   │   └── handlers/
│   │       ├── __init__.py
│   │       ├── registro.py
│   │       ├── egreso.py
│   │       ├── ingreso.py
│   │       ├── transferencia.py
│   │       ├── prestamo.py
│   │       ├── pago_deuda.py
│   │       ├── pago_tarjeta.py
│   │       ├── editar.py
│   │       ├── borrar.py
│   │       ├── consultas.py     # /saldo, /resumen, /ultimos
│   │       └── sistema.py       # /ayuda, /privacidad, /cancelar
│   │
│   ├── services/
│   │   ├── __init__.py
│   │   ├── usuarios.py
│   │   ├── movimientos.py
│   │   ├── categorias.py
│   │   ├── deudas.py
│   │   ├── saldos.py
│   │   ├── resumen.py
│   │   └── exportador.py        # generación de Excel
│   │
│   ├── models/
│   │   ├── __init__.py
│   │   ├── base.py
│   │   ├── usuario.py
│   │   ├── saldo_inicial.py
│   │   ├── categoria.py
│   │   ├── movimiento.py
│   │   ├── deuda.py
│   │   ├── mensaje_log.py
│   │   └── aviso_privacidad.py
│   │
│   ├── integrations/
│   │   ├── __init__.py
│   │   └── whatsapp.py
│   │
│   ├── db/
│   │   ├── __init__.py
│   │   ├── session.py
│   │   └── migrations/
│   │
│   └── utils/
│       ├── __init__.py
│       ├── parseo.py
│       ├── logger.py
│       └── normalizacion.py
│
├── tests/
│   ├── __init__.py
│   ├── conftest.py
│   ├── test_services/
│   │   ├── test_saldos.py
│   │   ├── test_movimientos.py
│   │   └── test_resumen.py
│   └── test_bot/
│       ├── test_handlers.py
│       └── test_state_machine.py
│
├── scripts/
│   ├── inicializar_db.py
│   └── crear_aviso_privacidad.py
│
└── docs/
    ├── arquitectura.md
    ├── comandos.md
    └── deployment.md
```

---

## Las capas

Organicé el proyecto en capas para que no se mezcle todo en un solo lado.

### `app/api/`

La puerta de entrada. WhatsApp manda POST aquí cuando un usuario escribe. El endpoint valida que el mensaje viene de WhatsApp y se lo pasa al router. Nada de lógica de negocio en esta capa.

### `app/bot/`

El cerebro conversacional.

- `router.py` recibe el mensaje, mira el estado del usuario, y decide qué handler usar.
- `state_machine.py` define las transiciones entre estados (monto → categoría → forma de pago, etc.).
- `messages.py` centraliza los textos del bot. Cambiar el tono toca solo este archivo.
- `handlers/` un archivo por flujo. Separados aunque sean parecidos, así es más fácil encontrar cosas.

### `app/services/`

Las reglas del negocio. Cómo se calcula un saldo, cómo se valida un movimiento, cómo se arma el resumen mensual. Esta capa no sabe nada de WhatsApp ni de FastAPI, es Python puro contra la base de datos. Por eso es fácil de probar.

### `app/models/`

Los modelos de SQLAlchemy. Un archivo por tabla. Estos son la traducción a Python del `schema.sql`.

### `app/integrations/`

Para hablar con servicios externos. Por ahora solo WhatsApp Cloud API. Si Meta cambia su API mañana, solo toco aquí.

### `app/db/`

Configuración de conexión y migraciones con Alembic. Se toca poco después del setup inicial.

### `app/utils/`

Funciones que se usan en muchos lados: parsear "2,500.50" a decimal, normalizar texto de categorías, configurar logs.

### `tests/`

Pruebas automatizadas. Para una app que maneja dinero esto no es opcional. La estructura espeja a `app/`.

### `scripts/`

Cosas que se corren a mano, no son parte de la app. Por ejemplo, inicializar la DB la primera vez.

---

## Reglas

1. **Una sola dirección de dependencias.** Handlers usan services, services usan models. No al revés.

2. **No mezclar capas.** Si un handler hace queries directos a la DB, mal. Si un service formatea mensajes para WhatsApp, mal.

3. **Sin lógica en models.** Los models describen datos, no toman decisiones.

4. **Un archivo por concepto.** No meter handler de egreso con el de ingreso aunque se parezcan.

5. **Español en todo.** Variables, comentarios, mensajes. Solo lo de Python se queda en inglés.

6. **Imports relativos desde `app/`.** `from app.services.saldos import calcular_saldo`.

---

## Lo que falta agregar

Cosas que voy a meter cuando las necesite, no antes:

- `Dockerfile` y `docker-compose.yml` cuando vaya a desplegar
- GitHub Actions cuando quiera automatizar tests
- `alembic.ini` cuando configure migraciones
