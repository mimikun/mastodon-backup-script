# Project Structure

## Organization Philosophy

Single-purpose script project with clear separation between code, configuration, and deployment infrastructure. Configuration is externalized to support environment-specific deployment without code changes.

## Directory Patterns

### Root Scripts

**Location**: `/`
**Purpose**: Core backup script and configuration
**Example**:
- `backup.sh`: Main executable script
- `backup.conf`: Active configuration (gitignored, instance-specific)
- `backup.conf.example`: Template with documentation

### systemd Service Files

**Location**: `/services/`
**Purpose**: Production deployment infrastructure
**Example**:
- `mastodon-backup.service`: Service unit for backup execution
- `mastodon-backup.timer`: Timer unit for daily scheduling (2:00 AM)

### Documentation

**Location**: `/`
**Purpose**: User-facing documentation
**Example**:
- `README.md`: English documentation
- `README-ja.md`: Japanese documentation

## Naming Conventions

- **Scripts**: Snake_case with `.sh` extension (`backup.sh`)
- **Config Files**: Descriptive names with `.conf` extension
- **Functions**: Snake_case with descriptive verbs (`backup_postgresql`, `cleanup_remote_backup`)
- **Variables**: UPPER_CASE for globals/readonly, lowercase for local function variables

## File Organization Principles

### Separation of Concerns

- **Logic**: `backup.sh` (executable script)
- **Configuration**: `backup.conf` (user-editable settings)
- **Templates**: `backup.conf.example` (documented defaults)
- **Infrastructure**: `services/` (systemd units)

### Configuration Pattern

```bash
# Configuration loaded at runtime
source "${CONFIG_FILE}" || exit 1

# Externalized variables (from backup.conf):
MASTODON_HOME="/home/mastodon/live"
BACKUP_DIR="/home/mastodon/backups"
RCLONE_REMOTE_DAILY="remote_b2_account_credentials"
B2_BUCKET_DAILY="daily-db-backup"
```

### Script Structure Pattern

```bash
#!/usr/bin/env bash
set -euo pipefail

# 1. Initialization (script directory, config path)
# 2. Configuration loading
# 3. CLI argument parsing
# 4. Runtime variables (dates, filenames)
# 5. Utility functions (validation, directory setup)
# 6. Core operations (backup, upload, cleanup)
# 7. Main execution flow
# 8. Entry point (main function call)
```

## Backup File Naming Convention

Pattern: `{database}_backup_{YYYY}_{MM}_{DD}[_manual]`

**Examples**:
- Daily automatic: `pg_backup_2026_01_15`
- Manual backup: `redis_backup_2026_01_01_manual`

**Rationale**: Sortable, readable, distinguishes automatic vs manual backups

---
_Document patterns, not file trees. New files following patterns shouldn't require updates_

