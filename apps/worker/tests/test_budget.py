from decimal import Decimal

import pytest

from app.budget import BudgetExceeded, guard


class FakeConn:
    def __init__(self, spent: str):
        self.spent = Decimal(spent)

    async def fetchval(self, _sql):
        return self.spent


async def test_guard_allows_under_cap():
    assert await guard(FakeConn("10.00"), cap_usd=40, estimated_cost_usd=1.5) == Decimal("10.00")


async def test_guard_aborts_over_cap():
    with pytest.raises(BudgetExceeded):
        await guard(FakeConn("39.50"), cap_usd=40, estimated_cost_usd=1.0)
