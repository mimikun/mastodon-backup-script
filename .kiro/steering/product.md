# Product Overview

Automated backup solution for Mastodon instances that handles PostgreSQL and Redis database backups with cloud storage integration.

## Core Capabilities

- **Automated Backup Orchestration**: Daily and monthly backup scheduling for Mastodon database infrastructure
- **Cloud Storage Integration**: Direct upload to Backblaze B2 cloud storage via rclone
- **Lifecycle Management**: Configurable retention policies for both local and remote backups
- **Operational Flexibility**: Manual backup triggers, dry-run testing, and comprehensive error handling

## Target Use Cases

- **Production Mastodon Instances**: Automated daily database protection with minimal manual intervention
- **Disaster Recovery**: Monthly archival backups for long-term recovery scenarios
- **Migration Support**: Manual backup mode for pre-migration database snapshots
- **Testing & Validation**: Dry-run mode for backup process verification without actual data transfer

## Value Proposition

Provides a production-ready, security-focused backup solution that automates the critical task of protecting Mastodon database infrastructure. Unlike manual backup approaches, this script ensures consistent daily backups with automatic cloud replication and intelligent cleanup, reducing operational burden while maintaining data safety.

---
_Focus on patterns and purpose, not exhaustive feature lists_

