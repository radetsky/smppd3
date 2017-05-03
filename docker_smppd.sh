#!/bin/bash 
/usr/bin/mysqld_safe &
sleep 5
cd /opt/smppd3 && ./smppd3.pl --debug 


