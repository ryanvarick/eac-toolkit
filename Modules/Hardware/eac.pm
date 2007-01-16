#
# EAC.PM - Driver for the Ethernet-based extended analog computer.
#
#
# Copyright (C) 2006 Ryan R. Varick <toolkit@indiana.edu>
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of
# the License, or (at your option) any later version.
#
#

package eac;

use diagnostics;
use strict;
use warnings;

# network connectivity
use Socket;



# ====================[ CONFIGURATION ]====================

use constant TRUE  => (1 == 1);
use constant FALSE => (0 == 1);
use constant NULL  => -1;

our $VERSION       =  '2.0.0';
our $DEBUG_ON      =  TRUE;

# network options
my $EAC_PORT        = 17000;
my $EAC_SOCKET_OPEN = FALSE;                    # state of the socket connection

# valid EACs
use constant EAC1  =>  'eac1.cs.indiana.edu';
use constant EAC2  =>  'eac2.cs.indiana.edu';
use constant EAC3  =>  'eac3.cs.indiana.edu';
use constant EAC4  =>  'eac4.cs.indiana.edu';

my @EAC_LIST = 
    (
       EAC1,
       EAC2,
       EAC3,
       EAC4,
    );

# ====================[ END CONFIGURATION ]===================







#

sub init_driver($)
{

    $Driver::hardware_layout = $Driver::FIXED_LAYOUT;

    $Driver::attempt_device_connection = TRUE;
    @Driver::eac_list = @EAC_LIST;


    # FIXME: this should use vars
    $Driver::genome_length   = 8 + 8 + 6;

    return $Driver::OK;
}

sub connect_to_device($)
{
    my $eac = $_[0];

    # TODO: validate
    $Driver::eac = $eac;

    eac::open_socket();
    return $Driver::OK;
}

sub disconnect_from_device()
{
    eac::close_socket();
    return $Driver::OK;
}




#
# NOTE: 
#
#  This is the base abstraction layer, responsible for minding 
#  direct communication with the EAC.
#
#  In general, an EAC command looks like this: CccddddZ, where:
#
#      C = Command 
#     cc = channel
#   dddd = data (ddd for the EAC, dddd for the uEAC)
#      Z = terminator
#
#  A successfully exectuted command will be echoed back over the
#  communication channel.  A malformed or otherwise unsucessful
#  command will return FxxxxxxZ.
#
#  TODO: Finish this:
#
#  DccdddZ - eac write dac
#  P/M     - ueac source, sink
#  A       - eac lla report (general v1 report)
#  LCCDDDZ = L   -> LLA command message
#          = CC  -> 2 hex digits of channel number
#                   0-5 lla channel
#          = DDD -> 3 hex digits of data value 0-26
#  FxxxxxZ = bad command data










# --------------------[ EAC communication layer (1) ]--------------------

#
# OPEN_SOCKET - Maintains a network socket connection to the EAC.
#
#  args:    none
#  returns: nothing
#
sub open_socket() 
{

    if($EAC_SOCKET_OPEN eq FALSE) 
    {
	# set up
	my $port  = $EAC_PORT;
	my $iaddr = inet_aton("$Driver::eac") or 
	    Toolkit::crash('E_NETWORK_ERROR', "No host error: $Driver::eac");
	my $paddr = sockaddr_in($port, $iaddr);
	my $proto = getprotobyname("tcp");

	# connect
	socket(S, PF_INET, SOCK_STREAM, $proto) or 
	    Toolkit::crash('E_NETWORK_ERROR', "Socket error: $!");
	connect(S, $paddr) or 
	    Toolkit::crash('E_NETWORK_ERROR', "Connection error: $!");

	# set autoflushing
	select(S); 
	$|=1; 
	select(STDOUT);

	$EAC_SOCKET_OPEN = TRUE;
	Toolkit::printd("Socket connection opened.\n");
    }
    else 
    {
	Toolkit::printd("Socket connection already open.\n");
    }
}

#
# CLOSE_SOCKET - Closes the active socket cleanly, if one exists.
#
#  args:    none
#  returns: nothing
#
sub close_socket() 
{
    if($EAC_SOCKET_OPEN eq TRUE) 
    {
	close S;
	$EAC_SOCKET_OPEN = FALSE;
	Toolkit::printd("Socket connection closed.\n");
    }
    else 
    {
	Toolkit::printd("There is no socket to close.\n");
    }
}

return TRUE;
