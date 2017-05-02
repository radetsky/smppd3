#!/usr/bin/perl 
#===============================================================================
#
#         FILE:  smppd3.pm
#
#  DESCRIPTION:  Новый SMPP-сервер на базе Pearl::SMPP::Server на базе AnyEvent.   
#
#        NOTES:  Please read the FM ! 
#       AUTHOR:  Alex Radetsky (Rad), <rad@rad.kiev.ua>
#      COMPANY:  PearlPBX
#      VERSION:  3.0
#      CREATED:  19.07.2014 17:13:03 EEST
#     MODIFIED:  Till the end.   
#===============================================================================
  use 5.8.0; 
	use strict; 
	use warnings; 

  use lib './Pearl-SMPP-Server'; # FIXME 
  use lib './SMPP-Packet/lib';   # FIXME 

# Читая конфигурационный файл от smppd2 я могу сделать следующий вывод: 
# 3. В конфиге первой части надо указать ОДИН на всех путь в БД. 
# 4. set names=utf8 ОБЯЗАТЕЛЬНО! 
# 5. Обязательно все тексты, которые идут внутри submit_sm приводим в utf-8 для хранения в БД 
# или передачи в RabbitMQ. ОБЯЗАТЕЛЬНО! 

	use Pearl::SMPP::Server;
  use AnyEvent; 
  use Data::Dumper; 

  use Proc::Daemon;      # Daemonization
  use Proc::PID::File;   # Managing PID files
  use Getopt::Long qw(:config auto_version auto_help pass_through);
  use Readonly;
  use Config::General;  
  use DBI; 
  use JSON;
  use NetSDS::Util::String; 
  use NetSDS::Util::Convert; 
  use Data::UUID::MT; 
  use POSIX; 
  use Pearl::Util::SMPPConvert; 
  use Encode qw/encode decode encode_utf8 decode_utf8 from_to is_utf8/;
  use Log::Log4perl qw(get_logger :easy); 
  use Log::Log4perl::Appender; 
  use SMPP::Packet; 

  Log::Log4perl->easy_init();

  use constant smppd3_config => './smppd3.conf'; 
  my $connections = undef; 

  # Initialize application 

  my $logger = get_logger();
  
  my $appender = Log::Log4perl::Appender->new ( "Log::Dispatch::File", filename => "/var/log/smppd3.log", mode => ">>" ); 
  my $layout =  Log::Log4perl::Layout::PatternLayout->new("%d %p> %F{1}:%L %M - %m%n");
  $appender->layout($layout);
  $logger->add_appender($appender);  

  my $debug  = getopt(); # Get CLI options --debug  
  $logger->debug("Debug: $debug") if $debug; 

  my $conf = read_config(smppd3_config);
  $logger->debug ("Config: " . Dumper $conf) if $debug; 

  unless ( defined ( $debug )) { my_daemon_procedure(); } 
  pid(); # PID = /var/run/smppd3.pid 
 

  my $dbh = connect_db($conf); 
  my $sql = "insert into messages ( msg_type, esme_id, src_addr, dst_addr, body, short_message, coding, udh, mwi, mclass, message_id, validity, deferred, registered_delivery, service_type, extra, received ) values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,? ) ";
  my $insert_sth = $dbh->prepare_cached($sql);

  my $sql2 = "select id,msg_type,esme_id,src_addr,dst_addr,body,coding,udh,mwi,mclass,validity,deferred,message_id,registered_delivery,service_type,extra from messages where msg_type='MO' or msg_type='DLR' and esme_id = ? order by id limit ?";
  my $get_mo_sth = $dbh->prepare_cached($sql2); 

  my $sql3 = "delete from messages where message_id=?"; 
  my $del_mo_sth = $dbh->prepare_cached($sql3); 

  my $seq = 1; 
  my $seq_message_id = undef;


