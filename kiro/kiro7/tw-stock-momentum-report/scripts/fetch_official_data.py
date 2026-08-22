#!/usr/bin/env python3
"""Fetch and normalize official TWSE/TPEx institutional trading data."""
from __future__ import annotations

import argparse
import json
import time
from dataclasses import asdict, dataclass
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any, Iterable
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

TWSE_URL = "https://www.twse.com.tw/rwd/zh/fund/T86?response=json&date={date}&selectType=ALLBUT0999"
TPEX_URL = "https://www.tpex.org.tw/openapi/v1/tpex_3insti_daily_trading"


class DataError(RuntimeError):
    pass


@dataclass(frozen=True)
class InstitutionalRecord:
    trade_date: str
    stock_code: str
    stock_name: str
    market: str
    foreign_net_shares: int | None
    sitc_net_shares: int | None
    source_name: str
    source_url: str
    fetched_at: str


def parse_integer(value: Any) -> int | None:
    if value is None:
        return None
    text = str(value).strip().replace(",", "")
    if text in {"", "--", "---", "N/A", "null"}:
        return None
    try:
        return int(text)
    except ValueError as exc:
        raise DataError(f"invalid integer: {value!r}") from exc


def roc_compact_to_iso(value: str) -> str:
    text = str(value).strip()
    if len(text) != 7 or not text.isdigit():
        raise DataError(f"invalid ROC date: {value!r}")
    year = int(text[:3]) + 1911
    try:
        return date(year, int(text[3:5]), int(text[5:7])).isoformat()
    except ValueError as exc:
        raise DataError(f"invalid ROC date: {value!r}") from exc


def compact_to_iso(value: str) -> str:
    text = str(value).strip()
    if len(text) != 8 or not text.isdigit():
        raise DataError(f"invalid Gregorian date: {value!r}")
    try:
        return date(int(text[:4]), int(text[4:6]), int(text[6:8])).isoformat()
    except ValueError as exc:
        raise DataError(f"invalid Gregorian date: {value!r}") from exc


def _unique(records: Iterable[InstitutionalRecord]) -> list[InstitutionalRecord]:
    result=[]; seen=set()
    for record in records:
        key=(record.trade_date, record.market, record.stock_code)
        if key in seen:
            raise DataError(f"duplicate institutional key: {key}")
        seen.add(key); result.append(record)
    return result


def parse_twse(payload: Any, source_url: str, fetched_at: str) -> list[InstitutionalRecord]:
    if not isinstance(payload, dict) or payload.get("stat") != "OK":
        raise DataError("TWSE response status is not OK")
    if "股" not in str(payload.get("hints", "")):
        raise DataError("TWSE response does not declare share units")
    fields=payload.get("fields"); rows=payload.get("data")
    if not isinstance(fields, list) or not isinstance(rows, list):
        raise DataError("TWSE fields/data schema missing")
    required={"證券代號","證券名稱","外陸資買賣超股數(不含外資自營商)","投信買賣超股數"}
    missing=required-set(fields)
    if missing:
        raise DataError(f"TWSE required fields missing: {sorted(missing)}")
    index={name:fields.index(name) for name in required}
    trade_date=compact_to_iso(payload.get("date", ""))
    records=[]
    for row in rows:
        if not isinstance(row, list) or len(row) < len(fields):
            raise DataError("TWSE row length does not match fields")
        records.append(InstitutionalRecord(
            trade_date=trade_date,
            stock_code=str(row[index["證券代號"]]).strip(),
            stock_name=str(row[index["證券名稱"]]).strip(), market="TWSE",
            foreign_net_shares=parse_integer(row[index["外陸資買賣超股數(不含外資自營商)"]]),
            sitc_net_shares=parse_integer(row[index["投信買賣超股數"]]),
            source_name="TWSE T86", source_url=source_url, fetched_at=fetched_at))
    return _unique(records)


