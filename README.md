# Mastodon Backup Script

Automated backup script for Mastodon PostgreSQL and Redis databases with Backblaze B2 cloud storage integration via rclone.

## Features

- ✅ **Automated daily backups** of PostgreSQL and Redis databases
- ✅ **Monthly archival backups** (automatically triggered on the 1st of each month)
- ✅ **Cloud storage** with Backblaze B2 via rclone
- ✅ **Automatic cleanup** of old backups (configurable retention periods)
- ✅ **Manual backup mode** with timestamped filenames
- ✅ **Dry-run mode** for testing without actual backup/upload
- ✅ **Security-focused** with separated configuration and no hardcoded secrets
- ✅ **Comprehensive error handling** with detailed logging

## Requirements

- **Operating System**: Linux (tested on Ubuntu/Debian)
- **Mastodon**: Any version
- **PostgreSQL**: 12+ (with peer authentication for postgres user)
- **Redis**: 5+
- **rclone**: Latest version
- **Bash**: 4.3+

## Quick Start

### 1. Install rclone

```bash
# Official installation script
curl https://rclone.org/install.sh | sudo bash

# Or use package manager
sudo apt install rclone  # Debian/Ubuntu
```

### 2. Configure Backblaze B2

#### Get B2 Credentials

1. Log in to [Backblaze](https://www.backblaze.com/)
2. Navigate to **B2 Cloud Storage** → **App Keys**
3. Click **Add a New Application Key**
   - Key Name: `mastodon-backup` (or your preferred name)
   - Allow access to Bucket(s): Select your backup buckets or "All"
   - Type of Access: Read and Write
4. **IMPORTANT**: Save the **Application Key** immediately (shown only once!)
5. Note down:
   - Account ID (or Application Key ID)
   - Application Key (the secret)

#### Create B2 Buckets

1. Go to [B2 Buckets](https://www.backblaze.com/b2/buckets.html)
2. Create two buckets:
   - **daily-db-backup** (for daily backups)
   - **monthly-db-backup** (for monthly archival backups)
3. Bucket settings:
   - Files in Bucket: **Private**
   - Default Encryption: **Enable** (recommended)
   - Object Lock: Optional (for compliance requirements)

#### Configure rclone

```bash
rclone config
```

Follow the interactive prompts:

```
n) New remote
name> remote_b2_account_credentials
Storage> b2
account> [Paste your Account ID or Application Key ID]
key> [Paste your Application Key]
# Accept defaults for remaining options
```

#### Verify rclone Configuration

```bash
# List configured remotes
rclone listremotes
# Expected output: remote_b2_account_credentials:

# List buckets
rclone lsd remote_b2_account_credentials:
# Expected output should show: daily-db-backup, monthly-db-backup

# Test upload
echo "test" > /tmp/test.txt
rclone copy /tmp/test.txt remote_b2_account_credentials:/daily-db-backup/
rclone ls remote_b2_account_credentials:/daily-db-backup/
# Should show: test.txt

# Cleanup test
rclone delete remote_b2_account_credentials:/daily-db-backup/test.txt
rm /tmp/test.txt
```

### 3. Clone and Configure

```bash
# Clone repository
cd /home/mastodon/
git clone https://github.com/mimikun/mastodon-backup-script.git
cd mastodon-backup-script

# Copy configuration template
cp backup.conf.example backup.conf

# Edit configuration
nano backup.conf
# Update paths, database names, and bucket names as needed

# Set permissions
chmod 600 backup.conf
chmod 700 backup.sh
```

### 4. Test Backup

```bash
# Dry-run test (no actual backup/upload)
./backup.sh --dry-run

# Manual backup test (creates backup with '_manual' suffix)
./backup.sh --manual
```

### 5. Schedule Automatic Backups (systemd timer)

```bash
# Install systemd service and timer files
sudo cp services/mastodon-backup.service /etc/systemd/system/
sudo cp services/mastodon-backup.timer /etc/systemd/system/

# Reload systemd to recognize new files
sudo systemctl daemon-reload

# Enable and start the timer (will run daily at 2:00 AM)
sudo systemctl enable mastodon-backup.timer
sudo systemctl start mastodon-backup.timer

# Check timer status
sudo systemctl status mastodon-backup.timer

# List all active timers
systemctl list-timers --all | grep mastodon-backup
```

## Usage

### Command Line Options

```bash
./backup.sh [OPTIONS]

Options:
  --manual    Run in manual mode (appends '_manual' to backup filenames)
  --dry-run   Test mode - show what would be done without actual backup/upload
  -h, --help  Show help message
```

### Examples

```bash
# Automatic daily backup (default)
./backup.sh

# Manual backup with timestamped filename
./backup.sh --manual

# Test run without actual backup/upload
./backup.sh --dry-run

# Combine options: manual dry-run
./backup.sh --manual --dry-run
```

## Configuration

### Configuration Files

- **`backup.conf`**: Your active configuration (excluded from git)
- **`backup.conf.example`**: Template with detailed documentation

### systemd Files

- **`services/mastodon-backup.service`**: systemd service unit file
- **`services/mastodon-backup.timer`**: systemd timer unit file (schedules daily backups at 2:00 AM)

### Key Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `MASTODON_HOME` | Mastodon installation directory | `/home/mastodon/live` |
| `BACKUP_DIR` | Local backup storage directory | `/home/mastodon/backups` |
| `PG_DBNAME` | PostgreSQL database name | `postgres` |
| `RCLONE_REMOTE_DAILY` | rclone remote for daily backups | `remote_b2_account_credentials` |
| `RCLONE_REMOTE_MONTHLY` | rclone remote for monthly backups | `remote_b2_account_credentials` |
| `B2_BUCKET_DAILY` | B2 bucket for daily backups | `daily-db-backup` |
| `B2_BUCKET_MONTHLY` | B2 bucket for monthly backups | `monthly-db-backup` |
| `REMOTE_RETENTION_DAYS` | Days to keep remote backups | `3` |
| `LOCAL_RETENTION_DAYS` | Days to keep local backups | `7` |

## How It Works

### Backup Process

1. **Initialization**
   - Loads configuration from `backup.conf`
   - Validates rclone configuration
   - Creates backup directory if needed

2. **PostgreSQL Backup**
   - Dumps database using `pg_dump` (custom format)
   - Saves to local backup directory

3. **Redis Backup**
   - Creates RDB snapshot using `redis-cli --rdb`
   - Saves to local backup directory

4. **Upload to B2**
   - Uploads PostgreSQL and Redis backups to Backblaze B2
   - Uses appropriate bucket (daily vs monthly based on date)

5. **Cleanup**
   - Deletes remote backups older than `REMOTE_RETENTION_DAYS`
   - Deletes local backups older than `LOCAL_RETENTION_DAYS`

### Monthly vs Daily Backups

- **Daily backups**: Run automatically every day, stored in `daily-db-backup` bucket
- **Monthly backups**: Automatically triggered on the 1st of each month, stored in `monthly-db-backup` bucket
- Both use the same retention policy but separate buckets for organization

### File Naming Convention

```
PostgreSQL: pg_backup_YYYY_MM_DD[_manual]
Redis:      redis_backup_YYYY_MM_DD[_manual]
```

Example: `pg_backup_2026_01_15` or `redis_backup_2026_01_01_manual`

## Restoration

### Restore PostgreSQL Database

```bash
# Stop Mastodon services
sudo systemctl stop mastodon-*.service

# Download backup from B2
rclone copy remote_b2_account_credentials:/daily-db-backup/pg_backup_2026_01_15 /tmp/

# Drop existing database (BE CAREFUL!)
sudo -u postgres dropdb postgres

# Create new database
sudo -u postgres createdb postgres

# Restore from backup
sudo -u postgres pg_restore -d postgres /tmp/pg_backup_2026_01_15

# Start Mastodon services
sudo systemctl start mastodon-*.service
```

### Restore Redis Database

```bash
# Stop Redis
sudo systemctl stop redis

# Download backup from B2
rclone copy remote_b2_account_credentials:/daily-db-backup/redis_backup_2026_01_15 /var/lib/redis/dump.rdb

# Set correct permissions
sudo chown redis:redis /var/lib/redis/dump.rdb

# Start Redis
sudo systemctl start redis
```

## Troubleshooting

### rclone remote not found

**Error**: `Error: rclone remote 'remote_b2_account_credentials' not found`

**Solution**:
1. Check configured remotes: `rclone listremotes`
2. Reconfigure if needed: `rclone config`
3. Update `backup.conf` with correct remote name

### Bucket not found

**Error**: `Warning: Bucket 'daily-db-backup' not found`

**Solution**:
1. Check buckets: `rclone lsd remote_b2_account_credentials:`
2. Create missing buckets in Backblaze B2 web interface
3. Update `backup.conf` with correct bucket names

### Permission denied errors

**Error**: `Permission denied` when running backup

**Solution**:

```bash
# For PostgreSQL backup (requires sudo for postgres user)
sudo visudo
# Add: mastodon ALL=(postgres) NOPASSWD: /usr/bin/pg_dump

# For script execution
chmod 700 backup.sh
```

### Backup validation failed

**Issue**: Want to verify backup integrity

**Solution**:

```bash
# Test PostgreSQL backup
pg_restore --list /path/to/pg_backup_file

# Test Redis backup (check file size and format)
file /path/to/redis_backup_file
# Should show: "Redis RDB file"
```

### systemd timer not running

**Error**: Timer is enabled but backup doesn't run

**Solution**:

```bash
# Check timer status
sudo systemctl status mastodon-backup.timer

# Check when timer will run next
systemctl list-timers --all | grep mastodon-backup

# Manually trigger the service (for testing)
sudo systemctl start mastodon-backup.service

# View service logs
sudo journalctl -u mastodon-backup.service -n 50

# Restart timer if needed
sudo systemctl restart mastodon-backup.timer
```

### systemd service fails

**Error**: Service exits with error code

**Solution**:

```bash
# Check detailed service status
sudo systemctl status mastodon-backup.service -l

# View full logs
sudo journalctl -u mastodon-backup.service --no-pager

# Check file permissions
ls -la /home/mastodon/mastodon-backup-script/backup.sh
# Should be executable: -rwx------

# Verify User/Group in service file
sudo cat /etc/systemd/system/mastodon-backup.service | grep -E "User|Group"
# Should match your Mastodon user

# Test script manually as the service user
sudo -u mastodon /home/mastodon/mastodon-backup-script/backup.sh --dry-run
```

## Security Best Practices

### File Permissions

```bash
chmod 600 backup.conf                          # Only owner read/write
chmod 700 backup.sh                            # Only owner execute
chmod 600 ~/.config/rclone/rclone.conf         # Only owner read rclone config
```

### Backblaze B2 Security

- ✅ Use restrictive Application Keys with access ONLY to backup buckets
- ✅ Enable IP restrictions if server has static IP
- ✅ Rotate Application Keys periodically (every 90 days recommended)
- ✅ Enable Server-Side Encryption in bucket settings
- ✅ Enable Object Lock for compliance requirements (optional)

### Monitoring

- ✅ Check backup logs regularly
- ✅ Set up monitoring/alerts for backup failures (e.g., via cron mail)
- ✅ Periodically test restoration from backups (monthly recommended)
- ✅ Monitor B2 bucket size and costs

### Encryption Options

**Server-Side Encryption** (Recommended):
- Enable in B2 bucket settings
- Transparent encryption/decryption
- No performance impact

**rclone crypt** (Advanced):
- Client-side encryption before upload
- More control but requires additional configuration
- See: https://rclone.org/crypt/

## Advanced Usage

### Custom Retention Periods

Edit `backup.conf`:

```bash
# Keep remote backups for 7 days
REMOTE_RETENTION_DAYS=7

# Keep local backups for 14 days
LOCAL_RETENTION_DAYS=14
```

### Multiple Environments

Create environment-specific configs:

```bash
cp backup.conf backup.conf.production
cp backup.conf backup.conf.staging

# Use specific config
CONFIG_FILE=backup.conf.staging ./backup.sh
```

### Logging

**View systemd logs:**

```bash
# View recent backup logs
sudo journalctl -u mastodon-backup.service -n 50

# Follow logs in real-time
sudo journalctl -u mastodon-backup.service -f

# View logs for specific date
sudo journalctl -u mastodon-backup.service --since "2026-01-01" --until "2026-01-02"

# Export logs to file
sudo journalctl -u mastodon-backup.service > /var/log/mastodon-backup.log
```

**Manual execution with logging:**

```bash
./backup.sh 2>&1 | tee -a /var/log/mastodon-backup.log
```

### Notifications

**Email notifications** (via systemd):

Create `/etc/systemd/system/mastodon-backup-notify@.service`:

```ini
[Unit]
Description=Mastodon Backup Notification
After=mastodon-backup.service

[Service]
Type=oneshot
ExecStart=/usr/bin/mail -s "Mastodon Backup %i" admin@example.com < /dev/null
```

Then modify `mastodon-backup.service`:

```ini
[Service]
OnSuccess=mastodon-backup-notify@success.service
OnFailure=mastodon-backup-notify@failure.service
```

