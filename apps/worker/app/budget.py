"""Tope de gasto: aborta antes de superar el límite mensual. Nunca avisa y sigue."""

from decimal import Decimal

import asyncpg


class BudgetExceeded(SystemExit):
    pass


MONTH_SPENT_SQL = """
SELECT coalesce(sum(cost_usd), 0)
FROM llm_usage
WHERE created_at >= date_trunc('month', now())
"""


async def guard(conn: asyncpg.Connection, cap_usd: float, estimated_cost_usd: float) -> Decimal:
    """Devuelve lo gastado en el mes; lanza BudgetExceeded si la llamada superaría el tope."""
    spent: Decimal = await conn.fetchval(MONTH_SPENT_SQL)
    if spent + Decimal(str(estimated_cost_usd)) > Decimal(str(cap_usd)):
        raise BudgetExceeded(f"Tope mensual alcanzado: {spent:.2f} / {cap_usd:.2f} USD")
    return spent


async def record(
    conn: asyncpg.Connection,
    *,
    model: str,
    purpose: str,
    input_tokens: int,
    output_tokens: int,
    cost_usd: float,
) -> None:
    await conn.execute(
        """INSERT INTO llm_usage (model, purpose, input_tokens, output_tokens, cost_usd)
           VALUES ($1, $2, $3, $4, $5)""",
        model, purpose, input_tokens, output_tokens, cost_usd,
    )
