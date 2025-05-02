#!/bin/bash

# Ensure PATH is set correctly for cron, especially for running git
export PATH=/usr/local/cpanel/3rdparty/lib/path-bin:/usr/local/bin:/usr/bin:/bin

cd /home2/hilosdes

# Source the configuration file
source "$(dirname "$0")/backup_config.sh"

# Configure Git to use 'main' as default branch
git config --global init.defaultBranch main

# Allow Git to work across filesystem boundaries
export GIT_DISCOVERY_ACROSS_FILESYSTEM=1

# Create timestamp for backup naming
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

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
	
	# Perform the mysqldump
	log_message "Running mysqldump..." "$YELLOW"
	if ! mysqldump -u "$db_user" -p"$db_pass" "$db_name" > "$backup_file"; then
		log_error "Database backup failed for $folder_name: mysqldump error"
		rm -f "$backup_file"
		return 1
	fi
	
	log_message "Database backup completed for $folder_name" "$GREEN"
	
	log_message "Database backup cleanup completed for $folder_name" "$GREEN"
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
		
		# Initialize new repository
		if ! git -C "$repo_dir" init --initial-branch=main; then
			log_error "Failed to initialize Git repository in $repo_dir"
			return 1
		fi
		
		# Configure repository settings
		git -C "$repo_dir" config core.compression 0
		git -C "$repo_dir" config gc.auto 0
		git -C "$repo_dir" config pack.threads 1
		git -C "$repo_dir" config pack.window 0
		git -C "$repo_dir" config pack.depth 0
		
		# Create initial commit with empty state
		git -C "$repo_dir" commit --allow-empty -m "Initial commit"
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
	
	# Add and commit changes
	log_message "Committing changes to Git repository..." "$YELLOW"
	if ! git -C "$repo_dir" add .; then
		log_error "Failed to add files to Git repository in $repo_dir"
		return 1
	fi
	sleep 2
	
	# Check if there are any changes to commit
	if git -C "$repo_dir" diff --cached --quiet; then
		log_message "No file changes to commit" "$GREEN"
	else
		# Try to commit with retries
		local max_retries=3
		local retry_count=0
		local commit_success=0
		
		while [ $retry_count -lt $max_retries ] && [ $commit_success -eq 0 ]; do
			if git -C "$repo_dir" commit -m "Backup from $TIMESTAMP"; then
				commit_success=1
				log_message "Changes committed successfully" "$GREEN"
			else
				retry_count=$((retry_count + 1))
				if [ $retry_count -lt $max_retries ]; then
					log_message "Commit failed, retrying (attempt $retry_count of $max_retries)..." "$YELLOW"
					sleep 5
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
	
	git -C "$backup_dir" log --pretty=format:"%h - %s (%cr)" --date=relative
}

# Function to restore from backup
restore_backup() {
	local folder_name="$1"
	local commit_hash="$2"
	local backup_dir="$BACKUP_ROOT/$folder_name"
	local restore_dir="$folder_name"
	
	if [ ! -d "$backup_dir/.git" ]; then
		log_error "No Git repository found for $folder_name"
		return 1
	fi
	
	if ! git -C "$backup_dir" rev-parse --git-dir > /dev/null 2>&1; then
		log_error "Git repository not properly initialized for $folder_name"
		return 1
	fi
	
	if ! git -C "$backup_dir" checkout "$commit_hash" -- .; then
		log_error "Failed to checkout commit $commit_hash for $folder_name"
		return 1
	fi
	
	# Copy restored files back to source
	rsync -a --delete "$backup_dir/" "$restore_dir/"
	return 0
}

# Main backup process
main() {
	
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
}

# Run the main function
main