#!/bin/bash

# Clean Logs Script for Kong Gateway API
# Keeps the latest 14 log files and removes older ones (5 files deletion batch)
# Supports rotation for Kong, Konga, and PostgreSQL logs

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
KEEP_FILES=14        # Number of latest log files to keep
DELETE_BATCH=5       # Number of old files to delete in one batch
LOG_BASE_DIR="./logs"

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] [SERVICE]"
    echo ""
    echo "Clean log files for Kong Gateway services"
    echo ""
    echo "Services:"
    echo "  kong        Clean Kong API Gateway logs only"
    echo "  konga       Clean Konga GUI logs only"
    echo "  postgres    Clean PostgreSQL logs only"
    echo "  pgbouncer   Clean PgBouncer logs only"
    echo "  nginx       Clean NGINX logs only"
    echo "  all         Clean all service logs (default)"
    echo ""
    echo "Options:"
    echo "  --dry-run   Show what would be deleted without actually deleting"
    echo "  --keep N    Keep N latest files (default: $KEEP_FILES)"
    echo "  --batch N   Delete N files per batch (default: $DELETE_BATCH)"
    echo "  --force     Delete without confirmation"
    echo "  --list      List all log files and their sizes"
    echo "  --stats     Show log directory statistics"
    echo "  --help      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Clean all logs (interactive)"
    echo "  $0 --dry-run          # Show what would be deleted"
    echo "  $0 --force kong       # Clean Kong logs without confirmation"
    echo "  $0 --keep 20 --batch 3 # Keep 20 files, delete 3 at a time"
    echo ""
}

# Function to check if logs directory exists
check_logs_directory() {
    if [ ! -d "$LOG_BASE_DIR" ]; then
        print_error "Logs directory not found: $LOG_BASE_DIR"
        print_info "Run './install.sh' first to create the directory structure"
        exit 1
    fi
}

# Function to get log files for a service
get_log_files() {
    local service="$1"
    local service_dir="$LOG_BASE_DIR/$service"
    
    if [ ! -d "$service_dir" ]; then
        print_warning "Service directory not found: $service_dir"
        return 1
    fi
    
    # Find all log files (*.log, *.log.*, *.out, *.err) and sort by modification time (newest first)
    find "$service_dir" -type f \( -name "*.log" -o -name "*.log.*" -o -name "*.out" -o -name "*.err" \) -printf "%T@ %p\n" 2>/dev/null | sort -nr | cut -d' ' -f2-
}

