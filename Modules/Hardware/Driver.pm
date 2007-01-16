#
# HARDWARE.PM - Hardware abstraction layer for the various 
#  incarnations of the extended analog computer.
#
#
# Copyright (C) 2005 Ryan R. Varick <rvarick@indiana.edu>
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of
# the License, or (at your option) any later version.
#
#
# DESCRIPTION:
#
#  Abstraction diagram:
#
#   LEVEL   FUNCTION NAME                     LAYER INFORMATION
#   =====   =============                     =================
#
#    (5)    reset_board                       some useful meta functions
#    (5)    get_gradient
#    (5)    report_lla
#    (5)    report_chain
#
#    (4)    read_voltage, write_source        command abstraction layer
#    (4)    read_lla_input, write_sink
#    (4)    read_lla_output, write_lla [*]
#
#    (3)    read_dac, write_dac               basic hardware command layer
#
#    (2)    init_hardware
#    (2)    write_command                     hardware communication layer
#
#    (1)    open/close_socket, 
#           open/close_serial port            communication channel layer
#

package Driver;

use diagnostics;
use strict;
use warnings;

use Modules::Hardware::eac;
use Modules::Hardware::ueac;
use Modules::Hardware::simulator;



# ====================[ CONFIGURATION ]====================

use constant TRUE  => (1 == 1);
use constant FALSE => (0 == 1);
use constant NULL  => -1;

our $VERSION       =  '3.0.0';
our $DEBUG_ON      =  TRUE;

# driver status codes
our $OK    = 0;
our $ERROR = 1;
our $NA    = 2;



# --------------------[ Driver mode ]---------------------

#
# NOTE: For each of these, there is a variable declaration
#       and a few constants.  The declarations are controlled
#       by the init() methods, while the constants are used
#       externally as references.
#
#       Generally, since everything is declared 'our', all
#       variables are externally accessible.  Good OO practice
#       would wrap each variable in get/set methods.  For the
#       toolkit, other modules are assumed to behave.  That is,
#       the get method is simply a $Driver::{$variable} call, 
#       while chaning the value is done only when necessary.
#
# TODO (v3.1): use the exporter to define access better.
#

# valid driver modes (these should map to driver module names)
our $EAC_DRIVER            = 'eac';
our $UEAC_DRIVER           = 'ueac';
our $EAC_SIMULATOR_DRIVER  = 'eac-simulator';
our $UEAC_SIMULATOR_DRIVER = 'ueac-simulator';
our $NULL_DRIVER           = 'null';

# simulators share a common driver
our $SIMULATOR_DRIVER = 'simulator';

# list of valid driver modes (provided for convenience)
our @driver_list = 
    (

     $Driver::EAC_DRIVER,
#     $Driver::UEAC_DRIVER,
     $Driver::EAC_SIMULATOR_DRIVER,
     $Driver::UEAC_SIMULATOR_DRIVER,
     $Driver::NULL_DRIVER,

    );

# current driver mode (controlled by init_driver)
our $driver;

# is the driver connected to an EAC?
my $DRIVER_CONNECTED = FALSE;

# --------------------[ Device information ]--------------------

# whether to use connect/disconnect (disabled for the simulator)
our $attempt_device_connection;

# prededfined devices
our $NULL_EAC      = 'null';
our $SIMULATED_EAC = 'simulator';

# active eac (controlled by init_driver)
our $eac;

# list of valid EACs (controlled by each driver's connect method)
our @eac_list;

#
# hardware layout - the EAC and the uEAC have very different
#  properties.  The EAC has a number of fixed source, sink,
#  and LLA channels, while the uEAC is fully configurable.  The
#  GA needs to know how each device works to operate properly.
#
our $FIXED_LAYOUT = 'fixed';            # position-dependent
our $FREE_LAYOUT  = 'free';             # position-independent

# layout of the current eac (controlled by the active driver)
our $hardware_layout;

# TODO: set these on hardware init
our $current_precision_mask = "%2.2f";
our $min_current            =   0.0;  # reference min_foam_current, etc.
our $max_current            = 200.0;
our $min_lla_function       =   1;
our $max_lla_function       =  27;

our $unit;

# we want to cache driver settings to restrict driver calls
#  as much as possible
#our $hardware_layout;
#our $genome_length;

# default eac configuration stuff (TODO)
#  used by get_connection_type (move to Driver??)
our $max_sources = 8;
our $max_sinks   = 8;
our $max_llas    = 6;

# default ueac configuration stuff (TODO)
# our $num_rows = 5;
# our $num_cols = 5;

# length of the genome (set by the driver, read by the GA)
our $genome_length;

# ==================== END CONFIGURATION ====================







