# Claude Session Manager - Development Guidelines

## Core Design Principles

### 1. Session Title Generation Strategy

**Priority Order for Information Extraction:**
1. **Latest conversation first** - Most recent messages contain the most relevant context
2. **First message as fallback** - May contain main instructions but also bulk code paste
3. **Sequential scan from newest** - If above fails, scan backwards for meaningful content

**Rationale:**
- First message might be bulk code paste (not useful for title)
- Latest conversation reflects current work context
- Avoid NG pattern approach - use LLM semantic judgment instead

### 2. Title Validation Approach

**DO NOT use NG pattern matching for title quality**
- NG patterns are fragile and require constant maintenance
- Instead: Use LLM (Haiku) to semantically judge if title is meaningful
- LLM can understand context and determine if text describes actual work

**Implementation:**
1. Extract candidate title using quick heuristics
2. Call LLM to validate: "Is this a meaningful session title? YES/NO"
3. If NO, ask LLM to generate title from session content
4. Cache results in session-names.json

### 3. Performance Requirements

- **Target: < 1 minute per session for AI validation**
- Scan phase: No API calls, pure text extraction
- Validation phase: Only for top 15 displayed sessions
- Use Haiku model for speed (fastest Claude model)

### 4. File Reading Strategy

- Read last N lines first (newest content)
- If no good title found, read first N lines
- Never read entire file (performance)
- Target: 50 lines max per direction

## Technical Notes

### Session Files Location
- `$env:USERPROFILE\.claude\projects\*\*.jsonl`

### Custom Names Storage
- `$env:USERPROFILE\.claude\session-names.json`

### Claude CLI Headless Mode
```powershell
$env:ANTHROPIC_API_KEY = ""
& claude.exe -p "prompt" --model haiku --dangerously-skip-permissions --setting-sources "local"
```

**🚨 CRITICAL: `--setting-sources "local"` 必須**
- グローバルCLAUDE.mdを読み込むと**68秒→5秒**に遅延
- このオプションでグローバル設定を無視し、高速化を実現

## 🚨 CRITICAL CONSTRAINTS (コンテキストロスト対策)

### API制限
- **Claude API直接呼び出しは使用禁止** - 定額制の範囲外になるため
- **使用可能**: Claude CLI headless mode (`-p`オプション) のみ
- Claude CLIは定額制MAXプランに含まれる

### パフォーマンス最適化 (2026-01-17解決済み)

**問題**: グローバルCLAUDE.md読み込みで1回68秒
**解決策**: `--setting-sources "local"` オプション追加
**結果**: 1回5秒に短縮（93%高速化）

| 設定 | 1回の時間 | 10件並列 |
|------|---------|---------|
| デフォルト | 68秒 | 10分+ |
| `--setting-sources ""` | 1秒（動作せず） | - |
| `--setting-sources "local"` | 5秒 | ~10秒 |

### 実装済み機能
- `Get-AITitlesParallel`: 並列AI呼び出し（ファイルI/O方式でエンコード問題回避）
- キャッシュ機能: `session-titles-cache.json`に保存、2回目以降は即座表示
- 最新会話優先: ファイル末尾30行+先頭30行からコンテキスト抽出
- **高速CLI呼び出し**: `--setting-sources "local"` で93%高速化
- **文字化け修正**: `Repair-GarbledText`関数でShift-JIS誤エンコードを自動修復
- **NGタイトルフィルタ**: 「待機中」「準備完了」「セッション終了」等を除外
- **ファイルI/O方式**: コンテキストを一時ファイル経由で渡しエンコード問題軽減

### スキップ条件
- **20行未満のセッション**: AIタイトル生成をスキップ（元のタイトルを維持）
- セッションファイルの書き込みはClaude Code本体の機能であり、このツールでは対応不可

### 文字化け問題について

**問題の発生箇所**:
1. **Claude Code本体のjsonl書き込み時**: ユーザープロンプト（日本語）が文字化けして保存される
   - Assistant応答は正常に保存される（同じファイル内でも差異あり）
   - `/resume`は正常に動作するのに、headless `-p`は文字化けする
2. **このツールのPowerShell→CLI渡し時**: エンコード変換で追加の文字化け発生

**対策**:
- `Repair-GarbledText`関数: Shift-JIS誤エンコードを自動修復試行
- ファイルI/O方式: プロンプトを一時ファイル経由で渡しエンコード問題回避
- Base64エンコード: CLI戻り値の日本語をバイト列で受け取り復元

**限界**:
- 多段エンコード（縺薙・繧ｳ繝ｼ等）: 完全復元不可能
- Claude Code本体側の文字化けバグ: このツールでは修正不可

### 残課題
- [ ] より良いタイトル品質の継続改善

## Change Log

### 2026-01-17 (夜)
- **ファイルI/O方式導入**: プロンプトを一時ファイル経由で渡すことでエンコード問題軽減
- 文字化け問題の詳細分析: Claude Code本体のjsonl書き込み時の問題を特定
- CLAUDE.md更新: 文字化け問題の発生箇所と対策を詳細記載

### 2026-01-17 (後半)
- **🎉 CLI高速化達成**: `--setting-sources "local"` オプション発見
- 1回の呼び出しを68秒→5秒に短縮（93%高速化）
- 10件並列処理が10分以上→約10秒に改善

### 2026-01-17 (前半)
- Document created with core design principles
- Emphasis on LLM-based title validation over NG patterns
- Latest conversation priority established
- Added CRITICAL CONSTRAINTS section for context loss prevention
- Implemented parallel AI calls, caching, hook detection