def _lookup(row: dict[str, Any], candidates: tuple[str, ...]) -> Any:
    normalized={key.strip():value for key,value in row.items()}
    for key in candidates:
        if key in row: return row[key]
        if key.strip() in normalized: return normalized[key.strip()]
    raise DataError(f"TPEx required field missing; expected one of {candidates}")


def parse_tpex(payload: Any, source_url: str, fetched_at: str) -> list[InstitutionalRecord]:
    if not isinstance(payload, list):
        raise DataError("TPEx response must be an array")
    records=[]
    foreign_keys=(
      "Foreign Investors include Mainland Area Investors (Foreign Dealers excluded)-Difference",
      "ForeignInvestorsIncludeMainlandAreaInvestors-Difference")
    sitc_keys=("SecuritiesInvestmentTrustCompanies-Difference",)
    for row in payload:
        if not isinstance(row, dict): raise DataError("TPEx row must be an object")
        records.append(InstitutionalRecord(
            trade_date=roc_compact_to_iso(_lookup(row,("Date",))),
            stock_code=str(_lookup(row,("SecuritiesCompanyCode",))).strip(),
            stock_name=str(_lookup(row,("CompanyName",))).strip(), market="TPEx",
            foreign_net_shares=parse_integer(_lookup(row,foreign_keys)),
            sitc_net_shares=parse_integer(_lookup(row,sitc_keys)),
            source_name="TPEx OpenAPI tpex_3insti_daily_trading",
            source_url=source_url, fetched_at=fetched_at))
    return _unique(records)


def fetch_json(url: str, timeout: float=20, attempts: int=3) -> tuple[Any,str]:
    error=None
    for attempt in range(attempts):
        try:
            request=Request(url,headers={"User-Agent":"tw-stock-momentum-report/1.0","Accept":"application/json"})
            with urlopen(request,timeout=timeout) as response:
                raw=response.read(); fetched_at=datetime.now(timezone.utc).isoformat()
            return json.loads(raw.decode("utf-8-sig")), fetched_at
        except (HTTPError,URLError,TimeoutError,json.JSONDecodeError,UnicodeDecodeError) as exc:
            error=exc
            if attempt+1<attempts: time.sleep(2**attempt)
    raise DataError(f"official fetch failed after {attempts} attempts: {error}")


def fetch_market(market: str, requested_date: str) -> list[InstitutionalRecord]:
    compact=requested_date.replace("-","")
    url=TWSE_URL.format(date=compact) if market=="twse" else TPEX_URL
    payload,fetched_at=fetch_json(url)
    records=parse_twse(payload,url,fetched_at) if market=="twse" else parse_tpex(payload,url,fetched_at)
    dates={r.trade_date for r in records}
    if dates != {requested_date}:
        raise DataError(f"{market.upper()} returned dates {sorted(dates)} instead of {requested_date}")
    return records


def main() -> int:
    parser=argparse.ArgumentParser()
    parser.add_argument("--market",choices=("twse","tpex","all"),default="all")
    parser.add_argument("--date",required=True,help="completed trade date, YYYY-MM-DD")
    parser.add_argument("--output",type=Path,required=True)
    args=parser.parse_args()
    compact_to_iso(args.date.replace("-",""))
    markets=("twse","tpex") if args.market=="all" else (args.market,)
    records=[]
    for market in markets: records.extend(fetch_market(market,args.date))
    _unique(records)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    document={"schema_version":"1.0","requested_trade_date":args.date,
              "generated_at":datetime.now(timezone.utc).isoformat(),
              "units":{"foreign_net_shares":"shares","sitc_net_shares":"shares"},
              "records":[asdict(r) for r in records]}
    args.output.write_text(json.dumps(document,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(f"wrote {len(records)} records to {args.output}")
    return 0


if __name__=="__main__":
    try: raise SystemExit(main())
    except DataError as exc:
        print(f"ERROR: {exc}",file=__import__('sys').stderr); raise SystemExit(2)
