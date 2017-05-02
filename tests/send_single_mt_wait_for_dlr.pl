#!/usr/bin/env perl 
#===============================================================================
#
#         FILE:  smppsvrtst.pl
#
#        USAGE:  ./smppsvrtst.pl
#
#  DESCRIPTION:  Test cases for smppserver v 2.x
#
#      OPTIONS:  ---
# REQUIREMENTS:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Alex Radetsky (Rad), <rad@rad.kiev.ua>
#      COMPANY:  Net.Style
#      VERSION:  1.0
#      CREATED:  29.08.10 20:56:45 EEST
#     REVISION:  ---
#===============================================================================

use 5.8.0;
use strict;
use warnings;

use Data::Dumper;
use Net::SMPP;
use Time::HiRes qw(gettimeofday tv_interval);

use DBI;

use NetSDS::Util::Convert;
use NetSDS::Util::String; 

unless ( ( defined ($ARGV[0] ) ) or ( defined ( $ARGV[1] ) ) ) {
	warn "Usage: <coding(0-2)> <Text>";
	exit -1;
}

my $coding=$ARGV[0]; 
my $text = $ARGV[1];
my $serverName = $ARGV[2];
my $smsCount = $ARGV[3]; 

my $demo   = { host => 'pearlsms-demo.pearlpbx.com', systemid => 'rad', secret => 'KillThem' }; 
my $pharos = { host => 'bulk.pharos.com.ua', systemid => 'pantera', secret => '38050316' }; 
my $server = { demo => $demo, pharos => $pharos}; 

my $seq = undef; 
my $pdu = undef; 

my $cli = Net::SMPP->new_connect( $server->{$serverName}->{host} , port => 2775, smpp_version => 0x34, async => 1 ) or die;
$seq = $cli->bind_transceiver( system_id => $server->{$serverName}->{systemid}, password => $server->{$serverName}->{secret} ) or die;
$pdu = $cli->read_pdu() or die;
if ( $pdu->{status} == 0x00 ) {          ## STATUS
	print "ok 3 : correct answer for system_id->".$server->{$serverName}->{systemid}.",password->".$server->{$serverName}->{secret}.". \n";
} else {
	print "fail 3: PDU->status must have 0x00 value. \n";
}

if ($coding == 2) { 
	$text = str_recode ($text, 'utf8', 'ucs2-be'); 
} 
if ($coding == 0) { 
	$text = str_recode ($text, 'utf8', 'gsm0338');
} 


# Test No. 4: Send SM
$seq = $cli->submit_sm( 'data_coding' => ( $coding << 2 )  , 'registered_delivery' => 1, 'source_addr' => 'TaxiPantera', 'destination_addr' => '380504139380', short_message => $text ) or die;
$pdu = $cli->read_pdu() or die;
if ( $pdu->{status} == 0x00 ) {          ## STATUS
	print "ok 4: SM accepted.\n";
} else {
	die "fail 4: single message was not acccepted. PDU->status must be 0x00. \n";
}

if ( defined ( $smsCount ) ) { 
	for (my $i = 0; $i < $smsCount; $i++ ) { 
		$seq = $cli->submit_sm( 'data_coding' => ( $coding << 2 )  , 'registered_delivery' => 1, 'source_addr' => 'Pharos', 'destination_addr' => '380504139380', short_message => $text ) or die;
		$pdu = $cli->read_pdu() or die;
	}
}

while(1) { 
	$pdu = $cli->read_pdu() or die; 
	warn Dumper $pdu; 
	$cli->deliver_sm_resp(seq => $pdu->{'seq'},message_id => '' ); 
}
$cli->unbind();


#EOF

1;
#===============================================================================

__END__

=head1 NAME

smppsvrtst.pl

=head1 SYNOPSIS

smppsvrtst.pl

=head1 DESCRIPTION

FIXME

=head1 EXAMPLES

FIXME

=head1 BUGS

Unknown.

=head1 TODO

Empty.

=head1 AUTHOR

Alex Radetsky <rad@rad.kiev.ua>

=cut

