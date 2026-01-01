# Mastodon バックアップスクリプト

Mastodon の PostgreSQL と Redis データベースを自動バックアップし、rclone 経由で Backblaze B2 クラウドストレージに統合するスクリプトです。

## 機能

- ✅ **PostgreSQL と Redis データベースの自動日次バックアップ**
- ✅ **月次アーカイブバックアップ**（毎月1日に自動実行）
- ✅ **rclone 経由での Backblaze B2 クラウドストレージ**
- ✅ **古いバックアップの自動クリーンアップ**（保持期間の設定が可能）
- ✅ **タイムスタンプ付きファイル名での手動バックアップモード**
- ✅ **ドライランモード**（実際のバックアップ/アップロードなしでテスト可能）
- ✅ **セキュリティ重視**（設定を分離し、秘密情報をハードコードしない）
- ✅ **包括的なエラーハンドリング**（詳細なログ出力）

## 要件

- **オペレーティングシステム**: Linux（Ubuntu/Debian でテスト済み）
- **Mastodon**: 全バージョン
- **PostgreSQL**: 12+（postgres ユーザーのピア認証が必要）
- **Redis**: 5+
- **rclone**: 最新バージョン
- **Bash**: 4.3+

## クイックスタート

### 1. rclone のインストール

```bash
# 公式インストールスクリプト
curl https://rclone.org/install.sh | sudo bash

# またはパッケージマネージャーを使用
sudo apt install rclone  # Debian/Ubuntu
```

### 2. Backblaze B2 の設定

#### B2 認証情報の取得

