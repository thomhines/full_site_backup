#!/bin/bash

# Ensure PATH is set correctly
export PATH=/usr/local/cpanel/3rdparty/lib/path-bin:/usr/local/bin:/usr/bin:/bin

cd /home2/hilosdes

# Source the configuration file
source "$(dirname "$0")/backup_config.sh"

# Allow Git to work across filesystem boundaries
export GIT_DISCOVERY_ACROSS_FILESYSTEM=1

# Set log file for Markdown output
LOG_MD="restore_log.md"

# Create timestamp for restore operation
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Add timestamp at the beginning of the process
{
	echo 
	echo
	echo "--------------------------------"
	echo
	echo "**Restore started:**"
	echo "$(date '+%Y-%m-%d %H:%M:%S')"
	echo
} >> "$LOG_MD"

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Function to log messages in Markdown
log_message() {
	local message="$1"
	local color="$2"
	
	# Print to screen
	if [ -n "$color" ]; then
		echo -e "${color}${message}${NC}"
	else
		echo -e "${message}"
	fi
	
	# Append to Markdown log file
	echo "- $message" >> "$LOG_MD"
}

# Function to log errors in Markdown
log_error() {
	local message="$1"
	
	# Log to screen in red
	echo -e "${RED}$message${NC}"
	
	# Append to Markdown log file
	echo "- *ERROR*: $message" >> "$LOG_MD"
}

# Function to find the most recent commit
get_latest_commit() {
	local backup_dir="$1"
	
	git -C "$backup_dir" rev-parse --short HEAD
}

# Function to find commit hash from partial hash
find_commit() {
	local backup_dir="$1"
	local partial_hash="$2"
	
	git -C "$backup_dir" log --pretty=format:"%h" | grep "^$partial_hash" | head -n 1
}

# Function to list available backups
list_backups() {
	local folder_name="$1"
	local backup_dir="$BACKUP_ROOT/$folder_name"
	
	if [ ! -d "$backup_dir/.git" ]; then
		log_error "No Git repository found for $folder_name"
		return 1
	fi
	
	if ! git -C "$backup_dir" rev-parse --git-dir > /dev/null 2>&1; then
		log_error "Git repository not properly initialized for $folder_name"
		return 1
	fi
	
	echo -e "${BLUE}Available backups for $folder_name:${NC}"
	git -C "$backup_dir" log --pretty=format:"%h - %s (%cr)" --date=relative
}

# Function to restore database
restore_database() {
	local folder_name="$1"
	local db_name="$2"
	local db_user="$3"
	local db_pass="$4"
	
	local backup_dir="$BACKUP_ROOT/$folder_name"
	local backup_file="$backup_dir/${db_name}_backup.sql"
	
	if [ ! -f "$backup_file" ]; then
		log_error "Database backup file not found: $backup_file"
		return 1
	fi
	
	log_message "Starting database restore for $folder_name" "$YELLOW"
	
	# Perform the database restore
	log_message "Running mysql restore..." "$YELLOW"
	if ! mysql -u "$db_user" -p"$db_pass" "$db_name" < "$backup_file"; then
		log_error "Database restore failed for $folder_name: mysql error"
		return 1
	fi
	
	log_message "Database restore completed for $folder_name" "$GREEN"
	return 0
}

# Function to restore files from backup
restore_files() {
	local folder_name="$1"
	local commit_hash="$2"
	local backup_dir="$BACKUP_ROOT/$folder_name"
	local restore_dir="$folder_name"
	
	log_message "Starting file restore for $folder_name" "$YELLOW"
	
	if [ ! -d "$backup_dir/.git" ]; then
		log_error "No Git repository found for $folder_name"
		return 1
	fi
	
	if ! git -C "$backup_dir" rev-parse --git-dir > /dev/null 2>&1; then
		log_error "Git repository not properly initialized for $folder_name"
		return 1
	fi
	
	# If no commit hash is provided, use the latest commit
	if [ -z "$commit_hash" ]; then
		commit_hash=$(get_latest_commit "$backup_dir")
		log_message "No commit hash provided, using latest commit: $commit_hash" "$BLUE"
	else
		# Try to find the full commit hash from the partial one
		full_hash=$(find_commit "$backup_dir" "$commit_hash")
		
		if [ -z "$full_hash" ]; then
			log_error "Could not find commit matching: $commit_hash"
			return 1
		fi
		
		commit_hash="$full_hash"
		log_message "Using commit: $commit_hash" "$BLUE"
	fi
	
	# Checkout the specified commit
	log_message "Checking out files from commit $commit_hash..." "$YELLOW"
	if ! git -C "$backup_dir" checkout "$commit_hash" -- .; then
		log_error "Failed to checkout commit $commit_hash for $folder_name"
		return 1
	fi
	
	# Ensure the restore directory exists
	mkdir -p "$restore_dir"
	
	# Copy restored files back to source, excluding .git and database backup
	log_message "Copying files to destination directory..." "$YELLOW"
	rsync -a --delete --exclude='.git' --exclude='*_backup.sql' "$backup_dir/" "$restore_dir/"
	
	log_message "File restore completed for $folder_name" "$GREEN"
	return 0
}

# Function to get site details from folder name
get_site_details() {
	local target_folder="$1"
	
	for site in "${SITES[@]}"; do
		IFS=$'\t' read -r folder_name db_name db_user db_pass <<< "$site"
		if [ "$folder_name" = "$target_folder" ]; then
			echo "$folder_name	$db_name	$db_user	$db_pass"
			return 0
		fi
	done
	
	return 1
}

# Main restore process
main() {
	# Check if folder name is provided
	if [ -z "$1" ]; then
		echo -e "${RED}Error: Folder name not provided${NC}"
		echo "Usage: $0 folder_name [commit_hash]"
		exit 1
	fi
	
	local folder_name="$1"
	local commit_hash="$2"
	
	# Create backup root directory if it doesn't exist
	mkdir -p "$BACKUP_ROOT"
	
	# Get site details
	site_details=$(get_site_details "$folder_name")
	
	if [ -z "$site_details" ]; then
		log_error "Site '$folder_name' not found in configuration"
		echo "Available sites:"
		for site in "${SITES[@]}"; do
			IFS=$'\t' read -r site_folder_name _ _ _ <<< "$site"
			echo "  - $site_folder_name"
		done
		exit 1
	fi
	
	IFS=$'\t' read -r _ db_name db_user db_pass <<< "$site_details"
	
	# If no commit hash is provided but -l or --list is specified, just list backups
	if [ "$commit_hash" = "-l" ] || [ "$commit_hash" = "--list" ]; then
		list_backups "$folder_name"
		exit 0
	fi
	
	log_message "## Starting restore for site: $folder_name"
	
	# Restore files first
	if ! restore_files "$folder_name" "$commit_hash"; then
		log_error "File restore failed for $folder_name"
		exit 1
	fi
	
	# Then restore database
	if ! restore_database "$folder_name" "$db_name" "$db_user" "$db_pass"; then
		log_error "Database restore failed for $folder_name"
		exit 1
	fi
	
	log_message "## Restore process completed successfully for $folder_name" "$GREEN"
}

# Show usage if help is requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
	echo "Usage: $0 folder_name [commit_hash]"
	echo
	echo "Arguments:"
	echo "  folder_name   The name of the site folder to restore"
	echo "  commit_hash   (Optional) The Git commit hash to restore from"
	echo "                If not provided, the latest backup will be used"
	echo
	echo "Options:"
	echo "  -l, --list    List available backups for the specified site"
	echo "  -h, --help    Show this help message"
	exit 0
fi

# Run the main function with provided arguments
main "$@"
