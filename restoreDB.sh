#!/bin/bash
#
DATE=$(date '+%m%d%y-%H%M%S')
LOGFILE=/opt/oracle/restore-${DATE}.log
MANUAL=0

while getopts "m" opt
do
  case $opt in
    m)
      MANUAL=1
      ;;
    \?)
      echo "Usage: $0 [ -m ]"
      exit 1
      ;;
  esac
done

sudo -n chown -R oracle:dba /opt/oracle/oradata || {
   echo "Can not set ownership on oradata mount."
   exit 1
}

sudo -n chown -R oracle:dba /opt/oracle/archivelog || {
   echo "Can not set ownership on archivelog mount."
   exit 1
}

if [ ! -d /opt/oracle/oradata/dbconfig ]; then
   echo "Can not find DB configuration directory /opt/oracle/oradata/dbconfig."
   exit 1
fi

if [ -f /opt/oracle/oradata/dbconfig/*.dbconfig ]; then
   . /opt/oracle/oradata/dbconfig/*.dbconfig
else
   echo "Can not find dbconfig file in directory /opt/oracle/oradata/dbconfig."
   exit 1
fi

if [ -z "$ORACLE_HOME" -o -z "$ORACLE_BASE" -o -z "$REDOGROUPS" -o -z "$REDOPERGROUP" -o -z "$DATAFILES" -o -z "$DBCHARSET" ]; then
   echo "Error: missing required parameters, check the environment and config file."
   exit 1
fi

echo "[i] Restoring database as SID $ORACLE_SID"

# Check whether ORACLE_SID is defined
export ORACLE_SID=${ORACLE_SID:-oradb}

# Auto generate ORACLE PWD if not defined
export ORACLE_PWD=${ORACLE_PWD:-"`openssl rand -base64 8`1"}
echo "Oracle password for sys and system: $ORACLE_PWD"

# Create network related config files (sqlnet.ora, tnsnames.ora, listener.ora)
mkdir -p $ORACLE_HOME/network/admin
echo "NAME.DIRECTORY_PATH= (TNSNAMES, EZCONNECT, HOSTNAME)" > $ORACLE_HOME/network/admin/sqlnet.ora

# Listener.ora
echo "LISTENER =
(DESCRIPTION_LIST =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = IPC)(KEY = EXTPROC1))
    (ADDRESS = (PROTOCOL = TCP)(HOST = 0.0.0.0)(PORT = 1521))
  )
)

DEDICATED_THROUGH_BROKER_LISTENER=ON
DIAG_ADR_ENABLED = off
" > $ORACLE_HOME/network/admin/listener.ora

# Tnsnames.ora
echo "$ORACLE_SID=
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = 0.0.0.0)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = $ORACLE_SID)
    )
  )" > $ORACLE_HOME/network/admin/tnsnames.ora

echo -n "Starting the Listener ..."
lsnrctl start >> $LOGFILE 2>&1

if [ $? -ne 0 ]; then
   echo "Failed. See log for details."
   exit 1
else
   echo "Done."
fi

# Create database PFILE
echo "Creating PFILE for $ORACLE_SID"
sed -e 's/^[a-zA-Z0-9*]*\.//' \
    -e '/audit_file_dest/d' \
    -e '/control_files/d' \
    -e '/diagnostic_dest/d' \
    -e '/db_recovery_file_dest/d' \
    -e '/log_archive_dest_/d' \
    -e '/remote_login_passwordfile/d' \
    -e '/db_recovery_file_dest_size/d' \
    -e '/db_create_file_dest/d' /opt/oracle/oradata/dbconfig/init${ORACLE_SID}.ora > $ORACLE_HOME/dbs/init${ORACLE_SID}.ora

# Create and prep directory structure
echo "Creating directory structure"
[ ! -d /opt/oracle/oradata/$ORACLE_SID ] && mkdir /opt/oracle/oradata/$ORACLE_SID
[ ! -d /opt/oracle/oradata/$ORACLE_SID/backup ] && mkdir /opt/oracle/oradata/$ORACLE_SID/backup
[ ! -d /opt/oracle/oradata/$ORACLE_SID/flash_recovery_area ] && mkdir /opt/oracle/oradata/$ORACLE_SID/flash_recovery_area
[ ! -d /opt/oracle/admin/$ORACLE_SID/adump ] && mkdir -p /opt/oracle/admin/$ORACLE_SID/adump
[ -f /opt/oracle/oradata/$ORACLE_SID/control01.ctl ] && mv /opt/oracle/oradata/$ORACLE_SID/control01.ctl /opt/oracle/oradata/$ORACLE_SID/backup/control01.ctl.backup
[ -f /opt/oracle/oradata/$ORACLE_SID/control02.ctl ] && mv /opt/oracle/oradata/$ORACLE_SID/control02.ctl /opt/oracle/oradata/$ORACLE_SID/backup/control02.ctl.backup

# Move data files into place
dataFileArray=($(echo $DATAFILES | sed "s/,/ /g"))
dataFileArrayCount=${#dataFileArray[@]}
archFileArray=($(echo $ARCHDIRS | sed "s/,/ /g"))
mountFileRelativePath=$(dirname ${dataFileArray[0]} | sed -e "s#$DATAFILEMOUNTPOINT/##")

if [ -z "$dataFileArrayCount" -o $dataFileArrayCount -eq 0 ]; then
   echo "Data issue: no data files in the configuration."
   exit 1
fi

if [ ! -f "/opt/oracle/oradata/$mountFileRelativePath/${ORACLE_SID}.snap.scn" ]; then
   echo "Can not find snapshot scn file."
   hotBackupScn=0
else
   hotBackupScn=$(cat /opt/oracle/oradata/$mountFileRelativePath/${ORACLE_SID}.snap.scn)
fi

for dataFileName in "${dataFileArray[@]}"; do
    dataFileBaseName=$(basename $dataFileName)
    if [ ! -f /opt/oracle/oradata/${ORACLE_SID}/$dataFileBaseName ]; then
       echo "Moving /opt/oracle/oradata/$mountFileRelativePath/$dataFileBaseName to /opt/oracle/oradata/${ORACLE_SID}/$dataFileBaseName"
       mv /opt/oracle/oradata/$mountFileRelativePath/$dataFileBaseName /opt/oracle/oradata/${ORACLE_SID}/$dataFileBaseName
    fi
done

# Add updated init parameters
cat <<EOF >> $ORACLE_HOME/dbs/init${ORACLE_SID}.ora
db_recovery_file_dest='/opt/oracle/oradata/$ORACLE_SID/flash_recovery_area'
db_recovery_file_dest_size=2G
diagnostic_dest='$ORACLE_BASE'
control_files = ('/opt/oracle/oradata/$ORACLE_SID/control01.ctl', '/opt/oracle/oradata/$ORACLE_SID/control02.ctl')
audit_file_dest='/opt/oracle/admin/$ORACLE_SID/adump'
db_create_file_dest='/opt/oracle/oradata/$ORACLE_SID'
EOF

if [ -n "$ARCHIVELOGMODE" -a "$ARCHIVELOGMODE" = "true" ]; then

ARCHRELDIR=$(echo ${archFileArray[0]} | sed -e "s#^$DATAFILEMOUNTPOINT/##")
if [ "$ARCHRELDIR" != "${archFileArray[0]}" ]; then
   echo "Archive log directory must be located on a separate mount."
   exit 1
fi

cat <<EOF >> $ORACLE_HOME/dbs/init${ORACLE_SID}.ora
log_archive_dest_1='LOCATION=/opt/oracle/archivelog'
EOF

fi

SQL_SCRIPT=$(mktemp)

# Create SQL script to import the database
echo "Generating DB import SQL"
cat <<EOF > $SQL_SCRIPT
startup nomount pfile='$ORACLE_HOME/dbs/init${ORACLE_SID}.ora'
CREATE CONTROLFILE SET DATABASE $ORACLE_SID RESETLOGS
MAXLOGFILES 32
MAXLOGMEMBERS 2
MAXDATAFILES 4000
MAXINSTANCES 1
MAXLOGHISTORY 800
EOF

{
for groupNum in $(seq -f "%02g" 1 $REDOGROUPS); do
if [ "$groupNum" -eq 1 ]; then
   echo "LOGFILE"
fi

letters=( {a..z} )
for ((i=1; i<=REDOPERGROUP; i++)); do
if [ "$groupNum" -eq $REDOGROUPS -a $i -eq $REDOPERGROUP ]; then
   echo "GROUP $(($groupNum+0)) '/opt/oracle/oradata/$ORACLE_SID/redo${groupNum}${letters[i-1]}.log' SIZE ${REDOSIZE}M"
else
   echo "GROUP $(($groupNum+0)) '/opt/oracle/oradata/$ORACLE_SID/redo${groupNum}${letters[i-1]}.log' SIZE ${REDOSIZE}M,"
fi
done
done

count=1
echo "DATAFILE"
for dataFileName in "${dataFileArray[@]}"; do
destDataFileName=$(basename $dataFileName)
if [ $count -ne $dataFileArrayCount ]; then
   echo "'/opt/oracle/oradata/${ORACLE_SID}/${destDataFileName}',"
else
   echo "'/opt/oracle/oradata/${ORACLE_SID}/${destDataFileName}'"
fi
count=$(($count+1))
done

echo "CHARACTER SET ${DBCHARSET};"
} >> $SQL_SCRIPT

DATE=$(date '+%m%d%y-%H%M%S')
echo "--> Begin DB import on $DATE <--" >> $LOGFILE

# Run SQL script
echo -n "Importing database ..."
sqlplus -S / as sysdba <<EOF >> $LOGFILE
set heading off;
set pagesize 0;
set feedback off;
whenever sqlerror exit 1
whenever oserror exit 2
@$SQL_SCRIPT
EOF

if [ $? -ne 0 ]; then
   echo "Failed. See log for details."
   exit 1
else
   echo "Done."
fi

if [ "$MANUAL" -ne 0 ];then

# Manual recovery
echo "Import SQL Script: $SQL_SCRIPT"

fi

# If DB is hot backup clone recover is required prior to open
if [ -n "$ARCHIVELOGMODE" -a "$ARCHIVELOGMODE" = "true" ]; then

RMAN_SCRIPT_CATALOG=$(mktemp)
RMAN_SCRIPT_RECOVER=$(mktemp)

cat <<EOF > $RMAN_SCRIPT_CATALOG
run
{
catalog start with '/opt/oracle/archivelog' noprompt;
}
EOF

echo -n "Cataloging archived logs ..."
rman <<EOF >> $LOGFILE
connect target /
@$RMAN_SCRIPT_CATALOG
EOF

if [ $? -ne 0 ]; then
   echo "Failed. See log for details."
   exit 1
else
   echo "Done."
fi

lastSeqNum=`sqlplus -S / as sysdba <<EOF
set heading off;
set pagesize 0;
set feedback off;
select * from (select trim(sequence#) from v\\$archived_log order by sequence# desc) where rownum=1;
EOF`
lastSeqNum=$(($lastSeqNum+1))

if [ "$hotBackupScn" -ne 0 ]; then
   rmanRecoverOpt="until scn $hotBackupScn"
else
   rmanRecoverOpt="until sequence $lastSeqNum"
fi

cat <<EOF > $RMAN_SCRIPT_RECOVER
run
{
sql 'alter system set optimizer_mode=rule';
allocate channel ch01 device type disk;
recover database $rmanRecoverOpt ;
release channel ch01;
}
EOF

if [ "$MANUAL" -eq 0 ];then

# Automatic recovery (default)
echo -n "Recovering database ..."
rman <<EOF >> $LOGFILE
connect target /
@$RMAN_SCRIPT_RECOVER
EOF

if [ $? -ne 0 ]; then
   echo "Failed. See log for details."
   exit 1
else
   echo "Done."
fi

else

# Manual recovery
echo "RMAN Recover Script: $RMAN_SCRIPT_RECOVER"

fi # Manual or Auto


fi # If hot backup

if [ "$MANUAL" -eq 0 ];then

# Create password file
echo -n "Creating password file ..."
orapwd file=$ORACLE_HOME/dbs/orapw${ORACLE_SID} password=${ORACLE_PWD} entries=30 >> $LOGFILE 2>&1

if [ $? -ne 0 ]; then
   echo "Failed. See log for details."
   exit 1
else
   echo "Done."
fi

else

# Manual recovery
echo "Skipping password file."

fi

if [ "$MANUAL" -eq 0 ];then

# Open database
echo -n "Opening database ..."
sqlplus -S / as sysdba <<EOF >> $LOGFILE
set heading off;
set pagesize 0;
set feedback off;
alter database open resetlogs;
EOF

if [ $? -ne 0 ]; then
   echo "Failed. See log for details."
   exit 1
else
   echo "Done."
fi

else

# Manual recovery
echo "Skipping DB Open."

fi

if [ -n "$TEMPSIZE" -a $TEMP = "true" ]; then
TEMP_SCRIPT=$(mktemp)
cat <<EOF > $TEMP_SCRIPT
ALTER TABLESPACE TEMP ADD TEMPFILE '/opt/oracle/oradata/$ORACLE_SID/temp01.dbf' size $TEMPSIZE reuse;
EOF

if [ "$MANUAL" -eq 0 ];then

echo -n "Creating temp tablespace ..."
sqlplus -S / as sysdba <<EOF >> $LOGFILE
set heading off;
set pagesize 0;
set feedback off;
@$TEMP_SCRIPT
EOF

if [ $? -ne 0 ]; then
   echo "Failed. See log for details."
   exit 1
else
   echo "Done."
fi

else

# Manual recovery
echo "Temp Tablespace Create Script: $TEMP_SCRIPT"

fi # Manual or Auto
fi # Make Temp Tablespace

SPFILE_SCRIPT=$(mktemp)
cat <<EOF > $SPFILE_SCRIPT
create spfile from pfile;
EOF

if [ "$MANUAL" -eq 0 ];then

echo -n "Creating SPFILE ..."
sqlplus -S / as sysdba <<EOF >> $LOGFILE
set heading off;
set pagesize 0;
set feedback off;
@$SPFILE_SCRIPT
EOF

if [ $? -ne 0 ]; then
   echo "Failed. See log for details."
   exit 1
else
   echo "Done."
fi

else

# Manual recovery
echo "SPFILE create script: $SPFILE_SCRIPT"

fi

echo -n "Updating oratab ..."
echo "$ORACLE_SID:$ORACLE_HOME:N" >> /etc/oratab
echo "Done."

DATE=$(date '+%m%d%y-%H%M%S')
echo "--> End DB import on $DATE <--" >> $LOGFILE
##
