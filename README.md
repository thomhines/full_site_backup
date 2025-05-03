# Site Backup & Restore System

A robust shell-based solution for backing up and restoring website files and databases.

## Features

- Full website file backup using Git for version control
- MySQL database backup with retry logic
- Point-in-time restore capabilities
- Configurable site settings
- Detailed logging in Markdown format
- Batch processing for large sites
- Resource optimization for Git operations
- Comprehensive error handling and recovery

## Files

- `config.sh` - Configuration file for sites and backup settings
- `backup.sh` - Main script for backup and restore operations

## Setup

1. Update the `config.sh` file with your site details:

```bash
# Site configurations
# Format: SITES=(
#    "source_folder_path	output_folder_name	database_name	db_user	db_password"
# )
#
# source_folder_path: Path to the website folder to backup (relative to SITES_ROOT or absolute)
# output_folder_name: Name of the folder where backups will be stored (inside BACKUP_ROOT)
SITES=(
	# "site1	site1_backup	site1_db	site1_user	site1_pass"
	# Add more sites as needed
)

2. Configure MySQL paths (if needed):
   - For MAMP on macOS: Set `MYSQL_BIN_PATH="/Applications/MAMP/Library/bin"`
   - For XAMPP on Windows: Set `MYSQL_BIN_PATH="C:/xampp/mysql/bin"`
   - For system-wide MySQL: Set `MYSQL_BIN_PATH=""`

3. Make the script executable:

```bash
chmod +x backup.sh
```

## Usage

The script provides a command-line interface with several commands:

```bash 
./backup.sh [COMMAND] [OPTIONS]
```

### Commands

- `backup` - Run backup for all configured sites (default if no command specified)
- `restore <site> [commit]` - Restore a site from backup
- `list-backups <site>` - List all available backups for a specific site
- `list-sites` - List all configured sites
- `help` - Show usage information

### Backup

Run the backup script to back up all configured sites:

```bash
./backup.sh
# or explicitly
./backup.sh backup
```

This will:
- Create Git repositories for each site if they don't exist
- Back up all website files using Git for version control
- Export MySQL databases with retry logic
- Process large sites using batch operations if needed
- Log all operations to `backup_log.md`

### Restore

To restore a site from backup:

```bash
./backup.sh restore <site_name> [commit_hash]
```

Arguments:
- `site_name`: The output folder name of the site to restore
- `commit_hash`: (Optional) The Git commit hash to restore from
  If not provided, the latest backup will be used

Example usage:

```bash
# Restore the latest backup for 'site1_backup'
./backup.sh restore site1_backup

# Restore 'site1_backup' to a specific backup (can use partial commit hash)
./backup.sh restore site1_backup a1b2c3
```

### List Available Backups

To view available backups for a site:

```bash
./backup.sh list-backups site1_backup
```

### List Configured Sites

To see all sites configured in config.sh:

```bash
./backup.sh list-sites
```

## Logs

All operations are logged to `backup_log.md` with timestamps and detailed information about each step of the process.

## Resource Optimization

The script includes several optimizations to handle large sites:

- Git configuration tuning to reduce resource usage
- Batch processing for large directories
- Automatic retry logic with exponential backoff
- Detection and handling of resource limitations

## Security Considerations

- The backup configuration contains database credentials
- Ensure backup files are stored securely
- Consider encrypting sensitive backups

## Error Handling

The script includes comprehensive error handling:
- Retries for database operations
- Batch processing for Git operations that might fail due to resource constraints
- Detailed error logging
- Fallback mechanisms for large repositories

## Automation

For automated backups, add a cron job:

```bash
# Run backup daily at 2 AM
0 2 * * * /path/to/backup.sh
``` 