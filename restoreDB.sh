#!/bin/bash
#
DATE=$(date '+%m%d%y-%H%M%S')
LOGFILE=/opt/oracle/restore-${DATE}.log
MANUAL=0
BKUPCOPY=${BKUPCOPY:-0}
CREATE_AUX=0

while getopts "ma" opt
do
  case $opt in
    m)
      MANUAL=1
      ;;
    a)
      CREATE_AUX=1
      ;;
    \?)
      echo "Usage: $0 [ -m ]"
      exit 1
      ;;
  esac
done

# Check whether ORACLE_SID is defined
export ORACLE_SID=${ORACLE_SID:-oradb}
export AUX_SID=${AUX_SID:-auxdb}

sudo -n chown -R oracle:dba /opt/oracle/oradata || {
   echo "Can not set ownership on oradata mount."
   exit 1
}

if [ -d /opt/oracle/archivelog ]; then
sudo -n chown -R oracle:dba /opt/oracle/archivelog || {
   echo "Can not set ownership on archivelog mount."
   exit 1
}
fi

if [ ! -d /opt/oracle/oradata/dbconfig -a ! -d /opt/oracle/oradata/$ORACLE_SID/dbconfig -a ! /opt/oracle/archivelog/dbconfig ]; then
   echo "Can not find DB configuration directory."
   exit 1
fi

