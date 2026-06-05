# RWA-STO 雙智能體台股量化選股系統

兩個 AI 智能體交叉驗證,每日產出多空各 10 檔,平台收益 70% 經智能合約分潤給社群。

## 目錄結構

```
quant_system/
├── schema.sql              # PostgreSQL 資料表 (財報/量價/精選/用戶分紅)
├── agent_a_altman.py       # Agent A：Altman Z-Score 違約風險
├── agent_b_quant.py        # Agent B：MA20 + 主力買超 籌碼驗證
├── data_source.py          # 資料源介面 (目前 Mock，可換真實 API/DB)
├── decision_engine.py      # 中央決策引擎 → 多空各 10 檔 → picks.json
├── picks.json              # 引擎輸出 (board.html 讀取)
├── requirements.txt
└── contracts/
    └── RWAProfitSharing.sol  # 70% 分潤合約 (已修正並強化安全性)
../board.html                 # 多空選股看板前端
```

## 快速開始 (本機跑通)

```bash
pip install -r requirements.txt
python3 decision_engine.py      # 產生 picks.json 並印出多空清單
```

用瀏覽器開啟 `board.html` 即可看到看板(已內嵌後備資料;同源部署時會自動讀 picks.json)。

## 工作流

```
數據源 → Agent A (Z-Score 篩預警) → Agent B (籌碼/均線交叉驗證)
       → 中央決策引擎 (多空各10檔) → RWA-STO 合約 (70% 派發用戶)
```

### 篩選邏輯
- **多頭潛力榜**:Z > 2.99 且 Agent B = `STRONG_BUY`,依主力買超由高到低取 10。
- **空頭風險榜**:Z < 1.81 且 Agent B = `STRONG_SHORT`,依 Z-Score 由低到高取 10。

## Altman Z-Score
`Z = 1.2·X1 + 1.4·X2 + 3.3·X3 + 0.6·X4 + 0.999·X5`
(X1 營運資金/總資產、X2 保留盈餘/總資產、X3 EBIT/總資產、X4 市值/總負債、X5 營收/總資產)
分級:>2.99 健康 · 1.81~2.99 灰色 · <1.81 高違約風險。

## 從 Mock 換成真實資料
把 `data_source.py` 的 `MockDataSource` 換成串接：
- 財報:證交所 OpenAPI / 第三方金融數據 API → 寫入 `company_financials`
- 量價籌碼:每日收盤同步 → 寫入 `daily_market`
介面 (`get_universe / get_financials / get_kline / get_chip`) 不變,引擎無需改動。

## 智能合約重點修正(對照原始草稿)
1. **修 BUG**:原稿 `updateContribution` 誤用 Python 的 `def`,Solidity 須為 `function`。
2. **修 gas DoS**:原稿用 `for` 迴圈一次發給所有用戶,用戶一多會 Out-of-Gas、且可被惡意地址灌爆。改為 **快照 + 用戶自行 `claim`** 的 pull-payment 標準模式。
3. **加安全**:`nonReentrant` 防重入、checks-effects-interactions 順序、`transfer/transferFrom` 回傳值檢查、admin 可轉移(建議改多簽)。

## 排期 (Milestones)
- **第 1–2 週**:建資料庫 + 對接證交所/金融 API,每日傍晚自動同步。
- **第 3–4 週**:部署 Agent A/B 與決策引擎,Cron 每日收盤後跑模型產清單。
- **第 5–6 週**:APP 看板上線;Solidity 合約部署測試網,串 MetaMask,用戶查積分與預估 70% 收益。

## ⚠ 重要聲明
本系統為**研究與工程參考**,程式輸出**不構成投資建議或獲利保證**;量化模型有侷限、可能失準,交易風險高。STO/RWA 涉及證券法規,實際發行前須完成合規程序並對智能合約做第三方審計。請諮詢合格法律與財務顧問。
