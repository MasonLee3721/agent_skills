import json
import sys
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from fetch_official_data import DataError, parse_integer, parse_tpex, parse_twse, roc_compact_to_iso


class OfficialParserTests(unittest.TestCase):
    def fixture(self,name):
        return json.loads((ROOT/'tests'/'fixtures'/name).read_text(encoding='utf-8'))

    def test_twse_normalizes_by_field_name_and_shares(self):
        records=parse_twse(self.fixture('twse_t86.json'),'twse-url','2026-08-19T10:00:00+00:00')
        self.assertEqual(len(records),1)
        r=records[0]
        self.assertEqual((r.trade_date,r.market,r.stock_code),('2026-08-19','TWSE','1234'))
        self.assertEqual(r.foreign_net_shares,1_234_000)
        self.assertEqual(r.sitc_net_shares,-56_000)

    def test_twse_rejects_unknown_units(self):
        payload=self.fixture('twse_t86.json'); payload['hints']='單位：張'
        with self.assertRaises(DataError): parse_twse(payload,'u','t')

    def test_twse_rejects_missing_required_field(self):
        payload=self.fixture('twse_t86.json'); payload['fields'].remove('投信買賣超股數')
        with self.assertRaises(DataError): parse_twse(payload,'u','t')

    def test_tpex_normalizes_roc_date_and_values(self):
        r=parse_tpex(self.fixture('tpex_3insti.json'),'tpex-url','2026-08-19T10:00:00+00:00')[0]
        self.assertEqual((r.trade_date,r.market,r.stock_code),('2026-08-19','TPEx','5678'))
        self.assertEqual(r.foreign_net_shares,-123_000)
        self.assertEqual(r.sitc_net_shares,45_000)

    def test_roc_date_validation(self):
        self.assertEqual(roc_compact_to_iso('1150819'),'2026-08-19')
        with self.assertRaises(DataError): roc_compact_to_iso('1150230')

    def test_missing_marker_is_null_not_zero(self):
        self.assertIsNone(parse_integer('--'))
        self.assertEqual(parse_integer('0'),0)

    def test_duplicate_key_is_rejected(self):
        payload=self.fixture('tpex_3insti.json')*2
        with self.assertRaises(DataError): parse_tpex(payload,'u','t')


if __name__=='__main__': unittest.main()
