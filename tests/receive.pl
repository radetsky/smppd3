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

# Test No. 1: TCP Connect to pearlsms-demo.pearlpbx.com : 2775.
my $cli = Net::SMPP->new_connect( 'pearlsms-demo.pearlpbx.com', port => 2775, smpp_version => 0x34, async => 1 );
if ($cli) {
	print "ok 1: connect to '127.0.0.1:2775:ver 3.4:async\n";
} else {
	die "fail 1: failed connect to 127.0.0.1:2775 : $!\n";
}

my $seq = undef; 
my $pdu = undef; 

$cli = Net::SMPP->new_connect( 'pearlsms-demo.pearlpbx.com', port => 2775, smpp_version => 0x34, async => 1 ) or die;
$seq = $cli->bind_transceiver( system_id => 'rad', password => 'KillThem' ) or die;
$pdu = $cli->read_pdu() or die;
if ( $pdu->{status} == 0x00 ) {          ## STATUS
	print "ok 3 : correct answer for system_id->'SMSGW',password->'secret'. \n";
} else {
	die "fail 3: PDU->status must have 0x00 value. \n";
}

while (1) { 
	$pdu = $cli->read_pdu() or die; 
	warn Dumper $pdu; 
	if ( $pdu->{'cmd'} == 21 ) { 
		print "Keep alive packet.\n"; 
		$cli->enquire_link_resp(seq => $pdu->{'seq'});
	} else {
		$cli->deliver_sm_resp(message_id => $pdu->{'receipted_message_id'}, seq => $pdu->{'seq'}); 
	}
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

