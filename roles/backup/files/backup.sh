#!/bin/bash
# Available options :
#   --no-ugc : do not backup the user generated content
#   --no-db : do not backup the databases
#

OPTS=`getopt -a -l no-db -l no-ugc -- "$0" "$@"`
if [ $? != 0 ] # There was an error parsing the options
then
  exit 1 
fi

eval set -- "$OPTS"

NO_DB_FLAG=0
NO_UGC_FLAG=0

while true; do
  case "$1" in
    --no-db) NO_DB_FLAG=1; shift;;
    --no-ugc) NO_UGC_FLAG=1; shift;;
    --) shift; break;;
  esac
done

# Home root directory
# HOME_DIR=""

BACKUP_DIR="$HOME_DIR/backup"

# Some credentials for mysql/maria_db
# SHOW DATABASES
# SELECT
# LOCK TABLES
# RELOAD
MYSQL_USER='backup'

# Folders to ignore and patterns to ignore
IGNORE_FOLDERS="(mantis|public|lechiffre|data|default)"
IGNORE_PATTERNS="(prod|releases|current|\.dep)"
IGNORE_DB="(Database|information_schema|performance_schema|mysql|creative_engine)"

# Create a backup folder for each run
TIMESTAMP=$(date +"%F_%s")
THIS_BACKUP_DIR="$BACKUP_DIR/$TIMESTAMP"
mkdir "$THIS_BACKUP_DIR"

# FTP Stuff
HOSTNAME=`hostname`
FTP_HOST="dedibackup-dc3.online.net"

# Colors
green="\033[32m"
cyan="\033[36m"
yellow="\033[33m"
reset="\033[0m"

BACKED_UP="NO"

if [ $NO_DB_FLAG -eq 0 ]; then
  MYSQL=`type mysql >/dev/null 2>&1 && echo "ok" || echo "nok"`
  if [ "$MYSQL" = "ok" ]; then

    # Retrieves all databases
    databases=`mysql --user=$MYSQL_USER -p$MYSQL_PASSWORD -e "SHOW DATABASES;" | grep -Ev "$IGNORE_DB"`
    
    if [ `echo "$databases" | wc -l` -gt 2 ]; then

      echo -e "${cyan}Backing up databases${reset} :"
      mkdir "$THIS_BACKUP_DIR/mysql" 

      # Dumps everything
      for db in $databases; do
        printf " - $db .."
        mysqldump --single-transaction --routines --default-character-set=utf8 --hex-blob --force --opt --user=$MYSQL_USER -p$MYSQL_PASSWORD --result-file=$THIS_BACKUP_DIR/mysql/$db.sql --databases $db
        gzip --best $THIS_BACKUP_DIR/mysql/$db.sql
        echo -e "${green}done${reset}."
        logger -p cron.info "Database $db backed up [local]"
      done

      BACKED_UP="YES"

    else
    
      logger -p cron.info "No database to backup"
    
    fi


  fi
else
  echo -e "${yellow}The 'no-db' flag was used, not backing up databases${reset}."
  logger -p cron.info "Flag 'no-db' : not backing up databases"
fi

if [ $NO_UGC_FLAG -eq 0 ]; then 

  folders_count=`find $HOME_DIR/www/ -maxdepth 1 -mindepth 1 -type d | wc -l`

  if [ "$folders_count" -gt 0 ]; then

    # Retrieves all folders to backup
    folders=`ls -d $HOME_DIR/www/*/*/ | grep -Ev "$IGNORE_FOLDERS" | grep -Ev "\w\/$IGNORE_PATTERNS"`

    if [ `echo "$folders" | wc -l` -gt 0 ]; then

      # if folders length > 0...
      echo -e "${cyan}Backing up ugc folders${reset} :"
      mkdir "$THIS_BACKUP_DIR/ugc" 

      # Backup files
      for folder in $folders; do 
        printf " - $folder .."
        if [ "$(find $folder -type f | wc -l)" -gt 0 ]; then
          mkdir -p $THIS_BACKUP_DIR/ugc/$(basename $(dirname $folder))
          find $folder -type d -o -size -512M -print0 | xargs -0 tar -cPzvf $THIS_BACKUP_DIR/ugc/$(basename $(dirname $folder))/$(basename $folder).tar > /dev/null
          echo -e "${green}done${reset}."
          logger -p cron.info "Folder $(basename $(dirname $folder))/$(basename $folder) backed up [local]"
        else
          echo -e "${yellow}empty, not backing up. ${green}done${reset}."
          logger -p cron.notice "Folder $(basename $(dirname $folder))/$(basename $folder) empty - not backed up [local]"
        fi
      done

      BACKED_UP="YES"

    else

      logger -p cron.info "No folders to backup"

    fi

  fi
else
  echo -e "${yellow}The 'no-ugc' flag was used, not backing up ugc folders${reset}."
  logger -p cron.info "Flag 'no-ugc' : not backing up ugc folders"
fi

# Update the "last" symlink
if [ "$BACKED_UP" = "YES" ]; then
  ln -sfn "$THIS_BACKUP_DIR" "$BACKUP_DIR/last"

  # create a tar of the folder to sync with ftp

  # Syncs last backup with a FTP if any
  echo -e "${cyan}Syncing with FTP${reset} :"
  ftp $FTP_HOST <<EOF
  binary
  passive
  cd "$HOSTNAME"
  put "| tar -cPvf - $THIS_BACKUP_DIR" $TIMESTAMP.tar
  quit
EOF
  echo -e "${green}Backed up${reset}. Exiting."
  logger -p cron.info "Backups synced to $FTP_HOST"

else
  rmdir "$THIS_BACKUP_DIR"
  echo -e "${green}Nothing to be done${reset}. Exiting."
fi

