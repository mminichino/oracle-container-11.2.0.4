#!/bin/bash
# LICENSE UPL 1.0
#
# Copyright (c) 1982-2016 Oracle and/or its affiliates. All rights reserved.
#
# Since: December, 2016
# Author: gerald.venzl@oracle.com
# Description: Sets up the unix environment for DB installation.
# 
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
# 

# Setup filesystem and oracle user
# Adjust file permissions, go to /opt/oracle as user 'oracle' to proceed with Oracle installation
# ------------------------------------------------------------
case $DB_INSTALL_VERSION in
  "11.2.0.4")
    DB_INSTALL_PKG="oracle-rdbms-server-11gR2-preinstall"
    ;;
  "12.1.0.2")
    DB_INSTALL_PKG="oracle-rdbms-server-12cR1-preinstall"
    ;;
  "12.2.0.1")
    DB_INSTALL_PKG="oracle-database-server-12cR2-preinstall"
    ;;
  "18.3.0")
    DB_INSTALL_PKG="oracle-database-preinstall-18c"
    ;;
  "19.3.0")
    DB_INSTALL_PKG="oracle-database-preinstall-19c"
    ;;
  *)
    DB_INSTALL_PKG="oracle-rdbms-server-11gR2-preinstall"
    ;;
esac
mkdir -p $ORACLE_BASE/scripts/setup && \
mkdir $ORACLE_BASE/scripts/startup && \
ln -s $ORACLE_BASE/scripts /docker-entrypoint-initdb.d && \
mkdir $ORACLE_BASE/oradata && \
mkdir -p $ORACLE_HOME && \
chmod ug+x $ORACLE_BASE/*.sh && \
yum -y install $DB_INSTALL_PKG tar openssl vim-enhanced net-tools git sudo wget && \
echo "%dba ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
rm -rf /var/cache/yum && \
ln -s $ORACLE_BASE/$PWD_FILE /home/oracle/ && \
echo oracle:oracle | chpasswd && \
chown -R oracle:dba $ORACLE_BASE
