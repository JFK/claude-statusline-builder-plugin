# claude-statusline-builder

[Claude Code](https://claude.com/claude-code) 用のリッチで設定可能なステータスライン — モデル + コンテキスト + レート制限 + 月額 Anthropic/OpenAI コスト + 天気 + サービスヘルス (Anthropic / GitHub / OpenAI / Cloudflare) + Anthropic ニュース、ワンキーで minimal/detail 切り替え。

外部 HTTP fetch はすべて TTL キャッシュ + バックグラウンド実行なので、フォアグラウンドのレンダリングは毎ターン高速のまま。

```
jfk@laptop:demo-project (main)
🟢gh 🟢cf 🟢oai 🟢Claude Opus 4.6 (1M context)  ctx:234.0k/1.0M(23%)  sess:103.4k
💰 ant:$12.34/M  oai:$3.21/M  5h:41% → 14:00 JST  7d:17% → 金 14:00 JST
☀️ +18°C  💧19%  💨↑15km/h  ☔0.0mm  🧭1017hPa  🌗  🌅05:18  🌇18:07
🕐2026-04-08 (水) 14:05
────────────────────────────────────────────────────────────
📰[1/5] Anthropic expands partnership with Google and Broadcom
   🔗https://www.anthropic.com/news/google-broadcom-partnership-compute
```

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

ガイド付きセットアップ (TZ・天気・プロバイダ・コスト) には builder エージェントを使用してください。

## コマンド

| コマンド | 動作 |
|---|---|
| `/claude-statusline-builder:install` | スクリプトを `~/.claude/statusline-command.sh` にコピーし、既存ファイルをバックアップ、`~/.claude/settings.json` に配線、コメント付き設定テンプレートを配置 |
| `/claude-statusline-builder:toggle` | **minimal** (アイデンティティ + ブランチ + モデル) と **detail** (フル多行) を切り替え。引数なし=フリップ。`minimal` / `detail` / `status` も可 |
| `/claude-statusline-builder:preview` | ダミー JSON ペイロードで一回レンダリング。`minimal` / `detail` でモード強制も可 |
| `/claude-statusline-builder:doctor` | 12項目の診断: 依存・配線・キャッシュ鮮度・環境変数・HTTPS到達性・レンダ・date 互換性。`fix` で修復ヒント |
| `/claude-statusline-builder:config` | `show` (デフォルト) で全設定値とソース表示。`init` でテンプレ生成。`<KEY>` で単一値 |
| `/claude-statusline-builder:uninstall` | バックアップから `settings.json` 復元、スクリプトとモードフラグ削除。`purge` で設定とキャッシュも削除 |

## builder エージェント

サブエージェント名: `claude-statusline-builder:statusline-builder`

ロケール・天気・言語・ヘルスプロバイダ・コスト追跡・レンダリング設定を 4〜8 問で対話的に決定し、`~/.claude/statusline-config.sh` を書き込み、フィクスチャでレンダリング検証まで行うウィザード。

エージェントは管理者 API キーをチャットに入力するよう求めません — `~/.profile` に事前に設定してください。

## 設定

すべての上書きは `~/.claude/statusline-config.sh` (毎回 source される) に書きます。`scripts/statusline-config.sample.sh` がカノニカルなテンプレートです。

### 全環境変数

| 変数 | デフォルト | 備考 |
|---|---|---|
| `STATUSLINE_TZ` | *(システム)* | IANA TZ 名 |
| `STATUSLINE_TZ_LABEL` | *(空)* | リセット時刻のサフィックス |
| `STATUSLINE_LANG` | `en` | `ja` で 月火水木金土日 にマップ |
| `STATUSLINE_DATETIME_FMT` | `%Y-%m-%d (%a) %H:%M` | strftime |
| `STATUSLINE_USER_HOST` | `$USER@$(hostname -s)` | 行1のアイデンティティ |
| `WEATHER_ENABLED` | `1` | `0` で天気行無効 |
| `WEATHER_COORDS` | *(空)* | `lat,lon`。空 = wttr.in IP 検出 |
| `WEATHER_LANG` | `en` | wttr.in 言語コード |
| `WEATHER_TTL` | `1800` | 秒 |
| `NEWS_ENABLED` | `1` | `0` でニュース無効。`python3` 必須 |
| `NEWS_COUNT` | `5` | キャッシュ件数 |
| `NEWS_TITLE_MAX` | `72` | タイトル切り詰め |
| `NEWS_TTL` | `3600` | 秒 |
| `HEALTH_ENABLED` | `1` | `0` でサービスヘルス全無効 |
| `HEALTH_TTL` | `300` | 秒 |
| `HEALTH_PROVIDERS` | `anthropic github openai cloudflare` | スペース区切りリスト |
| `HEALTH_CLOUDFLARE_REGION_FILTER` | *(空)* | IATA 正規表現、例: `NRT\|KIX\|FUK\|OKA` |
| `HEALTH_OPENAI_COMPONENTS` | `Embeddings\|Fine-tuning\|...` | 全名の正規表現 |
| `COST_ENABLED` | `1` | `0` でコスト両方無効 |
| `COST_TTL` | `3600` | 秒 |
| `STATUSLINE_BORDER_CHAR` | `─` | U+2500 |
| `STATUSLINE_BORDER_WIDTH` | `60` | 繰り返し回数 |
| `STATUSLINE_FIELD_SEP` | `  ` | フィールド間 |
| `STATUSLINE_PCT_YELLOW` | `50` | 配色閾値 |
| `STATUSLINE_PCT_MAGENTA` | `75` | 配色閾値 |
| `STATUSLINE_PCT_RED` | `90` | 配色閾値 (太字赤) |
| `STATUSLINE_CACHE_DIR` | `/tmp` | キャッシュディレクトリ |

### 管理者 API キー (任意)

月額コスト表示には管理者スコープの API キーが必要です。`~/.profile` に設定:

```bash
export ANTHROPIC_ADMIN_API_KEY="sk-ant-admin-..."
export OPENAI_ADMIN_API_KEY="sk-admin-..."
```

**コスト省略ルール:** キーが未設定のプロバイダはスロットごと省略されます (`—` ではなく完全に消える)。両方未設定なら `💰` プレフィックス自体が出ません。

`ANTHOROPIC_ADMIN_API_KEY` (タイポ) も後方互換エイリアスとして読まれます。

## サポートプラットフォーム

- **Linux** (Ubuntu / Debian / Arch / Alpine 確認済み)
- **macOS** (GNU `date -d` が無いとき BSD `date -r` にフォールバック)
- **WSL2** (Windows 環境ではこちら推奨。ネイティブ cmd/PowerShell は非対応)

## トラブルシューティング

まず `/claude-statusline-builder:doctor` を実行してください。

## 関連プラグイン

- [claude-c-suite-plugin](https://github.com/JFK/claude-c-suite-plugin)
- [claude-phd-panel-plugin](https://github.com/JFK/claude-phd-panel-plugin)
- [expert-craft-plugin](https://github.com/JFK/expert-craft-plugin)

## ライセンス

[MIT](LICENSE) © Fumikazu Kiyota
