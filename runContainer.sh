docker run --privileged -d --name oradb11 \
	-p 1521:1521 -p 5500:5500 \
	-e ORACLE_SID=oradb \
	-e ORACLE_PWD=password \
	-e ORACLE_EDITION=EE \
	-e ORACLE_CHARACTERSET=AL32UTF8 \
	-v /opt/oracle/oradata \
	--volume-driver netapp \
	oracle/database:11.2.0.4-ee
