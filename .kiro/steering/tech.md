# Technology Stack

## Architecture

Single-script automation focused on reliability and security. Follows bash best practices with strict error handling (`set -euo pipefail`), comprehensive validation, and defensive programming patterns.

## Core Technologies

- **Language**: Bash 4.3+
- **Database Backup**: PostgreSQL (`pg_dump`), Redis (`redis-cli --rdb`)
- **Cloud Storage**: Backblaze B2 via rclone
- **Scheduling**: systemd timers (production deployment)

## Key Libraries

- **rclone**: Cloud storage abstraction layer (supports multiple providers, currently configured for B2)
- **PostgreSQL Client**: Direct database access via peer authentication
- **Redis CLI**: RDB snapshot generation

## Development Standards

### Error Handling

- Strict mode enabled: `set -euo pipefail`
- Comprehensive error traps on line failures
- Explicit exit status checks for all critical operations
- Dry-run mode for safe testing

### Code Quality

- All variables quoted: `"${var}"`
- Readonly for immutable values
- Local scope in functions
- ShellCheck compliant (`# shellcheck source=backup.conf`)

### Security

- Configuration separated from code (`backup.conf` excluded from git)
- Restrictive file permissions (600 for configs, 700 for scripts)
- No hardcoded credentials
- Sudo usage minimized to specific operations

## Development Environment

### Required Tools

- Bash 4.3+ (standard on modern Linux)
- PostgreSQL 12+ with peer authentication
- Redis 5+
- rclone (latest version recommended)
- systemd (for automated scheduling)

### Common Commands

```bash
# Test: Dry-run without actual backup
./backup.sh --dry-run

# Manual: One-time backup with timestamped suffix
./backup.sh --manual

# Production: Automatic daily backup (via systemd timer)
sudo systemctl start mastodon-backup.service
```

## Key Technical Decisions

**Bash over Python/Ruby**: Minimizes dependencies on production Mastodon servers where bash is always available

**rclone abstraction**: Provides cloud storage portability (easy migration from B2 to S3/GCS if needed)

**systemd over cron**: Better logging, dependency management, and failure handling for production deployments

**Custom format PostgreSQL dumps**: Enables selective restoration and better compression than SQL dumps

**Separate daily/monthly buckets**: Organizational clarity and independent retention policies for different backup tiers

---
_Document standards and patterns, not every dependency_