#  unless ( defined ( $debug ) ) { Proc::Daemon::Init; } # Если не debug, то демон. 

  my $server = Pearl::SMPP::Server->new (  
    debug => $debug, 
    host => $conf->{'host'},
    port => $conf->{'port'},
    on_bound => sub { 
      my ($fh, $host, $port) = @_; 
      $logger->debug("Bound to $host:$port\n") if $debug;  
    }, 

    system_id => $conf->{'system_id'}, 

    authentication => sub { 
      my ( $login, $password, $host, $port ) = @_;
      $logger->debug("Authentication callback with $login, $password, $host, $port") if $debug; 
      return authentication ( $login, $password, $host, $port ); 
    },

    authorization => sub { 
      my ( $host, $port, $source_address ) = @_; 
      $logger->debug("Authorization callback with $host, $port, $source_address") if $debug; 
      return authorization ($host, $port, $source_address);    # return undef if disabled to use $source with $id 
    }, 

    submit_sm  =>  sub { 
      my ( $host, $port, $pdu ) = @_; 
      return handle_submit_sm ($host, $port, $pdu ); # return undef if fail  , return message_id if Ok; 
    }, 

    outbound_q => sub { 
      my ($socket, $host, $port ) = @_; 
      $logger->debug("outbound check with $socket, $host, $port") if $debug;  
      return check_outbound ($socket, $host, $port);       
    },

    handle_deliver_sm_resp => sub { 
      my ($host, $port, $pdu) = @_; 
      return handle_deliver_sm_resp ($host, $port, $pdu); #return undef always 
    }, 

    disconnect => sub { 
      my ($host, $port) = @_; 
      delete $connections->{connection_id($host,$port)};
      $logger->info("Disconnect from $host:$port");
    }

    ); 

    AnyEvent->condvar->recv; 

    exit(0); 

sub my_daemon_procedure { 

 chdir '/'                 or die "Can't chdir to /: $!";
 umask 0;

 open STDIN, '/dev/null'   or die "Can't read /dev/null: $!";
 open STDOUT, '>/dev/null' or die "Can't write to /dev/null: $!";
 open STDERR, '>/dev/null' or die "Can't write to /dev/null: $!";

 my $pid = fork;
 exit if $pid;
 die "Couldn't fork: $!" unless defined($pid);
 POSIX::setsid() or die "Can't start a new session: $!";

}

sub pid {
  if ( Proc::PID::File->running ( dir => '/var/run', name => 'smppd3' ) ) {
    die "Application already running, stop immediately!";
  }
}

sub getopt { 
  # Get command line arguments

  # if debug then not daemonize else daemonize 

  my $debug = undef; 

  GetOptions(
    'debug!'   => \$debug
  ); 

  return $debug; 
}

sub read_config { 

  my $cf = shift; 

  $logger->info("Reading configuration file: $cf"); 

  my $conf = Config::General->new(
      -ConfigFile        => $cf,
      -UTF8              => 'yes'
  );
  # Parse configuration file
  my %cf_hash = $conf->getall;
  return \%cf_hash;
}

sub connect_db { 
  my $conf = shift; 

  my $dbh = DBI->connect_cached ( 
    $conf->{'dsn'}, 
    $conf->{'db-user'},
    $conf->{'db-secret'},
    { RaiseError => 1, AutoCommit => 1, mysql_auto_reconnect => 1 } 
  ); 
  unless ( defined ( $dbh ) ) { 
    $logger->error("Can't connect to ".$conf->{'dsn'} . ": $!"); 
    die "Can't connect to ".$conf->{'dsn'} . ": $!\n"; 
  }


  return $dbh; 
}

sub authentication { 
  my ($login, $password, $host, $port) = @_; 
  $logger->info("Authentication for $host:$port"); 
  # 1. Check login/password 
  # 2. Check ACL 
  my $sth = $dbh->prepare('select esme_id,system_id,bandwidth,allowed_ip,allowed_src,max_connections from auth_table where system_id = ? and password = ? and active = 1');
  eval { 
      $sth->execute( $login, $password );
  }; 
  if ( $@ ) { 
    $logger->error("Can't execute authentication SQL query: $! $@"); 
    die "Can't execute authentication SQL query: $! $@"; 
  }
  if ( my $res = $sth->fetchrow_hashref() ) {
    $connections->{connection_id($host,$port)}->{'authentication'} = $res; 
    $logger->info("$host:$port $login logged in"); 
    return check_acl($login, $password, $host, $port, $res);  
  
  } else { 
    $logger->error("$host:$port $login not authenticated"); 
    return undef; 
  }

  return undef; 
}

