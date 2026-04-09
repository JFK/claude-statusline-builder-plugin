# claude-statusline-builder

[Claude Code](https://claude.com/claude-code) 用のリッチで設定可能なステータスライン — モデル + コンテキストウィンドウ (バーン率付き) + レート制限 + 月額 **および** 今日/時間ごとの Anthropic/OpenAI コスト + git 作業ツリー状態 + GitHub Actions CI ステータス + 天気 + サービスヘルス (Anthropic / GitHub / OpenAI / Cloudflare) + Anthropic ニュース見出し、ワンキーで minimal/detail 切り替え。

外部 HTTP fetch はすべて TTL キャッシュ + バックグラウンド実行なので、フォアグラウンドのレンダリングは毎ターン高速のまま。

```
jfk@laptop:claude-statusline-builder-plugin (main ●2 ↑1 🟢ci)
🟢gh 🟢cf 🟢oai 🟢Claude Opus 4.6 (1M context)  ctx:234.0k/1.0M(23% +12.4k/turn)
💰 ant:$12.34/M  oai:$3.21/M  today:$1.45  $0.12/h  5h:41% → 14:00 JST  7d:17% → 金 14:00 JST
🕐 2026-04-09 (木) 14:05 JST
☀️ +18°C (↓9/↑17°C)  💧19%  💨↑15km/h  ☔0.0mm  🧭1017hPa  🌗  🌅05:18  🌇18:07
明日 ⛅ 10/19°C ☔0%  明後日 🌧 14/20°C ☔100%
────────────────────────────────────────────────────────────
📰[1/5] Anthropic expands partnership with Google and Broadcom
   🔗https://www.anthropic.com/news/google-broadcom-partnership-compute
```

表示される各フィールドは、データが無い場合は自動的に消えます — クリーンな repo では `●/±/↑/↓` が出ず、CI 設定が無い repo では `🟢ci` が出ず、管理者キーが未設定なら `💰` プレフィックスごと出ません。プレースホルダ (`—` や `N/A`) で埋めることは一切ありません。

## 60秒クイックスタート

```
/plugin marketplace add JFK/claude-statusline-builder-plugin
/plugin install claude-statusline-builder
/claude-statusline-builder:install
/claude-statusline-builder:preview
```

以上です。次の Claude Code ターンからステータスラインが表示されます。minimal と detail を切り替えるには:

```
/claude-statusline-builder:toggle
```

ガイド付きセットアップ (タイムゾーン・天気・プロバイダ・コスト追跡) には builder エージェントを使用してください — Claude Code が自動的に提案してくれるか、「use the statusline-builder agent to configure my statusline」と明示的に指示すれば起動できます。

## コマンド

| コマンド | 動作 |
|---|---|
| `/claude-statusline-builder:install` | スクリプトを `~/.claude/statusline-command.sh` にコピーし、既存ファイルをバックアップ、`~/.claude/settings.json` に配線、コメント付き設定テンプレートを配置 |
| `/claude-statusline-builder:toggle` | **minimal** (アイデンティティ + ブランチ + モデル + レート制限) と **detail** (フル多行) を切り替え。引数なし=フリップ。`minimal` / `detail` / `status` も可 |
| `/claude-statusline-builder:preview` | ダミー JSON ペイロードで一回レンダリング。`minimal` / `detail` でモード強制も可 |
| `/claude-statusline-builder:doctor` | 12項目の診断: 依存・`settings.json` 配線・キャッシュ鮮度・環境変数・HTTPS到達性・フィクスチャレンダ・`date` 互換性。`fix` で修復ヒント |
| `/claude-statusline-builder:config` | `show` (デフォルト) で全設定値とソース表示 (ユーザー設定 vs デフォルト)。`init` でテンプレ生成。`<KEY_NAME>` で単一値 |
| `/claude-statusline-builder:uninstall` | バックアップから `~/.claude/settings.json` 復元、インストール済みスクリプトとモードフラグ削除。`purge` で設定ファイルと `/tmp` キャッシュも削除 |

## builder エージェント

サブエージェント名: `claude-statusline-builder:statusline-builder`

ロケール・天気・言語・ヘルスプロバイダ・コスト追跡・レンダリング設定を 4〜8 問で対話的に決定し、`~/.claude/statusline-config.sh` を書き込み、フィクスチャでレンダリング検証まで行うウィザード。bash の設定を手で書くよりガイド付きセットアップが欲しいときに使用してください。

エージェントは管理者 API キーをチャットに入力するよう求めません — それらは `~/.profile` (または bash が source するファイル) に事前に設定してください。

## 設定

すべての上書きは `~/.claude/statusline-config.sh` (スクリプトが毎回 source する) に書きます。プラグインの `scripts/statusline-config.sample.sh` がカノニカルなテンプレートで、`/install` と `/config init` がこれを生成します。

### 全環境変数

| 変数 | デフォルト | 備考 |
|---|---|---|
| `STATUSLINE_TZ` | *(システム)* | IANA タイムゾーン、例: `Asia/Tokyo` |
| `STATUSLINE_TZ_LABEL` | *(自動)* | リセット/時計行のサフィックス、例: `JST`。未設定なら `date +%Z` で自動検出。`""` で抑制 |
| `STATUSLINE_LANG` | `en` | `ja` で 月火水木金土日 の曜日マッピング、および天気予報行の「明日/明後日」を有効化 |
| `STATUSLINE_DATETIME_FMT` | `%Y-%m-%d (%a) %H:%M` | 時計行の strftime フォーマット |
| `STATUSLINE_USER_HOST` | `$USER@$(hostname -s)` | 行1のアイデンティティ。`user == host` の場合、git repo 内なら `$USER` のみに、repo 外なら `$USER@<pwd basename>` にフォールバック |
| `GIT_DIRTY_ENABLED` | `1` | `0` でブランチ名横の `●N ±N ↑N ↓N` 作業ツリー状態を非表示。クリーンな repo ではどちらにせよ何も出ません |
| `CTX_BURN_ENABLED` | `1` | `0` で `ctx:…%` 横の `+X.Xk/turn` コンテキストバーン率を非表示 |
| `CTX_BURN_WINDOW` | `5` | バーン率平均のスライディングウィンドウサイズ (セッションごとのサンプル数) |
| `CTX_BURN_MIN_DELTA` | `1000` | この値未満 (tokens/turn) のときバーン率を抑制するノイズフロア |
| `CI_ENABLED` | `1` | `0` でブランチ名横の `🟢ci / 🟡ci / 🔴ci / ⚪ci` GitHub Actions インジケータを非表示。`gh` CLI + 認証済みセッションが必要 |
| `CI_TTL` | `120` | 秒。GitHub のレート制限に優しい値 |
| `WEATHER_ENABLED` | `1` | `0` で天気行無効 |
| `WEATHER_COORDS` | *(空)* | `lat,lon`。空 = wttr.in の IP 検出 |
| `WEATHER_LANG` | `en` | wttr.in 言語コード |
| `WEATHER_TTL` | `1800` | 秒 |
| `WEATHER_FORECAST_ENABLED` | `1` | `0` で今日の最低/最高気温 **と** 明日/明後日の予報行を両方無効化 |
| `WEATHER_FORECAST_TTL` | `10800` | 秒。予報は変化が遅いので 3h キャッシュ |
| `NEWS_ENABLED` | `1` | `0` で Anthropic ニュース無効。`python3` 必須 |
| `NEWS_COUNT` | `5` | キャッシュ件数、レンダリングごとに 1 件ローテーション |
| `NEWS_TITLE_MAX` | `72` | N 文字より長いタイトルを切り詰め |
| `NEWS_TTL` | `3600` | 秒 |
| `HEALTH_ENABLED` | `1` | `0` で 4 プロバイダすべてのサービスヘルス行を無効化 |
| `HEALTH_TTL` | `300` | 秒 |
| `HEALTH_PROVIDERS` | `anthropic github openai cloudflare` | スペース区切りリスト。不要なプロバイダは外せます |
| `HEALTH_CLOUDFLARE_REGION_FILTER` | *(空)* | IATA コードの正規表現、例: `NRT\|KIX\|FUK\|OKA` (日本の PoP) |
| `HEALTH_OPENAI_COMPONENTS` | `Embeddings\|Fine-tuning\|Audio\|Images\|Batch\|Moderations` | コンポーネント名の正規表現 |
| `COST_ENABLED` | `1` | `0` で月額コスト両スロット無効 |
| `COST_TTL` | `3600` | 秒 |
| `COST_BURN_ENABLED` | `1` | `0` で請求行の `today:$X.XX` と `$Y.YY/h` バーン率セグメントを非表示 |
| `COST_BURN_TTL` | `120` | 秒。`COST_TTL` より短い (ローリングウィンドウのケイデンスに合わせる) |
| `COST_BURN_HOUR_WINDOW` | `1` | `$/h` フィールドで平均する時間数 |
| `STATUSLINE_BORDER_CHAR` | `─` | U+2500。古い端末では `-` を使用 |
| `STATUSLINE_BORDER_WIDTH` | `60` | 繰り返し回数 |
| `STATUSLINE_FIELD_SEP` | `  ` (スペース 2 つ) | フィールド間の区切り |
| `STATUSLINE_PCT_YELLOW` | `50` | 配色ランプの閾値 |
| `STATUSLINE_PCT_MAGENTA` | `75` | 配色ランプの閾値 |
| `STATUSLINE_PCT_RED` | `90` | 配色ランプの閾値 (太字赤) |
| `STATUSLINE_CACHE_DIR` | `/tmp` | TTL キャッシュファイルの保存先 |

### 管理者 API キー (任意)

月額コストスロット、および今日/時間ごとのバーン率スロットには、追跡したいプロバイダの管理者スコープ API キーが必要です。`~/.profile` に設定してください:

```bash
export ANTHROPIC_ADMIN_API_KEY="sk-ant-admin-..."   # console.anthropic.com → Admin API
export OPENAI_ADMIN_API_KEY="sk-admin-..."           # platform.openai.com → API Keys → Admin
```

**コスト省略ルール**: キーが未設定のプロバイダのスロットは完全に省略されます (`—` 等ではなく、そもそも出ません)。両方未設定なら請求行の `💰` プレフィックス自体が出ず、レート制限のみが表示されます。

`ANTHOROPIC_ADMIN_API_KEY` (タイポ) も後方互換エイリアスとして受け付けます — 古いシェル設定でこの綴りを使っているユーザー向け。

## 高速性を保つ仕組み

- **フォアグラウンドの jq 呼び出しは 1 回だけ** — ステータスライン JSON の解析はそれだけで、残りはすべて bash 組み込み
- **すべての HTTP fetch は `( ... ) & disown` バックグラウンドサブシェル** で実行、`--max-time` 制限とアトミックな `tmp → mv` キャッシュ書き込み付き
- **コールドスタート**: 5〜10 秒でキャッシュが埋まる。**ウォームレンダー**: 事前取得済みファイルを読むだけ
- **minimal モード** はバックグラウンド fetch ロジックの前でショートサーキット — コールドスタートでもサブ 30ms

## 依存関係

**必須**: `bash`, `jq`, `curl`, `git`, `awk`, `date` — サポート対象プラットフォームにはすべてデフォルトで存在します。

**任意**:
- `python3` — Anthropic ニュースローテーション行を有効化します。Python が無ければニュース行が出ないだけで、他はすべて動作します。
- `gh` (GitHub CLI) — ブランチ名横の `🟢ci / 🟡ci / 🔴ci` インジケータを有効化します。`gh` が無い、または未認証ならその行が出ないだけで、他は動作します。

## サポートプラットフォーム

- **Linux** (Ubuntu / Debian / Arch / Alpine で確認済み)
- **macOS** (GNU `date -d` が無いとき BSD `date -r` にフォールバック)
- **WSL2** (Windows ではこちら推奨。ネイティブ cmd/PowerShell は非対応)

## トラブルシューティング

まず `/claude-statusline-builder:doctor` を実行してください。最もよくある問題 (`jq`/`curl` 欠落、`settings.json` 未配線、キャッシュ陳腐化、HTTPS ブロック) をワンライナーヒント付きで表面化します。`doctor fix` は修復提案も追加します。

ステータスライン自体はレンダリングされるが特定の行が出ない場合:

- **天気行が出ない** → `WEATHER_ENABLED=1` を確認、`wttr.in` に到達できるか確認
- **ニュース行が出ない** → `python3` が PATH 上に必要。`python3 --version` が動くか確認
- **コストが出ない** → そのプロバイダの管理者キーが未設定 (これはバグではなく意図的な挙動)
- **請求行に `today:$X` や `$X/h` が出ない** → フレッシュなキャッシュか 2 分の TTL がまだ切れていないだけ。管理者課金 API は直近 24〜48 時間分のデータが遅延することがあります
- **ブランチ横に `🟢ci` が出ない** → `gh auth status` が成功している必要あり、ブランチにランが存在している必要あり、フレッシュセッション直後は最大 `CI_TTL` 秒かかります
- **モデル行に `+X.Xk/turn` が出ない** → セッション最初の 2 回のレンダーはサンプル不足で抑制 (仕様)、`CTX_BURN_MIN_DELTA` 未満のデルタもノイズとして抑制
- **サービスヘルス行が出ない** → `HEALTH_PROVIDERS` にそのプロバイダが含まれているか、`*.statuspage.io` ミラーへの HTTPS 通信が可能かを確認

## セキュリティ

完全な脅威モデルは [SECURITY.md](SECURITY.md) を参照してください (英語)。要点:

- スクリプトは環境変数から管理者 API キーを読みますが、**stdout, stderr, チャット出力には一切エコーしません**
- `/tmp` のキャッシュファイルには公開されているヘルス/天気/ニュースデータと、数値の月額/今日/時間ごとのコスト合計のみが入ります — 機密情報は一切含まれません
- 請求データを含むキャッシュ (`monthly-cost`, `cost-burn`) と、セッション使用パターンを含むキャッシュ (`ctx-history`) は `umask 077` で 0600 モードで書かれます — 共有マシン上の他ユーザーからは読めません
- テレメトリは一切ありません。スクリプトが「phone home」することはありません

## 関連プラグイン

同じく [@JFK](https://github.com/JFK) が作成した MIT ライセンスの Claude Code プラグインエコシステムの一部です:

- [claude-c-suite-plugin](https://github.com/JFK/claude-c-suite-plugin) — CEO/CTO/CSO/PM レビュースキル
- [claude-phd-panel-plugin](https://github.com/JFK/claude-phd-panel-plugin) — 学術レビュースキル (CS, DB, 統計 …)
- [expert-craft-plugin](https://github.com/JFK/expert-craft-plugin) — カスタム専門家レビュースキルの作成・削除

## ライセンス

[MIT](LICENSE) © Fumikazu Kiyota
