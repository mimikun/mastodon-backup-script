#!/usr/bin/env bash
#
# Mastodon Backup Script
#
# Description: Automated backup script for Mastodon PostgreSQL and Redis databases
#              Uploads backups to Backblaze B2 using rclone
# Usage: ./backup.sh [--manual] [--dry-run]
# Requirements: postgresql, redis-cli, rclone
#
# Author: mimikun
# License: MIT
#

set -euo pipefail

# ============================================================================
# Script initialization
# ============================================================================

# Script directory detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME

# Configuration file path
readonly CONFIG_FILE="${SCRIPT_DIR}/backup.conf"

# Error trap
trap 'echo "Error: Script failed on line $LINENO" >&2; exit 1' ERR

# Cleanup on exit
cleanup_on_exit() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        echo "Script exited with error code: ${exit_code}" >&2
    fi
}
trap cleanup_on_exit EXIT

# ============================================================================
# Load configuration
# ============================================================================

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "Error: Configuration file not found: ${CONFIG_FILE}" >&2
    echo "Please create backup.conf from backup.conf.example:" >&2
    echo "  cp backup.conf.example backup.conf" >&2
    exit 1
fi

# Source configuration with error handling
# shellcheck source=backup.conf
source "${CONFIG_FILE}" || {
    echo "Error: Failed to load configuration from ${CONFIG_FILE}" >&2
    exit 1
}

# ============================================================================
# Parse command line arguments
# ============================================================================

# Default mode
AUTO_MODE=true
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "${1}" in
        --manual)
            AUTO_MODE=false
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            echo "Usage: ${SCRIPT_NAME} [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --manual    Run in manual mode (appends '_manual' to backup filenames)"
            echo "  --dry-run   Test mode - show what would be done without actual backup/upload"
            echo "  -h, --help  Show this help message"
            echo ""
            echo "Examples:"
            echo "  ${SCRIPT_NAME}              # Automatic daily backup"
            echo "  ${SCRIPT_NAME} --manual     # Manual backup"
            echo "  ${SCRIPT_NAME} --dry-run    # Test without actual backup"
            exit 0
            ;;
        *)
            echo "Error: Unknown option: ${1}" >&2
            echo "Use --help for usage information" >&2
            exit 1
            ;;
    esac
done

# ============================================================================
# Runtime variables
# ============================================================================

# Date variables
DATE="$(date '+%Y_%m_%d')"
readonly DATE
DAY_OF_MONTH="$(date '+%d')"  # FIX: This was 'today' and undefined!
readonly DAY_OF_MONTH

# Calculate retention dates
REMOTE_OLD_DATE="$(date -d "${REMOTE_RETENTION_DAYS} days ago" '+%Y_%m_%d')"
readonly REMOTE_OLD_DATE
LOCAL_OLD_DATE="$(date -d "${LOCAL_RETENTION_DAYS} days ago" '+%Y_%m_%d')"
readonly LOCAL_OLD_DATE

# Base backup filenames
PG_FILENAME="pg_backup_${DATE}"
REDIS_FILENAME="redis_backup_${DATE}"

# Append '_manual' suffix in manual mode
if [[ "${AUTO_MODE}" == "false" ]]; then
    PG_FILENAME="${PG_FILENAME}_manual"
    REDIS_FILENAME="${REDIS_FILENAME}_manual"
fi

# Full backup file paths
readonly PG_BACKUP_FILE="${BACKUP_DIR}/${PG_FILENAME}"
readonly REDIS_BACKUP_FILE="${BACKUP_DIR}/${REDIS_FILENAME}"

# Old backup filenames (for cleanup)
readonly OLD_PG_FILENAME="pg_backup_${REMOTE_OLD_DATE}"
readonly OLD_REDIS_FILENAME="redis_backup_${REMOTE_OLD_DATE}"
readonly LOCAL_OLD_PG_FILENAME="pg_backup_${LOCAL_OLD_DATE}"
readonly LOCAL_OLD_REDIS_FILENAME="redis_backup_${LOCAL_OLD_DATE}"

# Determine which B2 bucket to use (monthly on 1st, daily otherwise)
if [[ "${DAY_OF_MONTH}" == "01" ]]; then
    RCLONE_REMOTE="${RCLONE_REMOTE_MONTHLY}"
    B2_BUCKET="${B2_BUCKET_MONTHLY}"
    BACKUP_TYPE="monthly"
    echo "Monthly backup mode activated (1st of the month)" >&2
else
    RCLONE_REMOTE="${RCLONE_REMOTE_DAILY}"
    B2_BUCKET="${B2_BUCKET_DAILY}"
    BACKUP_TYPE="daily"
    echo "Daily backup mode activated" >&2
fi

# Dry-run notification
if [[ "${DRY_RUN}" == "true" ]]; then
    echo "=== DRY-RUN MODE: No actual backup or upload will be performed ===" >&2
fi

# ============================================================================
# Utility functions
# ============================================================================

