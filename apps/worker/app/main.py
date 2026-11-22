"""API del worker: salud y endpoints que dispara n8n (protegidos con SERVICE_TOKEN)."""

import hmac
from contextlib import asynccontextmanager

import asyncpg
from fastapi import Depends, FastAPI, Header, HTTPException

from .config import load_settings
from .queue import enqueue

settings = load_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.pool = await asyncpg.create_pool(settings.database_url, min_size=1, max_size=5)
    yield
    await app.state.pool.close()


app = FastAPI(title="dichoyhecho-worker", lifespan=lifespan)


def require_token(authorization: str = Header(default="")) -> None:
    expected = f"Bearer {settings.service_token}"
    if not hmac.compare_digest(authorization, expected):
        raise HTTPException(status_code=401, detail="unauthorized")


@app.get("/health")
async def health():
    async with app.state.pool.acquire() as conn:
        pending = await conn.fetchval("SELECT count(*) FROM jobs WHERE status = 'queued'")
        failed = await conn.fetchval("SELECT count(*) FROM jobs WHERE status = 'failed'")
    return {"ok": True, "jobs_queued": pending, "jobs_failed": failed}


@app.post("/jobs/{job_type}", dependencies=[Depends(require_token)])
async def create_job(job_type: str, payload: dict | None = None):
    """n8n encola trabajos acá (ej. ingest_hcdn_votes, poll_channels)."""
    async with app.state.pool.acquire() as conn:
        job_id = await enqueue(conn, job_type, payload or {})
    return {"job_id": job_id}
