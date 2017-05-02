CREATE DATABASE smpp;
CREATE USER 'smpp'@'localhost' identified by 'smpp234';
GRANT ALL on smpp.* to 'smpp'@'localhost';
FLUSH PRIVILEGES;

