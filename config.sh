# Site configurations
# Format: SITES=(folder_name database_name db_user db_password)
SITES=(
	"test	bzzy	root	root"
	# "site1	site1_db	site1_user	site1_pass"
	# "site2	site2_db	site2_user	site2_pass"
	# "site3	site3_db	site3_user	site3_pass"
	# "site4	site4_db	site4_user	site4_pass"
)

# Backup directory
BACKUP_ROOT="backups"

# Backup retention settings
MONTHLY_BACKUP_MONTHS=24  # Keep monthly backups for 2 years
YEARLY_BACKUP_YEARS=5     # Keep yearly backups for 5 years

# Rsync exclusion patterns - add any paths you want to exclude
RSYNC_EXCLUDE=(
	"*.log"
	"cache/"
	"tmp/"
	".git/"
	"node_modules/"
	"*_backup.sql"
) 