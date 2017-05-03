#!/bin/bash 
/usr/bin/mysqld_safe &
sleep 5
/usr/bin/mysql -u root < createdb.sql 
/usr/bin/mysql -u root smpp < scheme.sql 


