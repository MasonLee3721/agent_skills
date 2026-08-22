#!/usr/bin/env python3
"""Transparent 100-point scoring; missing sections score zero and reduce confidence."""
from __future__ import annotations
from decimal import Decimal
from typing import Any
from momentum_core import rating_for_score
SECTION_MAX={"investment_ratio":25,"sitc_continuity":20,"chip_position":15,"foreign_sync":10,"moving_averages":15,"breakout_volume":15}
def D(v):return None if v is None else Decimal(str(v))
def technical_scores(t:dict[str,Any])->dict[str,dict[str,Any]]:
 ma=0;reasons=[]
 if t.get("bullish_alignment"):ma+=6;reasons.append("收盤站上多頭排列")
 for k,label in (("ma5_up","MA5向上"),("ma10_up","MA10向上"),("ma20_up","MA20向上")):
  if t.get(k):ma+=1;reasons.append(label)
 for k,label in (("close_above_ma5","站上MA5"),("close_above_ma10","站上MA10"),("close_above_ma20","站上MA20")):
  if t.get(k):ma+=2;reasons.append(label)
 bv=0;br=[]
 if t.get("close_breakout_prior_20d_high"):bv+=6;br.append("收盤突破前20日高")
 dist=D(t.get("distance_from_prior_20d_high_pct"))
 if dist is not None and dist>=-3:bv+=3;br.append("距前20日高點3%內")
 if t.get("red_candle"):bv+=2;br.append("收紅K")
 vr=D(t.get("volume_ratio_20d"))
 if vr is not None and Decimal("0.8")<=vr<=Decimal("2.5"):bv+=4;br.append("量比介於0.8至2.5")
 deductions=[]
 if t.get("long_upper_shadow"):deductions.append(("長上影",-4))
 if t.get("high_open_low_close"):deductions.append(("高開走低",-3))
 if t.get("false_breakout"):deductions.append(("假突破",-6))
 for label,points in deductions:bv+=points;br.append(f"{label}{points}分")
 return {"moving_averages":{"score":max(0,min(15,ma)),"max":15,"status":"actual","reasons":reasons},"breakout_volume":{"score":max(0,min(15,bv)),"max":15,"status":"actual","reasons":br}}

def investment_score(ratio_pct,positive_rank=None):
 ratio=D(ratio_pct)
 if ratio is None:return {"score":0,"max":25,"status":"missing","reasons":["缺少投本比"]}
 score=15 if ratio>=2 else 13 if ratio>=1 else 11 if ratio>=Decimal("0.7") else 9 if ratio>=Decimal("0.4") else 4 if ratio>0 else 0;reasons=[f"投本比{ratio}%"]
 if positive_rank is not None:score+=10 if positive_rank<=3 else 8 if positive_rank<=10 else 6 if positive_rank<=30 else 0;reasons.append(f"全市場正投本比排名{positive_rank}")
 return {"score":min(25,score),"max":25,"status":"actual" if positive_rank is not None else "partial","reasons":reasons}
def continuity_score(streak,daily):
 if streak is None or not isinstance(daily,list) or len(daily)<3 or any(D(x) is None for x in daily[-3:]):return {"score":0,"max":20,"status":"missing","reasons":["缺少近3日投信資料"]}
 v=[D(x) for x in daily[-3:]];score=10 if streak>=5 else 8 if streak>=3 else 5 if streak==2 else 3 if streak==1 else 0;positive=sum(x>0 for x in v);score+=6 if positive==3 else 4 if positive==2 else 1 if positive==1 else 0;reasons=[f"連買{streak}日",f"近3日{positive}日買超"]
 if v[2]>v[1]>v[0]:score+=4;reasons.append("買盤逐日加速")
 elif v[2]>=(v[0]+v[1])/2:score+=2;reasons.append("最新買盤未低於前兩日平均")
 return {"score":min(20,score),"max":20,"status":"actual","reasons":reasons}
def chip_score(estimated_pct=None,actual_pct=None):
 value=D(actual_pct) if actual_pct is not None else D(estimated_pct)
 if value is None:return {"score":0,"max":15,"status":"missing","reasons":["缺少持股或累計比例"]}
 raw=15 if 3<=value<=7 else 12 if 2<=value<3 or 7<value<=8 else 7 if value<2 else 5 if value<=15 else 2 if value<=20 else 0;estimated=actual_pct is None;score=min(11,(raw*3)//4) if estimated else raw;label="期間累計買超比例（估算）" if estimated else "實際持股比例"
 return {"score":int(score),"max":15,"status":"estimated" if estimated else "actual","reasons":[f"{label}{value}%"]}
def foreign_score(sitc,foreign,source_status="actual"):
 if not isinstance(sitc,list) or not isinstance(foreign,list) or len(sitc)<3 or len(foreign)<3:return {"score":0,"max":10,"status":"missing","reasons":["缺少近3日法人資料"]}
 s=[D(x) for x in sitc[-3:]];f=[D(x) for x in foreign[-3:]];score=0;reasons=[]
 if s[-1]>0 and f[-1]>0:score+=4;reasons.append("當日同步買超")
 if sum(f)>0:score+=3;reasons.append("近3日外資累計買超")
 if all(a>0 and b>0 for a,b in zip(s,f)):score+=3;reasons.append("近3日皆同步買超")
 if sum(f)<0:reasons.append("法人分歧")
 return {"score":min(10,score),"max":10,"status":source_status,"reasons":reasons}

def score_partial(stock:dict[str,Any])->dict[str,Any]:
 sections={k:{"score":0,"max":m,"status":"missing","reasons":["無可驗證資料"]} for k,m in SECTION_MAX.items()}
 if isinstance(stock.get("technical"),dict):sections.update(technical_scores(stock["technical"]))
 total=sum(x["score"] for x in sections.values());missing=[k for k,x in sections.items() if x["status"]=="missing"];confidence="低" if missing else "高"
 rating=rating_for_score(total)
 if missing and rating in ("強勢候選","可觀察"):rating="條件不足（關鍵資料缺失）"
 return {"stock_code":stock.get("stock_code"),"stock_name":stock.get("stock_name"),"sections":sections,"total_score":total,"rating":rating,"confidence":confidence,"missing_sections":missing}
