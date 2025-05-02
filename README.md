# Site Backup & Restore System

A robust shell-based solution for backing up and restoring website files and databases.

## Features

- Full website file backup using Git for version control
- MySQL database backup
- Point-in-time restore capabilities
- Configurable site settings
- Detailed logging in Markdown format

## Files

- `backup_config.sh` - Configuration file for sites and backup settings
- `backup_sites.sh` - Main backup script
- `restore_site.sh` - Script to restore sites from backups

## Setup

1. Update the `backup_config.sh` file with your site details:

```bash
# Site configurations
# Format: SITES=(folder_name database_name db_user db_password)
SITES=(
	"site1	site1_db	site1_user	site1_pass"
	# Add more sites as needed
)

# Backup directory
BACKUP_ROOT="backups"
```

2. Make scripts executable:

```bash
chmod +x backup_sites.sh restore_site.sh
```

## Usage

### Backup

Run the backup script to back up all configured sites:

```bash
./backup_sites.sh
```

This will:
- Create Git repositories for each site if they don't exist
- Back up all website files using Git for version control
- Export MySQL databases
- Log all operations to `backup_log.md`

### Restore

To restore a site:

```bash
./restore_site.sh <folder_name> [commit_hash]
```

Arguments:
- `folder_name`: The name of the site folder to restore
- `commit_hash`: (Optional) The Git commit hash to restore from
  If not provided, the latest backup will be used

Options:
- `-l, --list`: List available backups for the specified site
- `-h, --help`: Show help message

Examples:

```bash
# Restore the latest backup for 'site1'
./restore_site.sh site1

# List available backups for 'site1'
./restore_site.sh site1 --list

# Restore 'site1' to a specific backup (can use partial commit hash)
./restore_site.sh site1 a1b2c3
```

## Logs

- Backup operations are logged to `backup_log.md`
- Restore operations are logged to `restore_log.md`

## Security Considerations

- The backup configuration contains database credentials
- Ensure backup files are stored securely
- Consider encrypting sensitive backups

## Automation

For automated backups, add a cron job:

```bash
# Run backup daily at 2 AM
0 2 * * * /path/to/backup_sites.sh
``` 