# Ensure backup directory exists
# Returns: 0 on success
ensure_backup_directory() {
    if [[ ! -d "${BACKUP_DIR}" ]]; then
        echo "Backup directory does not exist, creating: ${BACKUP_DIR}" >&2
        mkdir -p "${BACKUP_DIR}"
    fi
}

# Validate rclone configuration
# Returns: 0 if valid, 1 if invalid
validate_rclone_config() {
    if ! command -v rclone &> /dev/null; then
        echo "Error: rclone is not installed" >&2
        echo "Please install rclone: https://rclone.org/install/" >&2
        return 1
    fi

    # Check if remote exists
    if ! rclone listremotes | grep -q "^${RCLONE_REMOTE}:$"; then
        echo "Error: rclone remote '${RCLONE_REMOTE}' not found" >&2
        echo "Configured remotes:" >&2
        rclone listremotes >&2
        echo "" >&2
        echo "Please configure rclone. See backup.conf.example for instructions" >&2
        return 1
    fi

    # Check if bucket exists (only if not dry-run)
    if [[ "${DRY_RUN}" == "false" ]]; then
        if ! rclone lsd "${RCLONE_REMOTE}:" 2>/dev/null | grep -q "${B2_BUCKET}"; then
            echo "Warning: Bucket '${B2_BUCKET}' not found in remote '${RCLONE_REMOTE}'" >&2
            echo "Available buckets:" >&2
            rclone lsd "${RCLONE_REMOTE}:" 2>&1 | grep -v "^$" || echo "(none)" >&2
            echo "" >&2
            echo "Please create the bucket in Backblaze B2 or update backup.conf" >&2
            return 1
        fi
    fi

    return 0
}

# ============================================================================
# Backup operations
# ============================================================================

# Backup PostgreSQL database
# Arguments:
#   $1 - Backup file path
# Returns:
#   0 on success, 1 on error
backup_postgresql() {
    local backup_file="${1}"

    echo "Starting PostgreSQL backup..." >&2
    echo "Database: ${PG_DBNAME}" >&2
    echo "Output file: ${backup_file}" >&2

    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "[DRY-RUN] Would execute: sudo -u postgres pg_dump -v -F c \"dbname=${PG_DBNAME}\" > \"${backup_file}\"" >&2
        # Create empty file for dry-run testing
        touch "${backup_file}"
        return 0
    fi

    # Execute PostgreSQL backup directly (no eval!)
    # Use tee with sudo to properly handle redirection
    if sudo -u postgres pg_dump -v -F c "dbname=${PG_DBNAME}" | tee "${backup_file}" > /dev/null; then
        echo "PostgreSQL backup completed successfully" >&2
        return 0
    else
        local status=$?
        echo "Error: PostgreSQL backup failed with status ${status}" >&2
        return 1
    fi
}

# Backup Redis database
# Arguments:
#   $1 - Backup file path
# Returns:
#   0 on success, 1 on error
backup_redis() {
    local backup_file="${1}"

    echo "Starting Redis backup..." >&2
    echo "Output file: ${backup_file}" >&2

    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "[DRY-RUN] Would execute: redis-cli --rdb \"${backup_file}\"" >&2
        # Create empty file for dry-run testing
        touch "${backup_file}"
        return 0
    fi

    # Execute Redis backup directly (no eval!)
    if redis-cli --rdb "${backup_file}"; then
        echo "Redis backup completed successfully" >&2
        return 0
    else
        local status=$?
        echo "Error: Redis backup failed with status ${status}" >&2
        return 1
    fi
}

# Upload backup file to Backblaze B2
# Arguments:
#   $1 - Backup file path
#   $2 - Database type (for logging)
# Returns:
#   0 on success, 1 on error
upload_to_b2() {
    local backup_file="${1}"
    local db_type="${2}"
    local remote_path="${RCLONE_REMOTE}:/${B2_BUCKET}/"

    echo "Uploading ${db_type} backup to Backblaze B2..." >&2
    echo "Remote: ${remote_path}" >&2
    echo "File: ${backup_file}" >&2

    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "[DRY-RUN] Would execute: rclone copy --no-check-dest \"${backup_file}\" \"${remote_path}\" -vvvv" >&2
        return 0
    fi

    if rclone copy --no-check-dest "${backup_file}" "${remote_path}" -vvvv; then
        echo "${db_type} backup uploaded successfully" >&2
        return 0
    else
        local status=$?
        echo "Error: ${db_type} upload failed with status ${status}" >&2
        return 1
    fi
}

# ============================================================================
# Cleanup operations
# ============================================================================

# Delete old remote backup file
# Arguments:
#   $1 - Filename to delete
#   $2 - Database type (for logging)
# Returns:
#   0 on success or file not found, 1 on error
cleanup_remote_backup() {
    local filename="${1}"
    local db_type="${2}"
    local remote_file="${RCLONE_REMOTE}:/${B2_BUCKET}/${filename}"

    if [[ -z "${filename}" ]]; then
        echo "Warning: Empty filename provided for remote cleanup" >&2
        return 0
    fi

    echo "Deleting old ${db_type} remote backup: ${filename}" >&2

    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "[DRY-RUN] Would execute: rclone deletefile \"${remote_file}\" -vvvv" >&2
        return 0
    fi

    # rclone deletefile returns error if file doesn't exist, so we ignore errors
    if rclone deletefile "${remote_file}" -vvvv 2>&1 | grep -q "not found"; then
        echo "Remote file not found (already deleted or never existed): ${filename}" >&2
        return 0
    fi

    echo "Remote ${db_type} backup deleted successfully" >&2
    return 0
}

