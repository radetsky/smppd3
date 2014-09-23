--
-- Table structure for table `auth_table`
--

DROP TABLE IF EXISTS `auth_table`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `auth_table` (
  `esme_id` int(11) NOT NULL auto_increment,
  `system_id` varchar(45) default NULL,
  `password` varchar(45) default NULL,
  `bandwidth` int(11) default NULL,
  `allowed_ip` varchar(256) default NULL,
  `allowed_src` varchar(256) default NULL,
  `max_connections` int(11) default NULL,
  `active` tinyint(1) default NULL,
  PRIMARY KEY  (`esme_id`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8 COMMENT='Table  for authorization of ESME''s';
SET character_set_client = @saved_cs_client;

--
-- Dumping data for table `auth_table`
--

LOCK TABLES `auth_table` WRITE;
/*!40000 ALTER TABLE `auth_table` DISABLE KEYS */;
INSERT INTO `auth_table` VALUES (1,'SMSGW','secret',1,'127.0.0.1','smppsvrtst.pl',NULL,1),(2,'test1000','secret1000',1000,NULL,NULL,1000,1);
/*!40000 ALTER TABLE `auth_table` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `messages`
--

DROP TABLE IF EXISTS `messages`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `messages` (
  `id` int(11) NOT NULL auto_increment,
  `msg_type` varchar(3) default NULL,
  `esme_id` int(11) default NULL,
  `received` timestamp NOT NULL default '0000-00-00 00:00:00',
  `processed` timestamp NOT NULL default CURRENT_TIMESTAMP,
  `src_addr` varchar(32) default NULL,
  `dst_addr` varchar(32) default NULL,
  `body` text default NULL,
  `short_message` text default NULL,
  `coding` int(11) default '0',
  `udh` varchar(512) default NULL,
  `mwi` int(11) default NULL,
  `mclass` int(11) default NULL,
  `message_id` varchar(64) default NULL,
  `validity` int(11) default '1440',
  `deferred` int(11) default '0',
  `registered_delivery` int(11) default '0',
  `service_type` varchar(64) default NULL,
  `extra` varchar(512) default NULL,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=67236 DEFAULT CHARSET=utf8;
SET character_set_client = @saved_cs_client;

--
-- Dumping data for table `messages`
--

LOCK TABLES `messages` WRITE;
UNLOCK TABLES;

create table delivery_requests ( 
	message_id varchar(64) NOT NULL, 
	expire timestamp NOT NULL default now()
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

create index m1 on messages (id);
create index m2 on messages (msg_type);
create index m3 on messages (esme_id);
create index m4 on messages (message_id);

