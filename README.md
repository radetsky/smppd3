smppd3
======

Based Pearl::SMPP::Server new release of our SMPP Server. 
It's a simple SMPP (SMSC) -> MySQL gateway.  

http://www.netstyle.com.ua/solutions/smpp-server 

It solves the task of receiving short messages via SMPP and translation in a simple database structure. 


DATABASE PREPARING
==================

$ mysql -u root -p
> create database mydb;
> use mydb;
> source scheme.sql

Grant all privileges on new database to some user.

CONFIGURATION FILES
===================
[rad@rad smppd3]$ cat smppd3.conf
host=0.0.0.0
port=9900
system_id=PearlSMPP
dsn=DBI:mysql:database=pearlsms;host=localhost
db-user=pearlsms
db-secret=pearlsms