sub check_acl { 
  my ($login, $password, $host, $port, $authentication) = @_; 

  unless ( defined( $authentication->{'allowed_ip'} ) ) {
    $logger->info("$login is allowed from NULL"); 
    return $authentication; # because NULL is equal to 0.0.0.0  access from any allowed 
  }
  if ( $authentication->{'allowed_ip'} eq '0.0.0.0') { 
    $logger->info("$login is allowed from 0.0.0.0"); 
    return $authentication; 
  }
  if ( $authentication->{'allowed_ip'} eq $host) { 
    $logger->info("$login is allowed from $host"); 
    return $authentication; 
  }

  $logger->error("$login denied from $host"); 
  return undef; 
}

sub connection_id { 
  my ($host, $port) = @_; 
  return $host . ":" . $port;
} 

sub authorization  { 
  my ($host, $port, $source_address) = @_; 
  my $auth = $connections->{connection_id($host, $port)}->{'authentication'}; 

  unless ( defined ( $auth->{'allowed_src'})) { 
    $logger->info("Allowed from ANY source address because allowed_src is NULL"); 
    return 1; 
  }

  my @allowed_src = split( ',', $auth->{'allowed_src'} );

  foreach my $source (@allowed_src) {
    $source = str_trim($source);
    if ( $source eq $source_address ) {
      $logger->info("Allowed source address $source_address from $host:$port"); 
      return 1;
    }
  }

  $logger->error("Denied $source_address from $host:$port"); 
  return undef;  
}

sub handle_submit_sm { 
  my ($host, $port, $pdu ) = @_; 
  $logger->info("submit_sm from $host:$port ->"); 
  $logger->debug(Dumper $pdu) if $debug;  

  my $date_now = POSIX::strftime( "%Y-%m-%d %H:%M:%S", localtime );    #date_now();

  my $message = {};
  $message->{'udh'} = undef;  

  my $mclass = undef; 
  my $data_coding = $pdu->{data_coding};
  # Check if message_class is present
  if ( ( $data_coding & 0b00010000 ) eq 0b00010000 ) {
    $mclass = $data_coding & 0b00000011;
  }

  # Determine coding
  # Part.1: is this Latin1 (5.2.19 in SMPP v.3.4. spec. 0b00000011)
  my $coding = 0;
  if ( ( $data_coding & 0b00000011 ) eq 0b00000011 ) {
    $coding = 3;    # Latin1 we are save in Database as 0b00000011 
  } else {
    $coding = ( $data_coding & 0b00001100 ) >> 2;
  }
  if ( $coding > 3 ) {
    $logger->error("Unknown data_coding from $host:$port $coding"); 
    return undef; 
  }

  # Determine UDHI state
  my $udhi      = 0;                    # No UDH by default
  my $esm_class = $pdu->{esm_class};    # see 5.2.12 part of SMPP 3.4 spec
  if ( ( $esm_class & 0b01000000 ) eq 0b01000000 ) {
    $udhi = 1;
  }

  # Process SM body (UD and UDH)
  my $msg_text = $pdu->{short_message};

  # If have UDH, get it from message
  my $udh = undef;

  if ($udhi) {
    use bytes;
    my ($udhl) = unpack( "C*", bytes::substr( $msg_text, 0, 1 ) );
    $udh = bytes::substr( $msg_text, 0, $udhl + 1 );
    $msg_text = bytes::substr( $msg_text, $udhl + 1 );
    no bytes;
    $message->{udh} = conv_str_hex($udh); ##### 050003010401 format.
  }

  # Convert text to UTF-8 for readable text 
  $message->{'readable'} = decode( 'utf-8', conv_gsm_utf8 ( $msg_text, $coding ));    # Not byte, only Utf-8.

  $logger->info("from: '". $pdu->{'source_addr'} . "' to: '". $pdu->{'destination_addr'}. "' text: '".$message->{'readable'}."'"); 

  my $uuid = Data::UUID::MT -> new ( version => 4 ); 
  $message->{'message_id'}  = $uuid->create_string();
  $message->{'msg_type'}    = 'MT'; 
  $message->{'esme_id'}     = $connections->{connection_id($host,$port)}->{'authentication'}->{'esme_id'}; 
  $message->{'created'}     = $date_now; 
  $message->{'source_addr'} = $pdu->{'source_addr'}; 
  $message->{'destination_addr'} = $pdu->{'destination_addr'}; 
  $message->{'mclass'}      = $mclass;
  $message->{'data_coding'} = $pdu->{'data_coding'}; 
  $message->{'coding'}      = $coding; ## Human Readable Value. Что бы было удобно читать глазами. 
  $message->{'udhi'}        = $udhi; 
  $message->{'short_message'} = $pdu->{'short_message'}; ###### - Оригинал. Не трогаем ни в коем случае. 
  $message->{'registered_delivery'} = $pdu->{'registered_delivery'}; 
  $message->{'validity_period'} = $pdu->{'validity_period'}; 
  $message->{'source_addr_ton'} = $pdu->{'source_addr_ton'}; 
  $message->{'schedule_delivery_time'} = $pdu->{'schedule_delivery_time'}; 
  $message->{'dest_addr_npi'} = $pdu->{'dest_addr_npi'}; 
  $message->{'dest_addr_ton'} = $pdu->{'dest_addr_ton'}; 
  $message->{'service_type'}  = $pdu->{'service_type'}; 
  $message->{'replace_if_present_flag'} = $pdu->{'replace_if_present_flag'};
  $message->{'priority_flag'} = $pdu->{'priority_flag'}; 
  $message->{'esm_class'} = $pdu->{'esm_class'}; 

  $logger->debug(Dumper $message) if $debug; 

  put_message($message); 

  return $message->{'message_id'}; 

}

