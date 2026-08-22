#!/usr/bin/env python3
"""Pure calculations for the Taiwan stock momentum report.

No network, filesystem, publishing, or brokerage side effects belong here.
All share counts use shares unless a function name explicitly says lots.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from decimal import Decimal
from enum import Enum
from typing import Iterable, Sequence


class Mode(str, Enum):
    AGGRESSIVE = "aggressive"
    CONSERVATIVE = "conservative"


@dataclass(frozen=True)
class Thresholds:
    min_investment_ratio_pct: Decimal = Decimal("0.4")
    top_positive_rank_cutoff: int = 30
    min_volume_lots: int = 3_000
    max_paid_in_capital_twd: int = 5_000_000_000
    aggressive_min_streak: int = 1
    conservative_min_streak: int = 3
    upper_shadow_body_multiple: Decimal = Decimal("1.5")
    doji_body_to_range_max: Decimal = Decimal("0.05")
    doji_min_amplitude_pct: Decimal = Decimal("2")


DEFAULT_THRESHOLDS = Thresholds()


@dataclass(frozen=True)
class ScreeningInput:
    stock_code: str
    investment_ratio_pct: Decimal | None
    positive_ratio_rank: int | None
    volume_lots: int | Decimal | None
    paid_in_capital_twd: int | None
    sitc_net_shares: int | None
    consecutive_sitc_buy_days: int | None
    is_common_stock: bool | None
    trading_status_ok: bool | None
    liquidity_status_ok: bool | None


@dataclass(frozen=True)
class ScreeningResult:
    passed: bool
    mode: Mode
    checks: dict[str, bool | None]
    reasons: tuple[str, ...] = field(default_factory=tuple)


def lots_to_shares(lots: int) -> int:
    return lots * 1_000


def shares_to_lots(shares: int) -> Decimal:
    return Decimal(shares) / Decimal(1_000)


def investment_ratio_pct(sitc_net_shares: int, issued_shares: int) -> Decimal:
    if issued_shares <= 0:
        raise ValueError("issued_shares must be positive")
    return Decimal(sitc_net_shares) / Decimal(issued_shares) * Decimal(100)


def issued_shares_from_capital(paid_in_capital_twd: int, par_value_twd: Decimal) -> Decimal:
    if paid_in_capital_twd < 0:
        raise ValueError("paid_in_capital_twd cannot be negative")
    if par_value_twd <= 0:
        raise ValueError("par_value_twd must be positive")
    return Decimal(paid_in_capital_twd) / par_value_twd


def trailing_positive_streak(values: Sequence[int | Decimal | None]) -> int:
    """Count consecutive positive values from the newest end of chronological data."""
    count = 0
    for value in reversed(values):
        if value is None or value <= 0:
            break
        count += 1
    return count


def simple_moving_average(values: Sequence[int | float | Decimal], window: int) -> list[Decimal | None]:
    if window <= 0:
        raise ValueError("window must be positive")
    numbers = [Decimal(str(v)) for v in values]
    result: list[Decimal | None] = []
    rolling = Decimal(0)
    for index, value in enumerate(numbers):
        rolling += value
        if index >= window:
            rolling -= numbers[index - window]
        result.append(rolling / window if index + 1 >= window else None)
    return result


def volume_ratio(current_volume_lots: int, prior_volumes_lots: Sequence[int], window: int = 20) -> Decimal | None:
    if current_volume_lots < 0 or any(v < 0 for v in prior_volumes_lots):
        raise ValueError("volume cannot be negative")
    if len(prior_volumes_lots) < window:
        return None
    baseline = prior_volumes_lots[-window:]
    average = Decimal(sum(baseline)) / Decimal(window)
    if average == 0:
        return None
    return Decimal(current_volume_lots) / average


def is_bullish_alignment(close: Decimal, ma5: Decimal | None, ma10: Decimal | None, ma20: Decimal | None) -> bool | None:
    if ma5 is None or ma10 is None or ma20 is None:
        return None
    return close > ma5 > ma10 > ma20


def has_long_upper_shadow(
    open_price: Decimal,
    high: Decimal,
    low: Decimal,
    close: Decimal,
    thresholds: Thresholds = DEFAULT_THRESHOLDS,
) -> bool:
    if min(open_price, high, low, close) < 0 or high < max(open_price, close) or low > min(open_price, close) or high < low:
        raise ValueError("invalid OHLC")
    candle_range = high - low
    if candle_range == 0:
        return False
    body = abs(close - open_price)
    upper_shadow = high - max(open_price, close)
    amplitude_pct = candle_range / open_price * 100 if open_price > 0 else Decimal(0)
    if body / candle_range <= thresholds.doji_body_to_range_max:
        return amplitude_pct >= thresholds.doji_min_amplitude_pct and upper_shadow > body
    return upper_shadow > body * thresholds.upper_shadow_body_multiple


def preselect_candidate(
    item: ScreeningInput,
    thresholds: Thresholds = DEFAULT_THRESHOLDS,
) -> ScreeningResult:
    """Apply only filters available from same-day full-market data.

    Historical streak and technical indicators intentionally do not participate.
    """
    ratio_gate = None if item.investment_ratio_pct is None else (
        item.investment_ratio_pct >= thresholds.min_investment_ratio_pct
        or (item.positive_ratio_rank is not None and 1 <= item.positive_ratio_rank <= thresholds.top_positive_rank_cutoff)
    )
    checks: dict[str, bool | None] = {
        "investment_ratio_or_top_rank": ratio_gate,
        "minimum_volume": None if item.volume_lots is None else item.volume_lots >= thresholds.min_volume_lots,
        "capital_below_limit": None if item.paid_in_capital_twd is None else item.paid_in_capital_twd < thresholds.max_paid_in_capital_twd,
        "sitc_net_buy": None if item.sitc_net_shares is None else item.sitc_net_shares > 0,
        "common_stock": item.is_common_stock,
        "trading_status": item.trading_status_ok,
        "liquidity_status": item.liquidity_status_ok,
    }
    labels = {
        "investment_ratio_or_top_rank": "投本比未達門檻且未進正投本比前30名",
        "minimum_volume": "成交量不足3000張",
        "capital_below_limit": "實收資本額未低於50億元",
        "sitc_net_buy": "投信非淨買超",
        "common_stock": "無法確認為普通股或屬排除商品",
        "trading_status": "交易狀態不符合",
        "liquidity_status": "流動性狀態不符合",
    }
    reasons = tuple(
        f"資料不足：{key}" if value is None else labels[key]
        for key, value in checks.items() if value is not True
    )
    return ScreeningResult(passed=all(value is True for value in checks.values()), mode=Mode.AGGRESSIVE, checks=checks, reasons=reasons)


def screen_candidate(
    item: ScreeningInput,
    mode: Mode,
    thresholds: Thresholds = DEFAULT_THRESHOLDS,
) -> ScreeningResult:
    min_streak = thresholds.aggressive_min_streak if mode is Mode.AGGRESSIVE else thresholds.conservative_min_streak
    ratio_gate = None if item.investment_ratio_pct is None else (
        item.investment_ratio_pct >= thresholds.min_investment_ratio_pct
        or (item.positive_ratio_rank is not None and 1 <= item.positive_ratio_rank <= thresholds.top_positive_rank_cutoff)
    )
    checks: dict[str, bool | None] = {
        "investment_ratio_or_top_rank": ratio_gate,
        "minimum_volume": None if item.volume_lots is None else item.volume_lots >= thresholds.min_volume_lots,
        "capital_below_limit": None if item.paid_in_capital_twd is None else item.paid_in_capital_twd < thresholds.max_paid_in_capital_twd,
        "sitc_net_buy": None if item.sitc_net_shares is None else item.sitc_net_shares > 0,
        "minimum_buy_streak": None if item.consecutive_sitc_buy_days is None else item.consecutive_sitc_buy_days >= min_streak,
        "common_stock": item.is_common_stock,
        "trading_status": item.trading_status_ok,
        "liquidity_status": item.liquidity_status_ok,
    }
    labels = {
        "investment_ratio_or_top_rank": "投本比未達門檻且未進正投本比前30名",
        "minimum_volume": "成交量不足3000張",
        "capital_below_limit": "實收資本額未低於50億元",
        "sitc_net_buy": "投信非淨買超",
        "minimum_buy_streak": f"投信連買未達{min_streak}日",
        "common_stock": "無法確認為普通股或屬排除商品",
        "trading_status": "交易狀態不符合",
        "liquidity_status": "流動性狀態不符合",
    }
    reasons = tuple(
        f"資料不足：{key}" if value is None else labels[key]
        for key, value in checks.items()
        if value is not True
    )
    return ScreeningResult(passed=all(value is True for value in checks.values()), mode=mode, checks=checks, reasons=reasons)


def rating_for_score(score: int) -> str:
    if not 0 <= score <= 100:
        raise ValueError("score must be between 0 and 100")
    if score >= 80:
        return "強勢候選"
    if score >= 70:
        return "可觀察"
    if score >= 60:
        return "條件不足"
    return "不列入"
