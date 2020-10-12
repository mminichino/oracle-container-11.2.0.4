# oracle-container-automation
Create a Container with a Database

This is a docker toolset to create containers that will run either a new Oracle Database instance, import a snapshot of a running instance (in hot backup mode), or create a new instnace from a backup copy. It is based on the Oracle docker-images-master project, which is provided under UPL, therefore this is provided under UPL. This is only a reference sample. It is provided for informational and self-help purposes only. This is provided in good faith, however there is no representation or warranty of any kind, express or implied, regarding the accuracy, adequacy, validity, reliability, availability or completeness of anything contained herein. Under no circumstance shall there be any liability to you for any loss or damage of any kind incurred as a result of the use of these utilities.

It has been tested with Database versions 11.2.0.4, 12.1.0.2, 12.2.0.1, 18c and 19c.

The host must have docker installed along with nfs-utils. To run docker as the oracle user, make sure the oracle user is a member of the docker group.

Combine this with [oracle-scripts](https://github.com/mminichino/oracle-scripts) and with the ontap_refresh_clone_oracle_db and ontap_incr_merge_clone playbooks from [ansible-playbooks](https://github.com/mminichino/ansible-playbooks) to create a simple DevOps solution for creating quick database copies for test and development purposes.

To build the image, you must have access to the installation media. For 11.2.0.4 it expects zip files 1 and 2 (of 7) of the patch 13390677 release. Otherwise it accepts the distribution files as downloaded. It will install Enterprise Edition. Copy the installation file(s) to the package directory, and then build the docker image:

````
$ ./buildDockerImage.sh -v 19.3.0
````

To run a container with a new instance, install NetApp Trident so that docker will automaticaly provision a new volume for the new database. Note the password complexity requirements for 12.2 and higher.

````
$ ./runContainer.sh -v 19.3.0 -s test01 -p 'Password0!'
````

To run a database clone from a snapshot of a database, the database must have its database files on a single NFS share, and its archive logs on another NFS share. Both shares must be mounted to the docker host.

````
$ ./runContainerImport.sh -s test01 -d /oradb/data -l /oradb/arch -p 'Password0!' -v 19.3.0
$ docker logs -f test01
````

To run a database clone from a backup copy, the backup must be available to be mounted in the container (in RMAN COPY format, not RMAN BACKUPSET format). Do not use a backup that may be needed for a restore. Instead use a snapshot copy or a secondary backup copy.

````
$ ./runContainerImage.sh -d /oradb/backup -v 19.3.0 -s test01 -p 'Password0!'
$ docker logs -f test01
````

To stop a container:

````
$ docker stop test01
````

To restart the container:
````
$ docker start test01
````