if [ -f /opt/oracle/oradata/dbconfig/*.dbconfig ]; then
   echo "Sourcing configuration $(ls /opt/oracle/oradata/dbconfig/*.dbconfig)"
   . /opt/oracle/oradata/dbconfig/*.dbconfig
elif [ -f /opt/oracle/oradata/$ORACLE_SID/dbconfig/*.dbconfig ]; then
   echo "Sourcing configuration $(ls /opt/oracle/oradata/$ORACLE_SID/dbconfig/*.dbconfig)"
   . /opt/oracle/oradata/$ORACLE_SID/dbconfig/*.dbconfig
elif [ -f /opt/oracle/archivelog/dbconfig/*.dbconfig ]; then
   echo "Sourcing configuratiopn $(ls /opt/oracle/archivelog/dbconfig/*.dbconfig)"
   . /opt/oracle/archivelog/dbconfig/*.dbconfig
else
   echo "Can not find dbconfig file in /opt/oracle/oradata/dbconfig or /opt/oracle/oradata/$ORACLE_SID/dbconfig or /opt/oracle/archivelog/dbconfig."
   exit 1
fi

if [ -z "$ORACLE_HOME" -o -z "$ORACLE_BASE" -o -z "$REDOGROUPS" -o -z "$REDOPERGROUP" -o -z "$DATAFILES" -o -z "$DBCHARSET" ]; then
   echo "Error: missing required parameters, check the environment and config file."
   exit 1
fi

echo "[i] Restoring database as SID $ORACLE_SID"

# Auto generate ORACLE PWD if not defined
export ORACLE_PWD=${ORACLE_PWD:-"`openssl rand -base64 8`1"}
echo "Oracle password for sys and system: $ORACLE_PWD"

dbMajorRev=$(echo $DBVERSION | sed -n -e 's/^\([0-9]*\)\..*$/\1/p')
dbMinorRev=$(echo $DBVERSION | sed -n -e 's/^[0-9]*\.\([0-9]*\)\..*$/\1/p')

if [ "$dbMajorRev" -lt 11 ]; then
   echo "DB Version $dbMajorRev not supported."
   exit 1
fi

echo "Performing DB restore for version $dbMajorRev"

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

# Check if the listener is running and stop if it is
lsnrctl status >/dev/null 2>&1
if [ $? -eq 0 ]; then
   echo "Listener running, stopping ..."
   lsnrctl stop
fi

echo -n "Starting the Listener ..."
lsnrctl start >> $LOGFILE 2>&1

if [ $? -ne 0 ]; then
   echo "Failed. See log for details."
   exit 1
else
   echo "Done."
fi

if [ "$BKUPCOPY" -ne 1 ]; then
# Hot backup snapshot restore

if [ -f /opt/oracle/oradata/dbconfig/init${ORIG_ORACLE_SID}.ora ]; then
   backupInitFile=/opt/oracle/oradata/dbconfig/init${ORIG_ORACLE_SID}.ora
elif [ -f /opt/oracle/archivelog/dbconfig/init${ORIG_ORACLE_SID}.ora ]; then
   backupInitFile=/opt/oracle/archivelog/dbconfig/init${ORIG_ORACLE_SID}.ora
else
   echo "Can not find instance ${ORIG_ORACLE_SID} PFILE."
   exit 1
fi

# Modify database PFILE
echo "Creating PFILE for $ORACLE_SID"
sed -e 's/^[a-zA-Z0-9*]*\.//' \
    -e '/db_name/d' \
    -e '/audit_file_dest/d' \
    -e '/control_files/d' \
    -e '/diagnostic_dest/d' \
    -e '/db_recovery_file_dest/d' \
    -e '/log_archive_dest_/d' \
    -e '/remote_login_passwordfile/d' \
    -e '/db_recovery_file_dest_size/d' \
    -e '/local_listener/d' \
    -e '/db_create_file_dest/d' $backupInitFile > $ORACLE_HOME/dbs/init${ORACLE_SID}.ora

# Create and prep directory structure
echo "Creating directory structure"
ORIG_SID_UPPER=${ORIG_ORACLE_SID^^}
if [ -d /opt/oracle/oradata/$ORIG_SID_UPPER ]; then
   ORIG_ORACLE_SID=$ORIG_SID_UPPER
fi
if [ ! -d /opt/oracle/oradata/$ORACLE_SID ]; then
   if [ -d /opt/oracle/oradata/$ORIG_ORACLE_SID ]; then
      mv /opt/oracle/oradata/$ORIG_ORACLE_SID /opt/oracle/oradata/$ORACLE_SID
   else
      echo "Can not locate dbf root directory, neither /opt/oracle/oradata/$ORACLE_SID nor /opt/oracle/oradata/$ORIG_ORACLE_SID found."
      exit 1
   fi
fi
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

# Add updated init parameters
cat <<EOF >> $ORACLE_HOME/dbs/init${ORACLE_SID}.ora
db_name='$ORACLE_SID'
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

fi # Archive mode

else # Backup copy snapshot

dataFileArray=($(echo $DATAFILES | sed "s/,/ /g"))
dataFileArrayCount=${#dataFileArray[@]}
hotBackupScn=0

# Create new PFILE
cat <<EOF > $ORACLE_HOME/dbs/init${ORACLE_SID}.ora
db_name='$ORACLE_SID'
memory_target=2G
processes = 1000
db_block_size=8192
db_domain=''
db_recovery_file_dest='/opt/oracle/oradata/$ORACLE_SID/flash_recovery_area'
db_recovery_file_dest_size=2G
diagnostic_dest='$ORACLE_BASE'
dispatchers='(PROTOCOL=TCP) (SERVICE=${ORACLE_SID}XDB)'
open_cursors=5000
remote_login_passwordfile='EXCLUSIVE'
control_files = ('/opt/oracle/oradata/$ORACLE_SID/control02.ctl', '/opt/oracle/oradata/$ORACLE_SID/control03.ctl')
audit_file_dest='$ORACLE_BASE/admin/$ORACLE_SID/adump'
db_create_file_dest='/opt/oracle/oradata/$ORACLE_SID'
log_archive_dest_1='LOCATION=/opt/oracle/oradata/$ORACLE_SID/archivelog'
compatible ='$DBVERSION'
EOF

if [ "$dbMajorRev" -gt 11 ]; then
cat <<EOF >> $ORACLE_HOME/dbs/init${ORACLE_SID}.ora
enable_pluggable_database=true
undo_tablespace='UNDOTBS1'
EOF
fi

[ ! -d "/opt/oracle/oradata/$ORACLE_SID/flash_recovery_area" ] && mkdir /opt/oracle/oradata/$ORACLE_SID/flash_recovery_area
[ ! -d "$ORACLE_BASE/admin/$ORACLE_SID/adump" ] && mkdir -p $ORACLE_BASE/admin/$ORACLE_SID/adump
[ ! -d "$ORACLE_BASE/admin/$ORACLE_SID/dpdump" ] && mkdir -p $ORACLE_BASE/admin/$ORACLE_SID/dpdump
[ ! -d "/opt/oracle/oradata/$ORACLE_SID/archivelog" ] && mkdir /opt/oracle/oradata/$ORACLE_SID/archivelog

fi # Backup type

######################################
## Create Aux Instance If Requested ##
######################################

if [ "$CREATE_AUX" -eq 1 ]; then

echo "Creating PFILE for aux instance $AUX_SID"
sed -e 's/^[a-zA-Z0-9*]*\.//' \
    -e '/db_name/d' \
    -e '/audit_file_dest/d' \
    -e '/control_files/d' \
    -e '/diagnostic_dest/d' \
    -e '/db_recovery_file_dest/d' \
    -e '/log_archive_dest_/d' \
    -e '/remote_login_passwordfile/d' \
    -e '/db_recovery_file_dest_size/d' \
    -e '/memory_target/d' \
    -e '/db_create_file_dest/d' $ORACLE_HOME/dbs/init${ORACLE_SID}.ora > $ORACLE_HOME/dbs/init${AUX_SID}.ora

# Add updated init parameters
cat <<EOF >> $ORACLE_HOME/dbs/init${AUX_SID}.ora
db_name='$AUX_SID'
memory_target=960M
db_recovery_file_dest='/opt/oracle/oradata/$AUX_SID/flash_recovery_area'
db_recovery_file_dest_size=2G
diagnostic_dest='$ORACLE_BASE'
control_files = ('/opt/oracle/oradata/$AUX_SID/control01.ctl', '/opt/oracle/oradata/$AUX_SID/control02.ctl')
audit_file_dest='/opt/oracle/admin/$AUX_SID/adump'
db_create_file_dest='/opt/oracle/oradata/$AUX_SID'
log_archive_dest_1='LOCATION=/opt/oracle/oradata/$AUX_SID/archivelog'
undo_tablespace='UNDOTBS1'
EOF

[ ! -d "/opt/oracle/oradata/$AUX_SID" ] && mkdir /opt/oracle/oradata/$AUX_SID
[ ! -d "/opt/oracle/oradata/$AUX_SID/flash_recovery_area" ] && mkdir /opt/oracle/oradata/$AUX_SID/flash_recovery_area
[ ! -d "$ORACLE_BASE/admin/$AUX_SID/adump" ] && mkdir -p $ORACLE_BASE/admin/$AUX_SID/adump
[ ! -d "$ORACLE_BASE/admin/$AUX_SID/dpdump" ] && mkdir -p $ORACLE_BASE/admin/$AUX_SID/dpdump
[ ! -d "/opt/oracle/oradata/$AUX_SID/archivelog" ] && mkdir /opt/oracle/oradata/$AUX_SID/archivelog

echo -n "Creating aux instance password file ..."
orapwd file=$ORACLE_HOME/dbs/orapw${AUX_SID} password=${ORACLE_PWD} entries=30 >> $LOGFILE 2>&1

if [ $? -ne 0 ]; then
   echo "Failed. See log for details."
   exit 1
else
   echo "Done."
fi

fi

############################################
## Specific Incremental Merge PDB Restore ##
############################################

if [ "$dbMajorRev" -ge 12 -a "$BKUPCOPY" -eq 1 -a -n "$PDB_NAMES" ]; then

echo -n "Creating instance password file ..."
orapwd file=$ORACLE_HOME/dbs/orapw${ORACLE_SID} password=${ORACLE_PWD} entries=30 >> $LOGFILE 2>&1

if [ $? -ne 0 ]; then
   echo "Failed. See log for details."
   exit 1
else
   echo "Done."
fi

pdbDuplicateScript=$(mktemp)
pdbOpenScript=$(mktemp)

if [ -n "$PDB_NAMES" ]; then
   count=1
   pdbNameArray=($(echo $PDB_NAMES | sed "s/,/ /g"))
   for pdbName in "${pdbNameArray[@]}"; do
       if [ "$pdbName" = "pdbseed" ]; then
          continue
       fi
       echo "DUPLICATE database to ${ORACLE_SID} noopen backup location '/opt/oracle/oradata/$ORACLE_SID' ;" >> $pdbDuplicateScript
       echo "alter pluggable database ${pdbName} open;" >> $pdbOpenScript
   count=$(($count+1))
   done
fi

if [ "$MANUAL" -ne 0 ];then

echo "PDB duplicate script: $pdbDuplicateScript"

else

echo -n "Opening instance unmounted ..."

sqlplus -S / as sysdba <<EOF >> $LOGFILE
set heading off;
set pagesize 0;
set feedback off;
startup nomount
EOF

if [ $? -ne 0 ]; then
   echo "Failed. See log for details."
   exit 1
else
   echo "Done."
fi

echo -n "Duplicating PDBs to CDB ${ORACLE_SID} ..."
rman auxiliary / <<EOF >> $LOGFILE
@$pdbDuplicateScript
EOF

if [ $? -ne 0 ]; then
   echo "Failed. See log for details."
   exit 1
else
   echo "Done."
fi

echo -n "Opening CDB and PDBs ..."
sqlplus -S / as sysdba <<EOF >> $LOGFILE
set heading off;
set pagesize 0;
set feedback off;
alter database open resetlogs;
@$pdbOpenScript
EOF

if [ $? -ne 0 ]; then
   echo "Failed. See log for details."
   exit 1
else
   echo "Done."
fi

fi # Auto or Manual

else

#######################################
## Non Incremental Merge PDB Restore ##
#######################################

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
if [ "$BKUPCOPY" -ne 1 ]; then
   destDataFileName=$(echo $dataFileName | sed -e "s#^$DATAFILEMOUNTPOINT/$ORIG_ORACLE_SID/##")
else
   destDataFileName=$(echo $dataFileName | sed -e "s#^$DATAFILEMOUNTPOINT/##")
fi
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

if [ "$MANUAL" -eq 0 ];then

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

else

# Manual recovery
echo "Import SQL Script: $SQL_SCRIPT"

fi

if [ "$dbMajorRev" -eq 11 ] || [ "$dbMajorRev" -eq 12 -a "$dbMinorRev" -eq 2 ] || [ "$dbMajorRev" -ge 18 ]; then
echo "Performing DB RMAN recover."
lastSeqNum=0

# If DB is hot backup or image clone recover is required prior to open
if [ "$ARCHIVELOGMODE" = "true" -o "$BKUPCOPY" -eq 1 ]; then

RMAN_SCRIPT_CATALOG=$(mktemp)
RMAN_SCRIPT_RECOVER=$(mktemp)

if [ "$BKUPCOPY" -eq 1 ]; then
   ARCH_LOG_LOCATION=/opt/oracle/oradata/${ORACLE_SID}/archivelog
else
   ARCH_LOG_LOCATION=/opt/oracle/archivelog
fi

cat <<EOF > $RMAN_SCRIPT_CATALOG
run
{
catalog start with '$ARCH_LOG_LOCATION' noprompt;
}
EOF

if [ "$MANUAL" -eq 0 ];then

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

else

# Manual mode
echo "Skipping archive log catalog, script: $RMAN_SCRIPT_CATALOG"

fi

if [ "$MANUAL" -eq 0 -a "$dbMajorRev" -eq 11 ];then

lastSeqNum=`sqlplus -S / as sysdba <<EOF
set heading off;
set pagesize 0;
set feedback off;
select * from (select trim(sequence#) from v\\$archived_log order by sequence# desc) where rownum=1;
EOF`
lastSeqNum=$(($lastSeqNum+1))

fi

if [ "$hotBackupScn" -ne 0 ]; then
   rmanRecoverOpt="until scn $hotBackupScn"
elif [ "$lastSeqNum" -gt 0 ]; then
   rmanRecoverOpt="until sequence $lastSeqNum"
elif [ "$dbMajorRev" -ne 11 -a "$dbMinorRev" -ne 1 ]; then
   rmanRecoverOpt="until available redo"
else
   rmanRecoverOpt=""
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

else # DB major rev is 12.1
echo "Using DB 12.1 style recover."

RECOVER_SQL_SCRIPT=$(mktemp)

cat <<EOF >$RECOVER_SQL_SCRIPT
recover database using backup controlfile until cancel;
auto
EOF

if [ "$MANUAL" -eq 0 ];then
# Recover database
echo -n "Recovering database ..."
sqlplus -S / as sysdba <<EOF >> $LOGFILE
@$RECOVER_SQL_SCRIPT
EOF

if [ $? -ne 0 ]; then
   echo "Failed. See log for details."
   exit 1
else
   echo "Done."
fi

else # Manual recover

echo "Database recover scriopt: $RECOVER_SQL_SCRIPT"

fi # Auto or manual

fi # DB version

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

fi #### If PDB Incr Merge or Not Main Loop ####

echo -n "Updating oratab ..."
echo "$ORACLE_SID:$ORACLE_HOME:N" >> /etc/oratab
echo "Done."

DATE=$(date '+%m%d%y-%H%M%S')
echo "--> End DB import on $DATE <--" >> $LOGFILE
##
