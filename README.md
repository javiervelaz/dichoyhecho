# Dicho y Hecho

Registro público de lo que la política argentina **dice** y lo que **hace**: declaraciones oficiales,
votaciones nominales y datos económicos, cruzados y con su fuente. Rumbo a las elecciones del
24 de octubre de 2027 y después, como control de gestión.

- YouTube: `@dichoyhecho.ar` · TikTok / Instagram: `dichoyhecho` · Web: dichoyhecho.ar

## Estructura

```text
db/migrations/   esquema Postgres (dbmate)
apps/worker/     ingesta, transcripción, NLP y cola (Python)
apps/render/     plantillas de video (Remotion)
apps/publisher/  publicación en plataformas
apps/admin/      panel de revisión y verificación (Next.js)
n8n/             workflows exportados
infra/           docker-compose, Nginx e instalador del VPS
```

## Arranque local

```bash
cp .env.example .env            # completar valores
docker compose -f infra/docker-compose.yml run --rm migrate
docker compose -f infra/docker-compose.yml up -d worker
curl localhost:8000/health
```

## Metodología

Cada dato en pantalla enlaza a su acta, serie oficial o expediente. El video proviene solo de
transmisiones oficiales públicas. Las correcciones se publican. Ver `CLAUDE.md` para las reglas completas.
