# kiro7 架構討論記錄

> 記錄日期：2026-05-15
> 來源：Discord 對話整理

---

## 一、文件分層架構

### 問題
PITFALLS.md 混雜了兩種性質不同的內容：流程性問題 vs 環境部署問題。

### 結論

| 檔案 | 性質 | 維護者 |
|------|------|--------|
| `agent_skills/README.md` | 通用說明 | 人工，bot 不碰 |
| `agent_skills/PITFALLS.md` | 跨 skill 流程性踩坑 | 人工，bot 不碰 |
| `kiro7/{skill}/skill_readme.md` | skill 專屬 onboarding + 環境 requirement | 該 skill 專屬 |
| `kiro7/{skill}/skill_pitfalls.md` | skill 專屬流程性踩坑 | 該 skill 專屬 |

- 共用文件（上層）只有 Orchestrator / 人工能改，bot 不碰
- 每個 skill 只能寫自己目錄內的檔案
- skill_readme.md 放在程式目錄內，執行時才讀取，隨 git 一起版控

---

## 二、多角色 Agent 架構

### 角色職責

| 角色 | 核心職責 | 主導階段 | 不做的事 |
|------|----------|----------|----------|
| **主人** | 提需求、最終決策（approve PR） | 全程 | 不管技術細節 |
| **Orchestrator** | 理解需求、拆解任務、派工、協調、整合結果 | 全程 | 不親自寫程式、不直接改共用文件 |
| **Producer** | 寫程式、執行 skill、修 bug | 實作、Test | 不 review 自己的程式、不碰共用文件 |
| **Organizer** | 管文件、管 git、維護命名規範、開 PR | Onboarding、收尾 | 不寫程式、不做 review |
| **Reviewer** | review 程式碼、文件、edge case、資安 | Plan/Spec、Test、Onboarding | 不寫程式、不管 git 操作 |

### 各階段主導角色

| 階段 | 主導 | 輔助 |
|------|------|------|
| Plan / Spec | Orchestrator + Reviewer | Producer（顧問） |
| 實作 | Producer | Orchestrator |
| Test | Producer + Reviewer | Orchestrator |
| Onboarding | Organizer + Reviewer | Producer、Orchestrator |
| 維運 | Orchestrator | 視需要 |

### 資安與邊界責任

| 項目 | 主責 |
|------|------|
| Edge case / 邊界條件 | Reviewer |
| API limit / timeout / 系統限制 | Reviewer + Producer |
| Secrets / 權限 / token 外洩 | Reviewer 專屬 |
| 程式碼資安設計 review | Reviewer（Producer 不能自審） |

---

## 三、Token 耗用排序

| 排名 | 角色 | 原因 |
|------|------|------|
| 1 | Reviewer | 需讀完整 context（需求 + diff + 執行結果 + 文件），全程參與 |
| 2 | Orchestrator | 需掌握全局，對話輪次最多 |
| 3 | Organizer | 需讀文件全文，但頻率低 |
| 4 | Producer | 只讀自己負責的程式碼，context 最窄 |
| 5 | 主人 | 只提需求，輸入最短 |

### 降低 Token 消耗做法

- Reviewer：只傳 diff，不傳整份檔案；review checklist 化
- Orchestrator：各角色只回傳摘要，不傳完整 log
- 共用文件保持精簡，避免堆積過時資訊
- 每個角色的 system prompt 只包含該角色需要的資訊

---

## 四、GitHub 目錄權限問題

### 現況

| Repo | 路徑 | 目前誰在 push |
|------|------|--------------|
| `agent_skills` | `C:\openab\agent_skills` | kiro7 bot 直接 push |
| `goodinfo-scraper` | `C:\openab\goodinfo-scraper` | goodinfo-trust bot 直接 push（token 明文在 remote URL） |

### 發現的問題

1. **goodinfo-scraper token 明文硬寫在 `.git/config` remote URL** — 資安死角，任何能讀該目錄的人都能拿到 token
2. **agent_skills 無 token 保護** — 靠 gh CLI session，過期後靜默失敗

### 建議的權限區分

| Repo | 誰能 push | 誰能 pull |
|------|-----------|-----------|
| `agent_skills` | Orchestrator / 人工 | 所有 bot |
| `goodinfo-scraper` | goodinfo-trust bot 專屬 | goodinfo-trust bot |
| 未來各 skill repo | 各 skill bot 專屬 | 各自 |

---

## 五、避免多 Bot 亂覆寫的建議

### 第一層：目錄隔離（規範層，現在就能做）
- 每個 skill 只能碰自己的 repo
- `agent_skills` bot 只 pull，不 push

### 第二層：Fine-grained Personal Access Token（物理隔離，優先處理）
- 每個 skill 申請獨立 token
- 只授權自己的 repo、只給 `Contents: Write`
- 物理上無法 push 到別人的 repo

### 第三層：Branch Protection（適用 agent_skills）
- `main` 需要 PR 才能 merge
- bot push 到 feature branch，Orchestrator / 人工 approve 後 merge
- 資料 repo（goodinfo-scraper 類）維持直接 push main

### 建議優先順序

| 措施 | 適用 | 優先級 |
|------|------|--------|
| 目錄隔離規範 | 全部 | 立即 |
| Fine-grained token 各自獨立 | 全部 | 高 |
| goodinfo-scraper token 移出 remote URL | goodinfo-scraper | 高（資安） |
| branch protection on main | `agent_skills` | 中 |

---

## 六、待決定事項

- [ ] 四個角色是用不同 Kiro session 扮演，還是同一個 kiro7 切換？
- [ ] Reviewer 介入的觸發條件是什麼？
- [ ] 角色架構是否寫進 `AGENTS.md`？
- [ ] goodinfo-scraper token 何時從 remote URL 移出？
- [ ] goodinfo-joint 是否建立獨立 repo？