# Delete old local backup file
# Arguments:
#   $1 - Filename to delete
#   $2 - Database type (for logging)
# Returns:
#   0 on success or file not found
cleanup_local_backup() {
    local filename="${1}"
    local db_type="${2}"
    local local_file="${BACKUP_DIR}/${filename}"

    if [[ -z "${filename}" ]]; then
        echo "Warning: Empty filename provided for local cleanup" >&2
        return 0
    fi

    if [[ ! -f "${local_file}" ]]; then
        echo "Local file not found (already deleted or never existed): ${filename}" >&2
        return 0
    fi

    echo "Deleting old ${db_type} local backup: ${local_file}" >&2

    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "[DRY-RUN] Would execute: rm -f \"${local_file}\"" >&2
        return 0
    fi

    if rm -f "${local_file}"; then
        echo "Local ${db_type} backup deleted successfully" >&2
        return 0
    else
        echo "Warning: Failed to delete local ${db_type} backup: ${local_file}" >&2
        return 0  # Non-fatal error
    fi
}

# ============================================================================
# Main execution
# ============================================================================

main() {
    echo "========================================" >&2
    echo "Mastodon Backup Script" >&2
    echo "========================================" >&2
    echo "Date: ${DATE}" >&2
    echo "Backup type: ${BACKUP_TYPE}" >&2
    echo "Mode: $(${AUTO_MODE} && echo "automatic" || echo "manual")" >&2
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "Dry-run: enabled" >&2
    fi
    echo "========================================" >&2
    echo "" >&2

    # Ensure backup directory exists
    ensure_backup_directory

    # Validate rclone configuration
    if ! validate_rclone_config; then
        echo "Error: rclone validation failed" >&2
        exit 1
    fi

    # PostgreSQL backup
    echo "" >&2
    echo "--- PostgreSQL Backup ---" >&2
    if backup_postgresql "${PG_BACKUP_FILE}"; then
        pg_backup_status=0
        if upload_to_b2 "${PG_BACKUP_FILE}" "PostgreSQL"; then
            pg_upload_status=0
        else
            pg_upload_status=1
        fi
    else
        pg_backup_status=1
        pg_upload_status=1  # Skip upload if backup failed
    fi

    # Redis backup
    echo "" >&2
    echo "--- Redis Backup ---" >&2
    if backup_redis "${REDIS_BACKUP_FILE}"; then
        redis_backup_status=0
        if upload_to_b2 "${REDIS_BACKUP_FILE}" "Redis"; then
            redis_upload_status=0
        else
            redis_upload_status=1
        fi
    else
        redis_backup_status=1
        redis_upload_status=1  # Skip upload if backup failed
    fi

    # Cleanup old remote backups (only after successful new backups)
    echo "" >&2
    echo "--- Cleanup Remote Backups (${REMOTE_RETENTION_DAYS} days) ---" >&2
    cleanup_remote_backup "${OLD_PG_FILENAME}" "PostgreSQL"
    cleanup_remote_backup "${OLD_REDIS_FILENAME}" "Redis"

    # Cleanup old local backups
    echo "" >&2
    echo "--- Cleanup Local Backups (${LOCAL_RETENTION_DAYS} days) ---" >&2
    cleanup_local_backup "${LOCAL_OLD_PG_FILENAME}" "PostgreSQL"
    cleanup_local_backup "${LOCAL_OLD_REDIS_FILENAME}" "Redis"

    # Final status report
    echo "" >&2
    echo "========================================" >&2
    echo "Backup Summary" >&2
    echo "========================================" >&2
    echo "PostgreSQL backup: $([ ${pg_backup_status} -eq 0 ] && echo "SUCCESS" || echo "FAILED")" >&2
    echo "PostgreSQL upload: $([ ${pg_upload_status} -eq 0 ] && echo "SUCCESS" || echo "FAILED")" >&2
    echo "Redis backup: $([ ${redis_backup_status} -eq 0 ] && echo "SUCCESS" || echo "FAILED")" >&2
    echo "Redis upload: $([ ${redis_upload_status} -eq 0 ] && echo "SUCCESS" || echo "FAILED")" >&2
    echo "========================================" >&2

    # Determine overall exit status
    if [[ ${pg_backup_status} -ne 0 ]] || [[ ${pg_upload_status} -ne 0 ]] || \
       [[ ${redis_backup_status} -ne 0 ]] || [[ ${redis_upload_status} -ne 0 ]]; then
        echo "Error: Some backup operations failed" >&2
        exit 1
    else
        echo "All backup operations completed successfully" >&2
        exit 0
    fi
}

# Run main function
main

