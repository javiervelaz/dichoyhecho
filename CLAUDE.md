# Dicho y Hecho — reglas del proyecto

Canal neutral de registro público sobre política argentina rumbo a las elecciones del 24/10/2027,
más un producto de datos (buscador y alertas sobre lo que cada político dijo y votó).
Formato estrella: "Dijo / Votó". Handles: YouTube `@dichoyhecho.ar`, TikTok e Instagram `dichoyhecho`.
Dominio: `dichoyhecho.ar`. Plan técnico completo: documento "Plan técnico: canal electoral 2027".

## Reglas no negociables

1. **Toda afirmación tiene fuente.** Nada se escribe en `claims`, `stories` ni en pantalla sin un
   `source_id`, acta, serie oficial o expediente. Si no hay documento, no hay afirmación.
2. **Video solo de fuentes oficiales públicas** (`usage_rights = 'publico_oficial'`). Los medios
   (`rss_titular`) son solo señal: nunca se descarga ni se usa su material.
3. **Estado judicial literal.** Solo los valores de `legal_cases.status`, con documento y fecha.
4. **Nunca contenido sintético de políticos** (ni voz ni imagen). La única voz sintética es la
   narración propia, y toda publicación lleva `containsSyntheticMedia: true`.
5. **Verificación humana obligatoria.** Ninguna story pasa a `verificado` o `publicado` sin
   `verified_at` (lo exige un CHECK en la base). Las marcadas `sensitive` tienen doble revisión.
6. **Simetría.** Mismos formatos, duraciones y reglas para todos los espacios políticos.
7. **Topes de gasto que abortan.** Toda llamada paga pasa por `budget.guard()`. Si falta la
   variable de tope, el proceso no arranca. Nunca avisar y seguir.
8. **Sin texto hardcodeado** en componentes Remotion: todo por props o `i18n.json`.
9. **Guiones de videos largos escritos por humanos.** Los Shorts usan plantillas sobre datos.
10. **Repo público: cero secretos.** Credenciales solo en `.env` del VPS (ver `.env.example`).

## Stack

- Orquestación: n8n (instancia existente), llama a los servicios por webhooks HTTPS con token.
- `apps/worker`: Python 3.12, FastAPI + asyncpg. Ingesta, transcripción (faster-whisper), NLP (Claude
  Haiku 5.5 / Sonnet 5.5), cola en Postgres (`jobs` + `FOR UPDATE SKIP LOCKED`).
- `apps/render`: Node 22 + Remotion + FFmpeg. `apps/publisher`: Node (YouTube, TikTok, Meta).
- `apps/admin`: Next.js en Vercel (cola de aprobación y verificación).
- Base: Neon Postgres 17 + pgvector, proyecto `dichoyhecho` (sa-east-1). Migraciones: `dbmate`, SQL plano
  en `db/migrations`. Rama `main` = producción; usar una rama `dev` para pruebas.
- Media: Cloudflare R2. Voz: ElevenLabs (PVC propia).

## Convenciones

- Python: ruff + pytest. Node: TypeScript estricto + vitest.
- Commits pequeños, un sprint por rama (`sprint-N-tema`), PR a `main`.
- Cuota de YouTube: vigilar canales con `playlistItems.list` (1 unidad), nunca `search.list` (100).
