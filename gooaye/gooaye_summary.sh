#!/usr/bin/env bash
# 股癌 Podcast 自動摘要腳本
# 流程：RSS → 下載 MP3 → 切割 → Groq Whisper 轉錄 → Groq LLaMA 摘要
# 用法：STT_API_KEY=xxx ./gooaye_summary.sh [集數，預設最新]

set -euo pipefail
export PATH="/home/agent/python/bin:$PATH"

PODCAST_ID="954689a5-3096-43a4-a80b-7810b219cef3"
RSS_URL="https://feeds.soundon.fm/podcasts/${PODCAST_ID}.xml"
CHUNK_SIZE=$((23 * 1024 * 1024))  # 23MB，低於 Groq 25MB 上限
WORK_DIR="/tmp/gooaye"
mkdir -p "$WORK_DIR"

# ── 1. 從 RSS 取得最新集資訊 ──────────────────────────────────────────────
echo "📡 抓取 RSS feed..."
RSS_CONTENT=$(curl -sL "$RSS_URL")

EPISODE_TITLE=$(echo "$RSS_CONTENT" | python3 -c "
import sys, re
content = sys.stdin.read()
titles = re.findall(r'<title><!\[CDATA\[(.*?)\]\]></title>', content)
print(titles[1] if len(titles) > 1 else 'Unknown')
")

MP3_URL=$(echo "$RSS_CONTENT" | python3 -c "
import sys, re
content = sys.stdin.read()
urls = re.findall(r'url=\"(https://[^\"]+\.mp3[^\"]*)\"', content)
print(urls[0] if urls else '')
")

if [[ -z "$MP3_URL" ]]; then
  echo "❌ 找不到 MP3 URL" && exit 1
fi

# 跟隨所有重定向取得最終 URL
REAL_URL=$(curl -sIL "$MP3_URL" | grep -i "^location:" | tail -1 | tr -d '\r' | awk '{print $2}')
[[ -z "$REAL_URL" ]] && REAL_URL="$MP3_URL"

echo "🎙️  集數：$EPISODE_TITLE"
echo "🔗 URL：$REAL_URL"

# ── 2. 下載 MP3 ───────────────────────────────────────────────────────────
MP3_FILE="$WORK_DIR/episode.mp3"
if [[ ! -f "$MP3_FILE" ]]; then
  echo "⬇️  下載中..."
  curl -L --progress-bar -o "$MP3_FILE" "$REAL_URL"
else
  echo "✅ 已有快取：$MP3_FILE"
fi
echo "📦 大小：$(du -h "$MP3_FILE" | cut -f1)"

# ── 3. 切割成 < 23MB 的段落（ffmpeg 按時間切割，每段 20 分鐘）────────────
echo "✂️  切割音訊..."
# 清除舊的 part 檔案
rm -f "$WORK_DIR"/part*.mp3
ffmpeg -v quiet -i "$MP3_FILE" -f segment -segment_time 1200 \
  -c copy "$WORK_DIR/part%d.mp3"
PART_COUNT=$(ls "$WORK_DIR"/part*.mp3 2>/dev/null | wc -l)
echo "共 ${PART_COUNT} 段"

# ── 4. Groq Whisper 轉錄（含 rate limit 重試）────────────────────────────
TRANSCRIPT_FILE="$WORK_DIR/transcript.txt"
> "$TRANSCRIPT_FILE"

ACTIVE_STT_KEY="${GROQ_API_KEY:-$STT_API_KEY}"

transcribe_part() {
  local part_file="$1"
  local part_num="$2"
  local max_retries=5

  for attempt in $(seq 1 $max_retries); do
    echo "  🎤 轉錄 Part $part_num（第 $attempt 次嘗試）..."
    
    RESPONSE=$(curl -s -w "\n__HTTP_CODE__:%{http_code}" \
      -X POST "https://api.groq.com/openai/v1/audio/transcriptions" \
      -H "Authorization: Bearer $ACTIVE_STT_KEY" \
      -F "file=@${part_file};type=audio/mpeg" \
      -F "model=whisper-large-v3-turbo" \
      -F "response_format=text" \
      -F "language=zh")
    
    HTTP_CODE=$(echo "$RESPONSE" | grep "__HTTP_CODE__:" | cut -d: -f2)
    BODY=$(echo "$RESPONSE" | grep -v "__HTTP_CODE__:")
    
    if [[ "$HTTP_CODE" == "200" ]]; then
      echo "$BODY" >> "$TRANSCRIPT_FILE"
      echo "  ✅ Part $part_num 完成"
      return 0
    elif [[ "$HTTP_CODE" == "429" ]]; then
      # 先嘗試切換到備用 key
      if [[ "$ACTIVE_STT_KEY" != "${GROQ_API_KEY_2:-}" ]] && [[ -n "${GROQ_API_KEY_2:-}" ]]; then
        echo "  🔄 切換到備用 GROQ_API_KEY_2..."
        ACTIVE_STT_KEY="$GROQ_API_KEY_2"
        continue
      fi
      WAIT=$(echo "$BODY" | python3 -c "
import sys, json, re
try:
    d = json.load(sys.stdin)
    msg = d.get('error',{}).get('message','')
    m = re.search(r'(\d+)m(\d+)s', msg)
    if m:
        print(int(m.group(1))*60 + int(m.group(2)) + 10)
    else:
        print(300)
except:
    print(300)
" 2>/dev/null || echo 300)
      echo "  ⏳ 兩個 key 均 rate limit，等待 ${WAIT} 秒..."
      sleep "$WAIT"
      # 重試時從主 key 開始
      ACTIVE_STT_KEY="${GROQ_API_KEY:-$STT_API_KEY}"
    else
      echo "  ❌ 錯誤 HTTP $HTTP_CODE：$BODY"
      sleep 10
    fi
  done
  echo "❌ Part $part_num 轉錄失敗" && return 1
}

if [[ -s "$TRANSCRIPT_FILE" ]] && [[ $(wc -l < "$TRANSCRIPT_FILE") -ge "$PART_COUNT" ]]; then
  echo "✅ 已有轉錄快取，跳過"
else
  > "$TRANSCRIPT_FILE"
  PART_NUM=1
  for part in "$WORK_DIR"/part*.mp3; do
    transcribe_part "$part" "$PART_NUM"
    PART_NUM=$((PART_NUM + 1))
  done
fi

echo "📝 轉錄完成，字數：$(wc -w < "$TRANSCRIPT_FILE") 字"

# ── 5. Groq LLaMA 生成摘要（分段處理，避免截斷）────────────────────────
echo "🤖 生成摘要..."

SUMMARY=$(python3 - <<PYEOF
import json, urllib.request, os, textwrap

def groq_chat(messages, max_tokens=2000):
    api_key = os.environ["STT_API_KEY"]
    payload = {
        "model": "llama-3.3-70b-versatile",
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": 0.3
    }
    req = urllib.request.Request(
        "https://api.groq.com/openai/v1/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req) as resp:
        result = json.loads(resp.read())
        return result["choices"][0]["message"]["content"]

transcript = open("/tmp/gooaye/transcript.txt").read()
CHUNK = 12000

chunks = [transcript[i:i+CHUNK] for i in range(0, len(transcript), CHUNK)]

if len(chunks) == 1:
    # 單段直接摘要
    summary = groq_chat([
        {"role": "system", "content": "你是專業的財經 Podcast 摘要助手。請用繁體中文，以結構化方式整理重點。"},
        {"role": "user", "content": f"""以下是股癌 Podcast 的逐字稿，請整理成：

1. **本集主題**（1-2 句）
2. **重點摘要**（5-8 個條列重點）
3. **提到的股票/ETF/市場**
4. **關鍵觀點**（謝孟恭的核心論點）

逐字稿：
{chunks[0]}"""}
    ])
else:
    # 多段：先各自摘要，再合併
    partial_summaries = []
    for i, chunk in enumerate(chunks, 1):
        print(f"  摘要第 {i}/{len(chunks)} 段...", flush=True)
        s = groq_chat([
            {"role": "system", "content": "你是專業的財經 Podcast 摘要助手。"},
            {"role": "user", "content": f"請用繁體中文條列出以下逐字稿的重點（5-8 點）：\n\n{chunk}"}
        ], max_tokens=1000)
        partial_summaries.append(f"【第{i}段】\n{s}")

    combined = "\n\n".join(partial_summaries)
    print("  合併摘要...", flush=True)
    summary = groq_chat([
        {"role": "system", "content": "你是專業的財經 Podcast 摘要助手。請用繁體中文，以結構化方式整理重點。"},
        {"role": "user", "content": f"""以下是股癌 Podcast 各段的重點摘要，請整合成最終版本：

1. **本集主題**（1-2 句）
2. **重點摘要**（5-8 個條列重點）
3. **提到的股票/ETF/市場**
4. **關鍵觀點**（謝孟恭的核心論點）

各段摘要：
{combined}"""}
    ], max_tokens=2000)

print(summary)
PYEOF
)

# ── 6. 輸出結果 ───────────────────────────────────────────────────────────
OUTPUT_FILE="$WORK_DIR/summary.md"
cat > "$OUTPUT_FILE" <<EOF
# 股癌 ${EPISODE_TITLE} 摘要

${SUMMARY}

---
*轉錄時間：$(TZ='Asia/Taipei' date '+%Y-%m-%d %H:%M %Z')*
EOF

echo ""
echo "════════════════════════════════════════"
echo "  📊 股癌 ${EPISODE_TITLE}"
echo "════════════════════════════════════════"
echo ""
echo "$SUMMARY"
echo ""
echo "💾 完整摘要已存至：$OUTPUT_FILE"
echo "📄 完整逐字稿：$TRANSCRIPT_FILE"
