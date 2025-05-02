#!/bin/bash

# Ensure PATH is set correctly for cron, especially for running git
export PATH=/usr/local/cpanel/3rdparty/lib/path-bin:/usr/local/bin:/usr/bin:/bin

cd /home2/hilosdes

# Source the configuration file
source "$(dirname "$0")/config.sh"

# Configure Git to use 'main' as default branch
git config --global init.defaultBranch main

# Configure Git for better resource handling
git config --global core.compression 0
git config --global gc.auto 0
git config --global pack.threads 1
git config --global pack.window 0
git config --global pack.depth 0

# Disable Git's parallel processing for large file operations
git config --global core.preloadIndex false
git config --global core.fsmonitor false
git config --global core.untrackedCache false

# Allow Git to work across filesystem boundaries
export GIT_DISCOVERY_ACROSS_FILESYSTEM=1

# Create timestamp for backup naming
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
NICE_TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

# Set log file for Markdown output
LOG_MD="backup_log.md"

# Add timestamp at the very beginning of the process
{
	echo 
	echo
	echo
	echo
	echo "--------------------------------"
	echo
	echo
	echo
	echo "**Backup started:**"
	echo "$NICE_TIMESTAMP"
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
	local color="$2" # Unused, but kept for compatibility
	
	# Print to screen as before
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
	
	# Append to Markdown log file as a code block for visibility
	echo "- *ERROR*: $message" >> "$LOG_MD"
}

# Function to handle Git add with retry and batching
git_add_with_retry() {
	local repo_dir="$1"
	local max_retries=5
	local retry_count=0
	local success=0
	local batch_size=1000
	
	# First try adding everything at once
	log_message "Adding files to Git repository..." "$YELLOW"
	if git -C "$repo_dir" add .; then
		return 0
	fi
	
	# If the bulk add failed, try batch processing
	log_message "Bulk add failed, trying batch processing..." "$YELLOW"
	
	# Find all files except .git directory files
	local file_list=$(find "$repo_dir" -type f -not -path "*/\.git/*")
	local total_files=$(echo "$file_list" | wc -l)
	
	log_message "Processing $total_files files in batches of $batch_size" "$YELLOW"
	
	# Process in batches
	local current=0
	while read -r file; do
		# Skip empty lines
		[ -z "$file" ] && continue
		
		current=$((current + 1))
		
		# Remove repo_dir prefix from file path for git add
		local rel_file="${file#$repo_dir/}"
		
		# Try to add the file with retries
		retry_count=0
		success=0
		
		while [ $retry_count -lt $max_retries ] && [ $success -eq 0 ]; do
			if git -C "$repo_dir" add "$rel_file" 2>/dev/null; then
				success=1
			else
				retry_count=$((retry_count + 1))
				# Only log every 100 files to avoid excessive logging
				if [ $((current % 100)) -eq 0 ]; then
					log_message "Retrying file $current of $total_files (attempt $retry_count)..." "$YELLOW"
				fi
				sleep 1
			fi
		done
		
		# Log progress periodically
		if [ $((current % 1000)) -eq 0 ]; then
			log_message "Processed $current of $total_files files..." "$YELLOW"
		fi
		
	done <<< "$file_list"
	
	log_message "Completed adding $total_files files to Git" "$GREEN"
	return 0
}

# Function to backup MySQL database
backup_database() {
	local folder_name="$1"
	local db_name="$2"
	local db_user="$3"
	local db_pass="$4"
	
	local backup_dir="$BACKUP_ROOT/$folder_name"
	mkdir -p "$backup_dir"
	
	local backup_file="$backup_dir/${db_name}_backup.sql"
	
	log_message "Starting database backup for $folder_name" "$YELLOW"
	
	# Perform the mysqldump with retries
	log_message "Running mysqldump..." "$YELLOW"
	
	local max_retries=3
	local retry_count=0
	local dump_success=0
	
	while [ $retry_count -lt $max_retries ] && [ $dump_success -eq 0 ]; do
		if mysqldump -u "$db_user" -p"$db_pass" "$db_name" > "$backup_file"; then
			dump_success=1
			log_message "Database dump completed successfully" "$GREEN"
		else
			retry_count=$((retry_count + 1))
			if [ $retry_count -lt $max_retries ]; then
				log_message "Database dump failed, retrying (attempt $retry_count of $max_retries)..." "$YELLOW"
				sleep 5
			else
				log_error "Database backup failed for $folder_name: mysqldump error after $max_retries attempts"
				rm -f "$backup_file"
				return 1
			fi
		fi
	done
	
	log_message "Database backup completed for $folder_name" "$GREEN"
	
	log_message "Database backup cleanup completed for $folder_name" "$GREEN"
	return 0
}