#
# CALL_DRIVER - Call the specific driver implementation of the
#  calling method.  'Driver' provides the generic driver framework;
#  the 
#
#  args:    <variable> (passed blindly)
#  returns: driver return value (passed blindly)
#
#  NOTE: This routine constructs a subroutine call using
#        the current driver and the caller's subroutine name.
#
sub call_driver
{
    # get the subroutine name and construct the driver call
    my $subroutine  = Toolkit::get_subroutine(1);
    my @routine     = split('::', $subroutine);
    my $driver_call = $driver . '::' . $routine[1];

    # For the null driver, skip the hardware call
    if($driver eq $Driver::NULL_DRIVER)
    {
	Toolkit->printd("Null driver enabled, skipping hardware call to $routine[1]().\n");
	return $Driver::OK;
    }
    else
    {
	Toolkit::printd("Calling $driver_call(@_)...\n");

	JUMP:
	  {
	      no strict 'refs';
	      return &{$driver_call}(@_);
	  }
    }
}







# --------------------[ API calls ]---------------------

#
# implementing reset should be driver-specific, not meta, because here it is
#  just re-initing the arrays
#


#
# NOTE: Each driver subclass should implement these functions.
#

sub reset { Driver::call_driver(); }

sub read_source { Driver::call_driver(@_); }
sub read_sink { }
sub read_lla { }

sub write_source { Driver::call_driver(@_); }
sub write_sink { }

# fixme:
#
# LLA = LLA_IN, LLA_SRC_OUT (+source = LLA_OUT_VAL)
#               LLA_SNK_OUT (-sink = LLA_OUT_VAL)
#
#
sub write_lla_in { }

# sub write_configuration { }

#
# CONNECT/DISCONNECT - Initiate or terminate communication with
#  EAC hardware devices.
#
#  args:    eac
#  returns: status code
#
sub connect_to_device($)
{
    my $eac = $_[0];

    # check for existing connections
    if($DRIVER_CONNECTED eq TRUE)
    {
	Toolkit::printd("Disconnecting existing EAC '$Driver::eac'...\n");
	Driver::disconnect_from_device();
    }

    # connect to the new EAC
    my $status = Driver::call_driver($eac);

    # log and report the connection status
    if($status eq $Driver::OK)
    {
	$Driver::eac      = $eac;
	$DRIVER_CONNECTED = TRUE;

	Toolkit::printd("Successfully connected to '$eac'.\n");
	return $Driver::OK;
    }
    elsif($status eq $Driver::NA)
    {
	return $Driver::NA;
    }
    else
    {
	Toolkit::printd("Connection to '$eac' failed with status=$status\n");
	return $Driver::ERROR;
    }
}

# responsible for clearing DRIVER_CONNECTED
sub disconnect_from_device() 
{
    if($DRIVER_CONNECTED eq FALSE)
    {
	Toolkit::printd("Not currently connected to an EAC.\n");
	return $Driver::NA;
    }
    else 
    {
	my $status = Driver::call_driver();

	if($status eq $Driver::OK)
	{
	    Toolkit::printd("Successfully disconnected from '$Driver::eac'.\n");

	    $Driver::eac      = $Driver::NULL_EAC;
	    $DRIVER_CONNECTED = FALSE;
	    
	    return $Driver::OK;
	}
	elsif($status eq $Driver::NA)
	{
	    # Do nothing
	}
	else
	{
	    Toolkit::printd("Disconnect from '$eac' failed with status=$status\n");
	    return $Driver::ERROR;
	}
    }
}



#
# INIT_DRIVER - Responsible for starting driver bookkeeping 
#  and calling the actual driver initializer.
#
#  args:    driver mode
#  returns: initialization status
#
sub init_driver($)
{
    my $new_driver = $_[0];

    # verify the driver mode
    my $valid_driver = FALSE;
    foreach my $d(@Driver::driver_list)
    {
	if($new_driver eq $d) { $valid_driver = TRUE; }
    }
    unless($valid_driver eq TRUE)
    {
	Toolkit::crash('E_UNKNOWN_DRIVER_MODE', $new_driver);
    }

    # check for and disconnect from existing EACs
    if($DRIVER_CONNECTED eq TRUE)
    {
	Driver::disconnect_from_device();
	# FIXME: reset all variables here
    }

    # initialize the driver interface (check for simulator modes)
    if($new_driver eq $Driver::EAC_SIMULATOR_DRIVER ||
       $new_driver eq $Driver::UEAC_SIMULATOR_DRIVER)
    {
	Toolkit::printd("Simulator detected, using common driver.\n");
	$Driver::driver = $Driver::SIMULATOR_DRIVER;
    }
    else
    {
	$Driver::driver = $new_driver;
    }

    # call with the *requested* driver in case we're dealing with a simulator
    Toolkit::printd("Initializing driver '$Driver::driver'...\n");
    return Driver::call_driver($new_driver);
}

return TRUE;
