# oracle-container-11.2.0.4
Create a Container with an 11gR2 Database

This is a docker toolset to create containers that will run either a new Oracle Database 11.2.0.4 instance, or import a snapshot of a running 11.2.0.4 instance (in hot backup mode). It is based on the Oracle docker-images-master project, which is provided under UPL, therefore this is provided under UPL. This is only a reference sample. It is provided for informational and self-help purposes only. This is provided in good faith, however there is no representation or warranty of any kind, express or implied, regarding the accuracy, adequacy, validity, reliability, availability or completeness of anything contained herein. Under no circumstance shall there be any liability to you for any loss or damage of any kind incurred as a result of the use of these utilities.

The host must have docker installed along with nfs-utils. To run docker as the oracle user, make sure the oracle user is a member of the docker group.

To build the image, you must have access to the 11.2.0.4 media. It expects zip files 1 and 2 (of 7) of the 11.2.0.4 patch 13390677 release. It will install 11gR2 Enterprise Edition. Copy the two zip files to the package directory, and then build the docker image:

````
$ ./buildDockerImage.sh
````

To run a container with a new instance, install NetApp Trident so that docker will automaticaly provision a new volume for the new database.

````
$ ./runContainer.sh
````

To run a database copy from a snapshot of a database, the database must have its database files on a single NFS share, and its archive logs on another NFS share. Both shares must be mounted to the docker host.

````
$ ./runContainerImport.sh -s oradb -d /oradb/oradata -l /oradb/archivelog -p password
$ docker logs -f oradb11
````

To stop a container:

````
$ docker stop oradb11
````

To restart the container:
````
$ docker start oradb11
````
