smppd3
======

Based Pearl::SMPP::Server new release of our SMPP Server.
It's a simple SMPP (SMSC) -> MySQL gateway.

It solves the task of receiving short messages via SMPP and translation in a simple database structure.


DATABASE PREPARING
==================
```
 $ mysql -u root -p
 > create database pearlsms;
 > use pearlsms;
 > source scheme.sql;
 > create user 'smppd3'@'localhost' identified by 'superpassword';
 > grant all on pearlsms.\* to 'smppd3'@'localhost';
 > flush privileges;
```

CONFIGURATION FILES
===================
```
[rad@rad smppd3]$ cat smppd3.conf
host=0.0.0.0
port=9900
system_id=PearlSMPP
dsn=DBI:mysql:database=pearlsms;host=localhost
db-user=pearlsms
db-secret=pearlsms
```
run
===

```cd <where smppd3.conf located>
smppd3
```
or smppd3 --debug for verbose and debug mode

Logfile: /var/log/smppd3.conf
PID: /var/run/smppd3.pid

stop
====

```
kill -TERM `cat /var/run/smppd3.conf`
```

ALSO read SQLAPI.txt