sub put_message { 
  my ($mt) = @_; 

  $logger->debug("Put MSG: " . $mt->{'message_id'} ) if $debug; 
  
  my $rv; 

  eval { 
          $rv = $insert_sth->execute(
            $mt->{'msg_type'},
            $mt->{'esme_id'},
            $mt->{'source_addr'},
            $mt->{'destination_addr'},
            $mt->{'readable'},
            conv_str_hex($mt->{'short_message'}), # Оригинальное сообщение конвертируем в HEXSTR и сохраняем в отдельном поле. 
            $mt->{'coding'},
            $mt->{'udh'},
            $mt->{'mwi'},
            $mt->{'esm_class'},
            $mt->{'message_id'},
            $mt->{'validity'},
            $mt->{'dereffed'},
            $mt->{'registered_delivery'},
            $mt->{'service_type'},
            $mt->{'extra'},
            $mt->{'received'},
            ); 
  }; 

  if ( $@ ) { 
	$logger->error("Can't insert into database. $!"); 
  }

  return 1;

}

sub check_outbound { 
  my ($socket, $host, $port ) = @_; 

  my $connection_id = $host . ':' . $port; 
  my $system_id = $connections->{$connection_id}->{'authentication'}->{'system_id'};
  my $esme_id   = $connections->{$connection_id}->{'authentication'}->{'esme_id'};
  my $bandwidth = $connections->{$connection_id}->{'authentication'}->{'bandwidth'};  

  #warn ("smppd3 check outbound: " . $connection_id . ":" . $esme_id . "bandwidth: " . $bandwidth ); 

  return get_msgs ( $esme_id, $bandwidth );

}


sub handle_outbound { 
  # Найти порцию исходящих сообщений ( foreach system_id (bandwidth) )
  # Вернуть hashref $hash_ref -> { $system_id } -> { $msg_id } -> { $PDU } 
  # Server будет отправлять каждому $system_id его PDU.  

  my $outbound = undef; 

  # 1. Смотрим кто в онлайне. 
  foreach my $connection_id ( keys %{ $connections} ) { 
    my $system_id = $connections->{$connection_id}->{'authentication'}->{'system_id'}; 
    my $esme_id   = $connections->{$connection_id}->{'authentication'}->{'esme_id'}; 
    my $bandwidth = $connections->{$connection_id}->{'authentication'}->{'bandwidth'}; 
    $outbound->{$system_id} = get_msgs ( $esme_id, $bandwidth ); 
  } 
  my $i = keys %{ $outbound };  
  $logger->info("Return $i items by outbound handler."); 
  warn Dumper $outbound if $debug;  
  return $outbound; 
}