# Function to initialize or update Git repository
setup_git_repo() {
	local repo_dir="$1"
	local source_dir="$2"
	
	# Create backup directory if it doesn't exist
	mkdir -p "$repo_dir"
	
	# Initialize Git repository if it doesn't exist
	if [ ! -d "$repo_dir/.git" ]; then
		log_message "Initializing new Git repository in $repo_dir" "$YELLOW"
		
		# Initialize new repository with retries
		local init_success=0
		local max_retries=3
		local retry_count=0
		
		while [ $retry_count -lt $max_retries ] && [ $init_success -eq 0 ]; do
			if git -C "$repo_dir" init --initial-branch=main; then
				init_success=1
			else
				retry_count=$((retry_count + 1))
				if [ $retry_count -lt $max_retries ]; then
					log_message "Git init failed, retrying (attempt $retry_count of $max_retries)..." "$YELLOW"
					sleep 3
				else
					log_error "Failed to initialize Git repository in $repo_dir after $max_retries attempts"
					return 1
				fi
			fi
		done
		
		# Configure repository settings for performance
		git -C "$repo_dir" config core.compression 0
		git -C "$repo_dir" config gc.auto 0
		git -C "$repo_dir" config pack.threads 1
		git -C "$repo_dir" config pack.window 0
		git -C "$repo_dir" config pack.depth 0
		git -C "$repo_dir" config core.preloadIndex false
		git -C "$repo_dir" config core.fsmonitor false
		git -C "$repo_dir" config core.untrackedCache false
		
		# Create initial commit with empty state
		if ! git -C "$repo_dir" commit --allow-empty -m "Initial commit"; then
			log_error "Failed to create initial commit in Git repository in $repo_dir"
			return 1
		fi
		sleep 2
	fi
	
	# Verify Git repository is working
	if ! git -C "$repo_dir" rev-parse --git-dir > /dev/null 2>&1; then
		log_error "Git repository not properly initialized in $repo_dir"
		return 1
	fi
	
	# Copy files to backup directory, excluding .git and preserving database backup
	log_message "Copying files to backup directory..." "$YELLOW"
	rsync -a --exclude='.git' --exclude='*_backup.sql' "$source_dir/" "$repo_dir/"
	sleep 2
	
	# Add and commit changes using our custom function with batching and retry
	if ! git_add_with_retry "$repo_dir"; then
		log_error "Failed to add files to Git repository in $repo_dir"
		return 1
	fi
	sleep 2
	
	# Check if there are any changes to commit
	if git -C "$repo_dir" diff --cached --quiet; then
		log_message "No file changes to commit" "$GREEN"
	else
		# Try to commit with retries
		local max_retries=5
		local retry_count=0
		local commit_success=0
		
		while [ $retry_count -lt $max_retries ] && [ $commit_success -eq 0 ]; do
			if git -C "$repo_dir" commit -m "Backup from $NICE_TIMESTAMP"; then
				commit_success=1
				log_message "Changes committed successfully" "$GREEN"
			else
				retry_count=$((retry_count + 1))
				if [ $retry_count -lt $max_retries ]; then
					log_message "Commit failed, retrying (attempt $retry_count of $max_retries)..." "$YELLOW"
					
					# Check if we got the threaded lstat error
					if [ $retry_count -eq 1 ]; then
						log_message "Trying to optimize Git settings to handle resource limitations..." "$YELLOW"
						git -C "$repo_dir" config pack.threads 1
						git -C "$repo_dir" config core.preloadIndex false
						git -C "$repo_dir" config core.fsmonitor false
						git -C "$repo_dir" config core.untrackedCache false
						
						# Wait longer between retries
						sleep 10
					else
						sleep 5
					fi
				else
					log_error "Failed to commit changes to Git repository in $repo_dir after $max_retries attempts"
					return 1
				fi
			fi
		done
		
		sleep 2
		
		# Clean up Git repository
		log_message "Cleaning up Git repository..." "$YELLOW"
		rm -f "$repo_dir/.git/gc.log" 2>/dev/null
		git -C "$repo_dir" gc --auto --quiet
	fi
	
	return 0
}

