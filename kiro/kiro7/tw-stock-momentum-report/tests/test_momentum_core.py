import sys
import unittest
from decimal import Decimal
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

from momentum_core import (
    Mode, ScreeningInput, has_long_upper_shadow, investment_ratio_pct,
    issued_shares_from_capital, preselect_candidate, rating_for_score, screen_candidate,
    simple_moving_average, trailing_positive_streak, volume_ratio,
)


class CalculationTests(unittest.TestCase):
    def test_investment_ratio_preserves_sign_and_precision(self):
        self.assertEqual(investment_ratio_pct(400_000, 100_000_000), Decimal("0.400"))
        self.assertEqual(investment_ratio_pct(-1_000, 100_000), Decimal("-1.00"))

    def test_investment_ratio_rejects_invalid_denominator(self):
        with self.assertRaises(ValueError):
            investment_ratio_pct(1, 0)

    def test_issued_shares_uses_actual_par_value(self):
        self.assertEqual(issued_shares_from_capital(5_000_000_000, Decimal("5")), Decimal("1000000000"))

    def test_streak_stops_on_zero_missing_or_sell(self):
        self.assertEqual(trailing_positive_streak([1, 2, 3]), 3)
        self.assertEqual(trailing_positive_streak([5, 0, 2, 3]), 2)
        self.assertEqual(trailing_positive_streak([5, None, 2]), 1)
        self.assertEqual(trailing_positive_streak([1, 2, -1]), 0)

    def test_moving_average_does_not_fill_insufficient_history(self):
        self.assertEqual(simple_moving_average([1, 2, 3], 2), [None, Decimal("1.5"), Decimal("2.5")])

    def test_volume_ratio_requires_full_nonzero_baseline(self):
        self.assertIsNone(volume_ratio(3_000, [1_000] * 19))
        self.assertIsNone(volume_ratio(3_000, [0] * 20))
        self.assertEqual(volume_ratio(3_000, [1_000] * 20), Decimal("3"))

    def test_long_upper_shadow_and_doji_guard(self):
        self.assertTrue(has_long_upper_shadow(Decimal("100"), Decimal("106"), Decimal("99"), Decimal("102")))
        self.assertFalse(has_long_upper_shadow(Decimal("100"), Decimal("101"), Decimal("99.9"), Decimal("100")))


class ScreeningTests(unittest.TestCase):
    def valid_input(self, **changes):
        data = dict(stock_code="1234", investment_ratio_pct=Decimal("0.4"), positive_ratio_rank=50,
                    volume_lots=3_000, paid_in_capital_twd=4_999_999_999,
                    sitc_net_shares=1, consecutive_sitc_buy_days=3,
                    is_common_stock=True, trading_status_ok=True, liquidity_status_ok=True)
        data.update(changes)
        return ScreeningInput(**data)

    def test_exact_boundaries(self):
        self.assertTrue(screen_candidate(self.valid_input(), Mode.CONSERVATIVE).passed)
        self.assertFalse(screen_candidate(self.valid_input(paid_in_capital_twd=5_000_000_000), Mode.CONSERVATIVE).passed)

    def test_top_30_is_alternative_to_absolute_ratio(self):
        item = self.valid_input(investment_ratio_pct=Decimal("0.1"), positive_ratio_rank=30)
        self.assertTrue(screen_candidate(item, Mode.CONSERVATIVE).passed)

    def test_missing_data_never_auto_passes(self):
        result = screen_candidate(self.valid_input(volume_lots=None), Mode.CONSERVATIVE)
        self.assertFalse(result.passed)
        self.assertIn("資料不足：minimum_volume", result.reasons)

    def test_modes_have_distinct_streak_thresholds(self):
        item = self.valid_input(consecutive_sitc_buy_days=1)
        self.assertTrue(screen_candidate(item, Mode.AGGRESSIVE).passed)
        self.assertFalse(screen_candidate(item, Mode.CONSERVATIVE).passed)

    def test_preselection_does_not_require_history(self):
        item = self.valid_input(consecutive_sitc_buy_days=None)
        self.assertTrue(preselect_candidate(item).passed)
        self.assertFalse(screen_candidate(item, Mode.AGGRESSIVE).passed)

    def test_rating_boundaries(self):
        expected = {100:"強勢候選", 80:"強勢候選", 79:"可觀察", 70:"可觀察",
                    69:"條件不足", 60:"條件不足", 59:"不列入", 0:"不列入"}
        for score, label in expected.items():
            self.assertEqual(rating_for_score(score), label)
        with self.assertRaises(ValueError):
            rating_for_score(101)


if __name__ == "__main__":
    unittest.main()