sub get_msgs { 
  my ( $esme_id, $bandwidth ) = @_; 
  my $msgs = undef; 

  eval { $get_mo_sth->execute( $esme_id, $bandwidth ); }; 
  if ( $@ ) {
    $logger->error("Can't execute GET MO statement: $! $@"); 
    die $!; 
  }
  my $res = $get_mo_sth->fetchall_hashref('id'); 
  #warn Dumper $res; 
  return undef unless ( defined ( keys %{ $res })); 

  foreach my $id ( keys %{ $res }) { 
    my $pdu = convert_mo ( $res->{$id} ); 
    $msgs->{$id} = $pdu; 
  }

  return $msgs; 
}

sub convert_mo { 
  my ($mo1) = @_; 
  my $mo = extra_decode($mo1); 

  my $pdu = undef; 

  $pdu->{source_addr} = $mo->{'src_addr'}; 
  $pdu->{destination_addr} = $mo->{'dst_addr'}; 
  $pdu->{short_message} = short_message ($mo); 
  $pdu->{esm_class} = esm_class($mo); 
  $pdu->{data_coding} = data_coding($mo); 
  $pdu->{receipted_message_id} = receipted_message_id($mo); 
  $pdu->{message_state} = message_state($mo); 
  $pdu->{message_id} = $mo->{'message_id'}; 
  $pdu->{command} = 'deliver_sm'; 
  $pdu->{version} = 0x34; 
  $pdu->{seq} = $seq; $seq_message_id->{$seq} = $mo->{'message_id'}; $seq++; 
  $pdu->{status} = 0; 

#  $logger->info("Converted MO/DLR: ". Dumper $pdu) if $debug;  

  return SMPP::Packet::pack_pdu($pdu); 
}

sub message_state { 
  my ($mo) = @_; 

  return undef unless ( defined ( $mo->{'message_state'})); 
  return $mo->{'message_state'}; 
}

sub receipted_message_id { 
  my ($mo) = @_; 

  return undef unless (defined ( $mo->{'receipted_message_id'})); 
  return $mo->{'receipted_message_id'}; 

}

sub data_coding { 
  my ($mo) = @_; 

  # Set right data_coding field.
  my $data_coding = $mo->{coding};
  if ( $data_coding < 3 ) {
    $data_coding = ( $data_coding << 2 ) & 0b00001100;
  }

  return $data_coding; 
}

sub extra_decode {
  my ( $mo ) = @_;

  my $extra = decode_json( $mo->{'extra'} );
  undef $mo->{'extra'};

  foreach my $parameter ( keys %{ $extra } ) {
    if ( $parameter =~ /message_state/i ) {
      $mo->{$parameter} = pack( "c", $extra->{$parameter} );
      next;
    }
    if ( $parameter =~ /receipted_message_id/i ) {
      $mo->{$parameter} = $extra->{$parameter} . chr(0);
      next;
    }
    $mo->{$parameter} = $extra->{$parameter};
  }
  return $mo;

} ## end sub _extra_decode

sub esm_class { 
  my ($mo) = @_; 

  unless ( defined ( $mo->{'udh'} ) ) { # No UDH in the message 
    return $mo->{'mclass'}; 
  }
  return 0b01000000 & $mo->{'mclass'}; 
}

sub short_message { 
  my ($mo) = @_; 

  unless ( defined ( $mo->{'short_message'} ) ) { 
    return conv_utf8_gsm ( encode ( 'utf-8', $mo->{'body'} ), $mo->{'coding'}); 
  }

  return $mo->{'short_message'}; 
}

sub handle_deliver_sm_resp { 
  my ($host, $port, $pdu) = @_; 

  my $msg_id = $seq_message_id->{$pdu->{'seq'}};
  $logger->info("Deliver_sm_resp for $msg_id. Delete."); 
  delete $seq_message_id->{$pdu->{'seq'}};

  eval { $del_mo_sth->execute($msg_id); }; 
  if ( $@ ) { 
    die "Can't delete with message_id=$msg_id : $!";  
  }

  return undef; 
}
