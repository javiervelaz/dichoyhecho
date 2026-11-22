"""Cola de trabajos sobre Postgres (tabla jobs) con FOR UPDATE SKIP LOCKED."""

import json
from typing import Any

import asyncpg

MAX_ATTEMPTS = 3


async def enqueue(conn: asyncpg.Connection, job_type: str, payload: dict[str, Any]) -> int:
    return await conn.fetchval(
        "INSERT INTO jobs (type, payload) VALUES ($1, $2::jsonb) RETURNING id",
        job_type, json.dumps(payload),
    )


CLAIM_SQL = """
UPDATE jobs SET status = 'running', locked_at = now(), attempts = attempts + 1
WHERE id = (
  SELECT id FROM jobs
  WHERE status = 'queued' AND run_at <= now() AND ($1::text IS NULL OR type = $1)
  ORDER BY run_at
  FOR UPDATE SKIP LOCKED
  LIMIT 1
)
RETURNING id, type, payload, attempts
"""


async def claim(conn: asyncpg.Connection, job_type: str | None = None) -> asyncpg.Record | None:
    """Toma el próximo trabajo disponible sin bloquear a otros workers."""
    return await conn.fetchrow(CLAIM_SQL, job_type)


async def complete(conn: asyncpg.Connection, job_id: int) -> None:
    await conn.execute("UPDATE jobs SET status = 'done', locked_at = NULL WHERE id = $1", job_id)


async def fail(conn: asyncpg.Connection, job_id: int, attempts: int, error: str) -> None:
    """Reintenta con espera creciente; tras MAX_ATTEMPTS queda en failed para alertar."""
    if attempts >= MAX_ATTEMPTS:
        await conn.execute(
            "UPDATE jobs SET status = 'failed', error = $2, locked_at = NULL WHERE id = $1",
            job_id, error[:2000],
        )
    else:
        await conn.execute(
            """UPDATE jobs SET status = 'queued', error = $2, locked_at = NULL,
                   run_at = now() + make_interval(mins => 5 * $3)
               WHERE id = $1""",
            job_id, error[:2000], attempts,
        )