# Function to backup files using Git
backup_files() {
	local folder_name="$1"
	local source_dir="$folder_name"
	local backup_dir="$BACKUP_ROOT/$folder_name"
	
	log_message "Starting file backup for $folder_name" "$YELLOW"
	
	# Setup Git repository and perform backup
	if setup_git_repo "$backup_dir" "$source_dir"; then
		log_message "File backup completed for $folder_name" "$GREEN"
	else
		log_error "File backup failed for $folder_name"
		return 1
	fi
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
		echo -e "${RED}No Git repository found for $folder_name${NC}"
		return 1
	fi
	
	if ! git -C "$backup_dir" rev-parse --git-dir > /dev/null 2>&1; then
		echo -e "${RED}Git repository not properly initialized for $folder_name${NC}"
		return 1
	fi
	
	echo -e "${BLUE}Available backups for $folder_name:${NC}"
	git -C "$backup_dir" log --pretty=format:"%h - %s (%cr)" --date=relative
	echo
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

# Function to list all configured sites
list_sites() {
	echo -e "${BLUE}Configured sites:${NC}"
	for site in "${SITES[@]}"; do
		IFS=$'\t' read -r folder_name db_name db_user db_pass <<< "$site"
		echo "  - $folder_name"
	done
}

# Main restore process
run_restore() {
	local folder_name="$1"
	local commit_hash="$2"
	
	# Check if folder name is provided
	if [ -z "$folder_name" ]; then
		echo -e "${RED}Error: Folder name not provided${NC}"
		echo "Usage: $0 restore <site_name> [commit_hash]"
		echo "To see available sites, use: $0 list-sites"
		exit 1
	fi
	
	# Create backup root directory if it doesn't exist
	mkdir -p "$BACKUP_ROOT"
	
	# Get site details
	site_details=$(get_site_details "$folder_name")
	
	if [ -z "$site_details" ]; then
		echo -e "${RED}Site '$folder_name' not found in configuration${NC}"
		echo "Available sites:"
		for site in "${SITES[@]}"; do
			IFS=$'\t' read -r site_folder_name _ _ _ <<< "$site"
			echo "  - $site_folder_name"
		done
		exit 1
	fi
	
	IFS=$'\t' read -r _ db_name db_user db_pass <<< "$site_details"
	
	echo -e "${GREEN}Starting restore for site: $folder_name${NC}"
	
	# Update log file
	{
		echo 
		echo
		echo "--------------------------------"
		echo
		echo "**Restore started:**"
		echo "$(date '+%Y-%m-%d %H:%M:%S')"
		echo "Site: $folder_name"
		echo
	} >> "$LOG_MD"
	
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
	echo -e "${GREEN}Restore completed successfully for $folder_name${NC}"
}

# Function to display usage information
show_usage() {
	echo "Usage: $0 [COMMAND] [OPTIONS]"
	echo
	echo "Commands:"
	echo "  backup                     Run backup for all configured sites (default)"
	echo "  restore <site> [commit]    Restore a site from backup"
	echo "  list-backups <site>        List available backups for a specific site"
	echo "  list-sites                 List all configured sites"
	echo "  help                       Show this help message"
	echo
	echo "Options:"
	echo "  -h, --help                 Show this help message"
	echo
	echo "Examples:"
	echo "  $0                         Run backup for all sites"
	echo "  $0 restore site1           Restore 'site1' from the latest backup"
	echo "  $0 restore site1 a1b2c3    Restore 'site1' from a specific backup commit"
	echo "  $0 list-backups site1      List all backups for 'site1'"
	echo "  $0 list-sites              Show all configured sites"
}

# Main backup process
run_backup() {
	# Create backup root directory if it doesn't exist
	mkdir -p "$BACKUP_ROOT"
	
	# Process each site
	for site in "${SITES[@]}"; do
		IFS=$'\t' read -r folder_name db_name db_user db_pass <<< "$site"
		echo " " >> "$LOG_MD"
		log_message "### Processing site: $folder_name"
		backup_database "$folder_name" "$db_name" "$db_user" "$db_pass"
		backup_files "$folder_name"
		echo " " >> "$LOG_MD"
		echo
	done
	
	log_message "## Backup process completed"
	echo
}

# Process command line arguments
process_args() {
	# If no arguments, run backup
	if [ $# -eq 0 ]; then
		run_backup
		return
	fi
	
	# Handle arguments
	case "$1" in
		backup)
			run_backup
			;;
		restore)
			run_restore "$2" "$3"
			;;
		list-backups)
			if [ -z "$2" ]; then
				echo -e "${RED}Error: Site name is required for list-backups${NC}"
				echo "Usage: $0 list-backups <site_name>"
				echo "To see available sites, use: $0 list-sites"
				exit 1
			fi
			list_backups "$2"
			;;
		list-sites)
			list_sites
			;;
		help|--help|-h)
			show_usage
			;;
		*)
			echo -e "${RED}Error: Unknown command '$1'${NC}"
			show_usage
			exit 1
			;;
	esac
}

# Run the main function with arguments
process_args "$@"