1. [Backblaze](https://www.backblaze.com/) にログイン
2. **B2 Cloud Storage** → **App Keys** に移動
3. **Add a New Application Key** をクリック
   - Key Name: `mastodon-backup`（または任意の名前）
   - Allow access to Bucket(s): バックアップ用のバケットを選択、または「All」
   - Type of Access: Read and Write
4. **重要**: **Application Key** をすぐに保存（一度だけ表示されます！）
5. 以下をメモ：
   - Account ID（または Application Key ID）
   - Application Key（シークレット）

#### B2 バケットの作成

1. [B2 Buckets](https://www.backblaze.com/b2/buckets.html) にアクセス
2. 2つのバケットを作成：
   - **daily-db-backup**（日次バックアップ用）
   - **monthly-db-backup**（月次アーカイブバックアップ用）
3. バケット設定：
   - Files in Bucket: **Private**
   - Default Encryption: **Enable**（推奨）
   - Object Lock: オプション（コンプライアンス要件がある場合）

#### rclone の設定

```bash
rclone config
```

対話式プロンプトに従ってください：

```
n) New remote
name> remote_b2_account_credentials
Storage> b2
account> [Account ID または Application Key ID を貼り付け]
key> [Application Key を貼り付け]
# 残りのオプションはデフォルトのまま
```

#### rclone 設定の確認

```bash
# 設定済みリモートの一覧表示
rclone listremotes
# 期待される出力: remote_b2_account_credentials:

# バケットの一覧表示
rclone lsd remote_b2_account_credentials:
# 期待される出力: daily-db-backup, monthly-db-backup が表示される

# アップロードのテスト
echo "test" > /tmp/test.txt
rclone copy /tmp/test.txt remote_b2_account_credentials:/daily-db-backup/
rclone ls remote_b2_account_credentials:/daily-db-backup/
# test.txt が表示されるはず

# テストファイルのクリーンアップ
rclone delete remote_b2_account_credentials:/daily-db-backup/test.txt
rm /tmp/test.txt
```

### 3. クローンと設定

```bash
# リポジトリのクローン
cd /home/mastodon/
git clone https://github.com/mimikun/mastodon-backup-script.git
cd mastodon-backup-script

# 設定テンプレートのコピー
cp backup.conf.example backup.conf

# 設定の編集
nano backup.conf
# 必要に応じてパス、データベース名、バケット名を更新

# パーミッションの設定
chmod 600 backup.conf
chmod 700 backup.sh
```

### 4. バックアップのテスト

```bash
# ドライランテスト（実際のバックアップ/アップロードなし）
./backup.sh --dry-run

# 手動バックアップテスト（'_manual' サフィックス付きでバックアップを作成）
./backup.sh --manual
```

### 5. 自動バックアップのスケジュール設定（systemd タイマー）

```bash
# systemd サービスとタイマーファイルのインストール
sudo cp services/mastodon-backup.service /etc/systemd/system/
sudo cp services/mastodon-backup.timer /etc/systemd/system/

# systemd をリロードして新しいファイルを認識させる
sudo systemctl daemon-reload

# タイマーを有効化して起動（毎日午前2時に実行）
sudo systemctl enable mastodon-backup.timer
sudo systemctl start mastodon-backup.timer

# タイマーの状態を確認
sudo systemctl status mastodon-backup.timer

# すべてのアクティブなタイマーを一覧表示
systemctl list-timers --all | grep mastodon-backup
```

## 使い方

### コマンドラインオプション

```bash
./backup.sh [OPTIONS]

オプション:
  --manual    手動モードで実行（バックアップファイル名に '_manual' を追加）
  --dry-run   テストモード - 実際のバックアップ/アップロードなしで実行内容を表示
  -h, --help  ヘルプメッセージを表示
```

### 使用例

```bash
# 自動日次バックアップ（デフォルト）
./backup.sh

# タイムスタンプ付きファイル名での手動バックアップ
./backup.sh --manual

# 実際のバックアップ/アップロードなしのテスト実行
./backup.sh --dry-run

# オプションの組み合わせ: 手動ドライラン
./backup.sh --manual --dry-run
```

## 設定

### 設定ファイル

- **`backup.conf`**: アクティブな設定（git から除外）
- **`backup.conf.example`**: 詳細なドキュメント付きテンプレート

### systemd ファイル

- **`services/mastodon-backup.service`**: systemd サービスユニットファイル
- **`services/mastodon-backup.timer`**: systemd タイマーユニットファイル（午前2時に日次バックアップをスケジュール）

### 主要な設定オプション

| オプション | 説明 | デフォルト |
|--------|-------------|---------|
| `MASTODON_HOME` | Mastodon インストールディレクトリ | `/home/mastodon/live` |
| `BACKUP_DIR` | ローカルバックアップ保存ディレクトリ | `/home/mastodon/backups` |
| `PG_DBNAME` | PostgreSQL データベース名 | `postgres` |
| `RCLONE_REMOTE_DAILY` | 日次バックアップ用 rclone リモート | `remote_b2_account_credentials` |
| `RCLONE_REMOTE_MONTHLY` | 月次バックアップ用 rclone リモート | `remote_b2_account_credentials` |
| `B2_BUCKET_DAILY` | 日次バックアップ用 B2 バケット | `daily-db-backup` |
| `B2_BUCKET_MONTHLY` | 月次バックアップ用 B2 バケット | `monthly-db-backup` |
| `REMOTE_RETENTION_DAYS` | リモートバックアップの保持日数 | `3` |
| `LOCAL_RETENTION_DAYS` | ローカルバックアップの保持日数 | `7` |

## 仕組み

### バックアッププロセス

1. **初期化**
   - `backup.conf` から設定を読み込み
   - rclone 設定を検証
   - 必要に応じてバックアップディレクトリを作成

2. **PostgreSQL バックアップ**
   - `pg_dump`（カスタムフォーマット）を使用してデータベースをダンプ
   - ローカルバックアップディレクトリに保存

3. **Redis バックアップ**
   - `redis-cli --rdb` を使用して RDB スナップショットを作成
   - ローカルバックアップディレクトリに保存

4. **B2 へのアップロード**
   - PostgreSQL と Redis のバックアップを Backblaze B2 にアップロード
   - 日付に基づいて適切なバケットを使用（日次 vs 月次）

5. **クリーンアップ**
   - `REMOTE_RETENTION_DAYS` より古いリモートバックアップを削除
   - `LOCAL_RETENTION_DAYS` より古いローカルバックアップを削除

### 月次 vs 日次バックアップ

- **日次バックアップ**: 毎日自動実行、`daily-db-backup` バケットに保存
- **月次バックアップ**: 毎月1日に自動実行、`monthly-db-backup` バケットに保存
- 両方とも同じ保持ポリシーを使用しますが、整理のために別々のバケットを使用

### ファイル命名規則

```
PostgreSQL: pg_backup_YYYY_MM_DD[_manual]
Redis:      redis_backup_YYYY_MM_DD[_manual]
```

例: `pg_backup_2026_01_15` または `redis_backup_2026_01_01_manual`

## リストア

### PostgreSQL データベースのリストア

```bash
# Mastodon サービスを停止
sudo systemctl stop mastodon-*.service

# B2 からバックアップをダウンロード
rclone copy remote_b2_account_credentials:/daily-db-backup/pg_backup_2026_01_15 /tmp/

# 既存のデータベースを削除（注意してください！）
sudo -u postgres dropdb postgres

# 新しいデータベースを作成
sudo -u postgres createdb postgres

# バックアップからリストア
sudo -u postgres pg_restore -d postgres /tmp/pg_backup_2026_01_15

# Mastodon サービスを起動
sudo systemctl start mastodon-*.service
```

### Redis データベースのリストア

```bash
# Redis を停止
sudo systemctl stop redis

# B2 からバックアップをダウンロード
rclone copy remote_b2_account_credentials:/daily-db-backup/redis_backup_2026_01_15 /var/lib/redis/dump.rdb

# 正しいパーミッションを設定
sudo chown redis:redis /var/lib/redis/dump.rdb

# Redis を起動
sudo systemctl start redis
```

## トラブルシューティング

### rclone リモートが見つからない

**エラー**: `Error: rclone remote 'remote_b2_account_credentials' not found`

**解決方法**:
1. 設定済みリモートを確認: `rclone listremotes`
2. 必要に応じて再設定: `rclone config`
3. `backup.conf` を正しいリモート名で更新

### バケットが見つからない

**エラー**: `Warning: Bucket 'daily-db-backup' not found`

**解決方法**:
1. バケットを確認: `rclone lsd remote_b2_account_credentials:`
2. Backblaze B2 Web インターフェースで不足しているバケットを作成
3. `backup.conf` を正しいバケット名で更新

### パーミッション拒否エラー

**エラー**: バックアップ実行時に `Permission denied`

**解決方法**:

```bash
# PostgreSQL バックアップ用（postgres ユーザーに sudo が必要）
sudo visudo
# 追加: mastodon ALL=(postgres) NOPASSWD: /usr/bin/pg_dump

# スクリプト実行用
chmod 700 backup.sh
```

### バックアップ検証の失敗

**問題**: バックアップの整合性を確認したい

**解決方法**:

```bash
# PostgreSQL バックアップのテスト
pg_restore --list /path/to/pg_backup_file

# Redis バックアップのテスト（ファイルサイズとフォーマットを確認）
file /path/to/redis_backup_file
# 表示されるべき内容: "Redis RDB file"
```

### systemd タイマーが実行されない

**エラー**: タイマーは有効だがバックアップが実行されない

**解決方法**:

```bash
# タイマーの状態を確認
sudo systemctl status mastodon-backup.timer

# タイマーの次回実行時刻を確認
systemctl list-timers --all | grep mastodon-backup

# サービスを手動でトリガー（テスト用）
sudo systemctl start mastodon-backup.service

# サービスログを表示
sudo journalctl -u mastodon-backup.service -n 50

# 必要に応じてタイマーを再起動
sudo systemctl restart mastodon-backup.timer
```

### systemd サービスが失敗する

**エラー**: サービスがエラーコードで終了

**解決方法**:

```bash
# 詳細なサービスステータスを確認
sudo systemctl status mastodon-backup.service -l

# 完全なログを表示
sudo journalctl -u mastodon-backup.service --no-pager

# ファイルパーミッションを確認
ls -la /home/mastodon/mastodon-backup-script/backup.sh
# 実行可能であるべき: -rwx------

# サービスファイル内の User/Group を確認
sudo cat /etc/systemd/system/mastodon-backup.service | grep -E "User|Group"
# Mastodon ユーザーと一致するべき

# サービスユーザーとしてスクリプトを手動でテスト
sudo -u mastodon /home/mastodon/mastodon-backup-script/backup.sh --dry-run
```

## セキュリティのベストプラクティス

### ファイルパーミッション

```bash
chmod 600 backup.conf                          # 所有者のみ読み書き
chmod 700 backup.sh                            # 所有者のみ実行
chmod 600 ~/.config/rclone/rclone.conf         # 所有者のみ rclone 設定を読み取り
```

### Backblaze B2 セキュリティ

- ✅ バックアップバケットのみにアクセスできる制限付き Application Key を使用
- ✅ サーバーに静的 IP がある場合は IP 制限を有効化
- ✅ Application Key を定期的にローテーション（90日ごとを推奨）
- ✅ バケット設定でサーバーサイド暗号化を有効化
- ✅ コンプライアンス要件がある場合は Object Lock を有効化（オプション）

### モニタリング

- ✅ バックアップログを定期的に確認
- ✅ バックアップ失敗時のモニタリング/アラートを設定（例: cron メール経由）
- ✅ バックアップからのリストアを定期的にテスト（月次推奨）
- ✅ B2 バケットサイズとコストを監視

### 暗号化オプション

**サーバーサイド暗号化**（推奨）:
- B2 バケット設定で有効化
- 透過的な暗号化/復号化
- パフォーマンスへの影響なし

**rclone crypt**（高度）:
- アップロード前のクライアントサイド暗号化
- より細かい制御が可能だが追加設定が必要
- 参照: https://rclone.org/crypt/

## 高度な使い方

### カスタム保持期間

`backup.conf` を編集:

```bash
# リモートバックアップを7日間保持
REMOTE_RETENTION_DAYS=7

# ローカルバックアップを14日間保持
LOCAL_RETENTION_DAYS=14
```

### 複数環境

環境固有の設定を作成:

```bash
cp backup.conf backup.conf.production
cp backup.conf backup.conf.staging

# 特定の設定を使用
CONFIG_FILE=backup.conf.staging ./backup.sh
```

### ロギング

**systemd ログの表示:**

```bash
# 最近のバックアップログを表示
sudo journalctl -u mastodon-backup.service -n 50

# ログをリアルタイムでフォロー
sudo journalctl -u mastodon-backup.service -f

# 特定の日付のログを表示
sudo journalctl -u mastodon-backup.service --since "2026-01-01" --until "2026-01-02"

# ログをファイルにエクスポート
sudo journalctl -u mastodon-backup.service > /var/log/mastodon-backup.log
```

**ロギング付き手動実行:**

```bash
./backup.sh 2>&1 | tee -a /var/log/mastodon-backup.log
```

### 通知

**メール通知**（systemd 経由）:

`/etc/systemd/system/mastodon-backup-notify@.service` を作成:

```ini
[Unit]
Description=Mastodon Backup Notification
After=mastodon-backup.service

[Service]
Type=oneshot
ExecStart=/usr/bin/mail -s "Mastodon Backup %i" admin@example.com < /dev/null
```

次に `mastodon-backup.service` を変更:

```ini
[Service]
OnSuccess=mastodon-backup-notify@success.service
OnFailure=mastodon-backup-notify@failure.service
```