# Function to clean logs for a specific service
clean_service_logs() {
    local service="$1"
    local dry_run="$2"
    local force="$3"
    local keep_files="$4"
    local delete_batch="$5"
    
    print_info "Processing $service logs..."
    
    # Get all log files for this service
    local log_files
    if ! log_files=$(get_log_files "$service"); then
        return 1
    fi
    
    if [ -z "$log_files" ]; then
        print_info "No log files found for $service"
        return 0
    fi
    
    # Convert to array
    local files_array=()
    while IFS= read -r line; do
        [ -n "$line" ] && files_array+=("$line")
    done <<< "$log_files"
    
    local total_files=${#files_array[@]}
    print_info "Found $total_files log files for $service"
    
    if [ $total_files -le $keep_files ]; then
        print_success "Only $total_files files found, keeping all (threshold: $keep_files)"
        return 0
    fi
    
    # Calculate files to delete
    local files_to_delete=$((total_files - keep_files))
    local actual_delete=$((files_to_delete < delete_batch ? files_to_delete : delete_batch))
    
    print_warning "Will delete $actual_delete old files (keeping latest $keep_files)"
    
    # Get files to delete (oldest ones)
    local delete_files=("${files_array[@]: -$actual_delete}")
    
    # Show files that will be deleted
    echo "Files to be deleted:"
    for file in "${delete_files[@]}"; do
        local size=$(du -h "$file" 2>/dev/null | cut -f1)
        local date=$(stat -c "%y" "$file" 2>/dev/null | cut -d' ' -f1)
        echo "  - $(basename "$file") (${size}, $date)"
    done
    
    if [ "$dry_run" = "true" ]; then
        print_info "DRY RUN: Would delete $actual_delete files"
        return 0
    fi
    
    # Confirmation prompt
    if [ "$force" != "true" ]; then
        echo ""
        read -p "Delete these $actual_delete files? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Deletion cancelled for $service"
            return 0
        fi
    fi
    
    # Delete files
    local deleted_count=0
    local total_size=0
    
    for file in "${delete_files[@]}"; do
        if [ -f "$file" ]; then
            local file_size=$(stat -c%s "$file" 2>/dev/null || echo 0)
            if rm "$file" 2>/dev/null; then
                deleted_count=$((deleted_count + 1))
                total_size=$((total_size + file_size))
                print_info "Deleted: $(basename "$file")"
            else
                print_error "Failed to delete: $file"
            fi
        fi
    done
    
    if [ $deleted_count -gt 0 ]; then
        local size_mb=$((total_size / 1024 / 1024))
        print_success "Deleted $deleted_count files for $service (freed ${size_mb}MB)"
    fi
}

# Function to list all log files
list_log_files() {
    print_info "Listing all log files..."
    
    for service in kong konga postgres pgbouncer nginx; do
        local service_dir="$LOG_BASE_DIR/$service"
        if [ -d "$service_dir" ]; then
            echo ""
            echo "=== $service logs ==="
            local log_files
            if log_files=$(get_log_files "$service") && [ -n "$log_files" ]; then
                echo "File Name                    Size    Date       Age"
                echo "---------------------------- ------- ---------- -------"
                while IFS= read -r file; do
                    if [ -f "$file" ]; then
                        local size=$(du -h "$file" 2>/dev/null | cut -f1)
                        local date=$(stat -c "%y" "$file" 2>/dev/null | cut -d' ' -f1)
                        local age=$((($(date +%s) - $(stat -c %Y "$file" 2>/dev/null || echo 0)) / 86400))
                        printf "%-28s %-7s %-10s %d days\n" "$(basename "$file")" "$size" "$date" "$age"
                    fi
                done <<< "$log_files"
            else
                echo "No log files found"
            fi
        fi
    done
}

# Function to show log directory statistics
show_stats() {
    print_info "Log directory statistics..."
    
    if [ ! -d "$LOG_BASE_DIR" ]; then
        print_error "Logs directory not found"
        return 1
    fi
    
    echo ""
    echo "=== Overall Statistics ==="
    local total_size=$(du -sh "$LOG_BASE_DIR" 2>/dev/null | cut -f1)
    local total_files=$(find "$LOG_BASE_DIR" -type f 2>/dev/null | wc -l)
    echo "Total size: $total_size"
    echo "Total files: $total_files"
    
    echo ""
    echo "=== Per Service Statistics ==="
    printf "%-10s %-8s %-8s %-12s\n" "Service" "Files" "Size" "Oldest"
    printf "%-10s %-8s %-8s %-12s\n" "-------" "-----" "----" "------"
    
    for service in kong konga postgres pgbouncer nginx; do
        local service_dir="$LOG_BASE_DIR/$service"
        if [ -d "$service_dir" ]; then
            local files_count=$(find "$service_dir" -type f 2>/dev/null | wc -l)
            local size=$(du -sh "$service_dir" 2>/dev/null | cut -f1)
            local oldest_file=$(find "$service_dir" -type f -printf "%T@ %p\n" 2>/dev/null | sort -n | head -1 | cut -d' ' -f2-)
            local oldest_days=""
            if [ -n "$oldest_file" ] && [ -f "$oldest_file" ]; then
                local oldest_timestamp=$(stat -c %Y "$oldest_file" 2>/dev/null || echo 0)
                oldest_days=$((($(date +%s) - oldest_timestamp) / 86400))
                oldest_days="${oldest_days} days"
            fi
            printf "%-10s %-8s %-8s %-12s\n" "$service" "$files_count" "$size" "$oldest_days"
        else
            printf "%-10s %-8s %-8s %-12s\n" "$service" "0" "0B" "N/A"
        fi
    done
}

# Main function
main() {
    local service="all"
    local dry_run="false"
    local force="false"
    local keep_files=$KEEP_FILES
    local delete_batch=$DELETE_BATCH
    local list_files="false"
    local show_statistics="false"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run="true"
                shift
                ;;
            --force)
                force="true"
                shift
                ;;
            --keep)
                keep_files="$2"
                if ! [[ "$keep_files" =~ ^[0-9]+$ ]] || [ "$keep_files" -lt 1 ]; then
                    print_error "Invalid --keep value. Must be a positive number."
                    exit 1
                fi
                shift 2
                ;;
            --batch)
                delete_batch="$2"
                if ! [[ "$delete_batch" =~ ^[0-9]+$ ]] || [ "$delete_batch" -lt 1 ]; then
                    print_error "Invalid --batch value. Must be a positive number."
                    exit 1
                fi
                shift 2
                ;;
            --list)
                list_files="true"
                shift
                ;;
            --stats)
                show_statistics="true"
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            kong|konga|postgres|pgbouncer|nginx|all)
                service="$1"
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    echo "=========================================="
    echo "Kong Gateway Log Cleanup Script"
    echo "=========================================="
    echo ""
    
    check_logs_directory
    
    # Handle special modes
    if [ "$list_files" = "true" ]; then
        list_log_files
        exit 0
    fi
    
    if [ "$show_statistics" = "true" ]; then
        show_stats
        exit 0
    fi
    
    # Main cleanup logic
    print_info "Configuration: Keep $keep_files files, delete $delete_batch files per batch"
    if [ "$dry_run" = "true" ]; then
        print_warning "DRY RUN MODE - No files will actually be deleted"
    fi
    echo ""
    
    if [ "$service" = "all" ]; then
        for svc in kong konga postgres pgbouncer nginx; do
            clean_service_logs "$svc" "$dry_run" "$force" "$keep_files" "$delete_batch"
            echo ""
        done
    else
        clean_service_logs "$service" "$dry_run" "$force" "$keep_files" "$delete_batch"
    fi
    
    if [ "$dry_run" != "true" ]; then
        echo ""
        print_success "Log cleanup completed!"
        print_info "Run '$0 --stats' to see updated statistics"
    fi
}

# Run main function with all arguments
main "$@"
