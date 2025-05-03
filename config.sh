# Site configurations
# Format: SITES=(
#    "source_folder_path	output_folder_name	database_name	db_user	db_password"
# )
#
# source_folder_path: Path to the website folder to backup (relative to this folder or absolute)
# output_folder_name: Name of the folder where backups will be stored (inside './backups')
# database_name: Name of the MySQL database to backup
# db_user: Database username
# db_password: Database password

SITES=(
	# "path/to/site1	site1	site1_db	site1_user	site1_pass"
	# Add more sites as needed
)

# Backup directory
BACKUP_ROOT="backups"

# MySQL binary paths (for MAMP or custom MySQL installations)
MYSQL_BIN_PATH=""  # Set to empty for system-wide MySQL

# Rsync exclusion patterns - add any paths you want to exclude
RSYNC_EXCLUDE=(
	"*.log"
	"cache/"
	"tmp/"
	".git/"
	"node_modules/"
	"*_backup.sql"
) 