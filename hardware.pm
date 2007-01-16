#
# HARDWARE.PM - Abstraction layer for the EAC/uEAC.
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


#
# TODO: Finish modularizing this module
# TODO: Recomment this module
# TODO: Finish v2 support
#

require 'config.pm';

require 5.002;
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw
    /
     &get_gradient,
     &report_lla,
     &reset_board,

     &read_voltage,
     &read_lla_input,
     &read_lla_output,
     &write_source,
     &write_sink,
     &write_lla,

     &read_dac,
     &write_dac,

     &init_hardware,
     &write_command,

     &open_socket,
     &close_socket,
     &open_serial_port,
     &close_serial_port
    /;



# ========== EAC COMMAND LANGUAGE ABSTRACTION LAYER ==========

#
# NOTE: These functions sit atop the low-level communication 
#  routines They are meant as an abstraction away from the 
#  details of any one particular EAC architecture, and are 
#  hopefully a more intuitive way of approaching EAC designs.
#
#  The read_* functions return properly formatted values for 
#  the active EAC.  The write_* functions return the result
#  of the requested operation.
#
#  Originally, these functions supported ranges; however it
#  does not really make sense to support that here.  Each of
#  these functions returns a value that could be used by the
#  calling procedure -- the output for the read_* functions,
#  and a response code for the write_* functions.  Range
#  support would at this level would make it difficult to
#  return values, or require decisions about what to do with
#  the values to be made at this level.
#
#  read_voltage    (index) - Reads the voltage at a channel
#  read_lla_input  (index) - Reads the current on an LLA_IN channel
#  read_lla_output (index) - Reads the current on an LLA_OUT channel
#
#  write_source (index, current) - Writes current to a source
#  write_sink   (index, current) - Writes current to a sink
#
#  write_lla - <special case>
#



# =============== META LAYER (5) ===============

#
# GET_GRADIENT - Returns a print-formatted string of the
#  voltage gradient on the sheet.
#
#  args: none
#
sub get_gradient() {
    my $result = '';
    my @accumulator;

    # Report hardware v1
    if($HARDWARE eq $EACV1) {

	# Intialize the accumulator (for multiple samples)
	for(my $i = 0; $i < 56; $i++) {
	    $accumulator[$i] = 0;
	}

	# Sample the voltage gradient n times
	for(my $i = 0; $i < $num_report_samples; $i++) {
	    for(my $j = 0; $j < 56; $j++) {
		my $value = &read_voltage($j);
		$accumulator[$j] += $value;
	    }
	}

	# Average and format
	my $row = 0;
	my $col = 0;
	my $avg = 0;
	my $print_row = '';

	for(my $i = 0; $i < 56; $i++) {
	    $avg = $accumulator[$i] / $num_report_samples;

	    # We only save the first seven rows, the last
	    #  couple of rows are ignored for some reason
	    if($row < 7) {
		$print_row = $avg . "\t" . $print_row;
	    
		if($col eq 4) {
		    $result .= "$print_row\n";
		    $print_row = '';
		    $col = 0;
		    $row++;
		}
		else { $col++; }
	    }
	}
    }

    # Report hardware v2
    elsif($HARDWARE eq $EACV2) {

	my $response = &write_command("RVZ");
	return $response;

    }

    return $result;
}

#
# REPORT_LLA - Report the values on one or more LLAs.
#
#  args: index_1, index_2
#
sub report_lla {
    my $lower   = $_[0];
    my $upper   = $_[1];

    my $result  = '';
    my $input, $output;

    # Read each of the LLAs in the specified range
    #  TODO: Check the return values for command errors
    for(my $i = $lower; $i <= $upper; $i++) {
	$input  = &read_lla_input($i);
	$output = &read_lla_output($i);
	$result .= "Current on LLA " . ($i + $feedback_adjustment) .
	    " is $input $current_unit IN, $output $current_unit OUT.\n";
    }

    return $result;
}

#
#
#
sub report_chain() {
    my $lla_1 = $_[0];
    my $lla_2 = $_[1];

    my $input  = &read_lla_input($lla_1);
    my $output = &read_lla_input($lla_2);

    # Since we're done with lla_1/2, we can destructively
    #  mutate them for printing's sake
    $lla_1 += $feedback_adjustment;
    $lla_2 += $feedback_adjustment;

    return 
	"Chained current reading on LLA pair ($lla_1,$lla_2)" .
	" is $input $current_unit IN, $output $current_unit OUT.\n";
}

#
# RESET_BOARD - Resets all connections on the sheet.
#
#  args: none
#
# NOTE on LLAs: The LLAs on the EAC (hardware v1) are permanent
#  and unchangable by software once attached to the sheet.  They
#  cannot be 'reset'.  The LLAs on the uEAC (hardware v2) are,
#  however, maintained in software and thus removed when all the
#  points are reset.
#
sub reset_board() {
    my $positions;

    # Find the number of connections to reset
    if($HARDWARE eq $EACV1) { $positions = ($num_sources - 1); }
    elsif($HARDWARE eq $EACV2) { $positions = $max_position; }
    else {
	&crash("reset_board(): Unsupported hardware mode recieved ($HARDWARE).\n");
    }

    # Reset each connection
    #  TODO: Check the return values for command errors
    for(my $i = 0; $i <= $positions; $i++) {
	&write_source($i, $min_current);
	&write_sink  ($i, $min_current);
    }
    
    return "EAC at \'$eac\' reset.\n";
}






# =============== EAC/uEAC BASIC FUNCTIONS ===============

#
# READ_VOLTAGE - Returns the voltage reported at the specified channel.
#
#  args: index
#
sub read_voltage() {
    my $index = $_[0];
    my $raw, $result;

    if($HARDWARE eq $EACV1) {
	$raw    = &read_dac($index);
	$result = sprintf($voltage_precision, ($raw - 470) * 0.009765);
    }
    elsif($HARDWARE eq $EACV2) {
	# TODO: uEAC reporting support
	# v2:  src = (4095-Value)*805^-6) / 2500 
	# v2:  snk = (value*805^-6) / 2500 
    }
    else { &crash("read_voltage(): Unsupported hardware flag recieved ($HARDWARE).\n"); }

    # Return the voltage
    &printc("read_voltage(): Conversion for DAC $index is: RAW($raw)=$result volts.\n\n");
    return $result;
}

#
# READ_LLA_INPUT - Returns the current on an LLA's input.
#
#  args: index
#
# NOTE: An LLA consists of two components -- an LLA_IN and an LLA_OUT.
#  The LLA_IN draws current off the sheet and into the transfer 
#  function.  The output of this function is the current on the LLA_OUT,
#  which may be reattached as either a source and/or sink on the sheet.
sub read_lla_input() {
    my $index, $raw, $result;

    if($HARDWARE eq $EACV1) {
	$index  = 40 + ($_[0] * 2);
	$raw    = &read_dac($index);
	$result = sprintf($current_precision, ($raw  - 455) * 0.5405);
    }
    elsif($HARDWARE eq $EACV2) {
	# TODO: uEAC LLA support
	# $raw = read_dac($_
    }
    else { &crash("read_lla_input(): Unsupported hardware flag recieved ($HARDWARE).\n"); }

    # Return the current
    &printc("read_lla_input(): Conversion for LLA_IN $index is: RAW($raw)=$result $current_unit.\n");
    return $result;
}

#
# READ_LLA_OUTPUT - Returns the current on an LLA's output.
#
#  args: index
#
sub read_lla_output() {
    my $index, $raw, $result;

    if($HARDWARE eq $EACV1) {
	$index  = 40 + ($_[0] * 2) + 1;
	$raw    = &read_dac($index);
	$result = sprintf($current_precision, ($raw  - 455) * 0.5405);
    }
    elsif($HARDWARE eq $EACV2) {
	# TODO: uEAC LLA support
    }
    else { &crash("read_lla_output(): Unsupported hardware flag recieved ($HARDWARE).\n"); }

    # Return the current
    &printc("read_lla_output(): Conversion for LLA_OUT $index is: RAW($raw)=$result $current_unit.\n");
    return $result;
}

#
# WRITE_SOURCE/SINK - Writes current to a source or sink.
#
#  args: index, current
#
sub write_source()  { return &write_dac( $SOURCE, $_[0], $_[1] ); }
sub write_sink()    { return &write_dac(   $SINK, $_[0], $_[1] ); }

#
# WRITE_LLA - Configures one or more LLAs.
#
#  args: index, function, out_src, out_snk
#
sub write_lla {
    my $index    = $_[0];
    my $function = $_[1];
    my $source   = $_[2];
    my $sink     = $_[3];

    #
    # Configure EAC (hardware v1) LLA in hardware:
    #
    if($HARDWARE eq $EACV1) {
	&write_dac($LLA_IN, $index, $function);
    }

    #
    # Configure uEAC (hardware v2) LLA in software
    #
    elsif($HARDWARE eq $EACV2) {
	# FIXME TODO: uEAC LLA support
	# &write_source(lla_in)
	# // set function [?]
	# // set src/snk output
    }

    # Illegal hardware
    else { &crash("write_lla(): Unsupported hardware flag recieved ($HARDWARE).\n"); }
    
    # Return the result
    #  TODO: uEAC src/snk outputs
    $result = "Function $function written to LLA on channel " . ($index + $feedback_adjustment) . ".\n";
    return $result;
}



# =============== EAC/uEAC COMMAND FUNCTIONS ===============

#
# READ_DAC - Returns the RAW value on a DAC.
#
#  args: index
#
sub read_dac() {
    my $index = $_[0];
    my $channel, $command, $prefix, $response, $result;

    #
    # Read from the EAC (hardware v1)
    #
    if($HARDWARE eq $EACV1) {

	$prefix  = 'A';
	$channel = sprintf("%02x", $index);

	# Build and issue the command, then wait for the response
	#  NOTE: The report command does not use the data field
	$command  = $prefix . $channel  . '000' . 'Z';
	$response  = &write_command($command);

	# Parse the responses and return the raw value
	$response =~ s/A.{2}//;
	$response =~ s/Z//;
	$result   = hex($response);
    }

    #
    # Read from the uEAC (hardware v2)
    #  TODO: uEAC support
    #
    elsif($HARDWARE eq $EACV2) {
	$result = "Not done yet.\n";
#	Pseudo-code:
#	my $gradient = &get_gradient();
#	my @gradient = split("\n", $gradient);
#	my $raw_current = $gradient[x];
#	my @raw = split(" ", $raw);
#	my $raw2 = @raw[y];
#	my $current = convert($raw2);
    }

    # Illegal hardware mode
    else { &crash("read_dac(): Unsupported hardware flag recieved ($HARDWARE).\n"); }

    # Return the value
    &printc("read_dac(): Raw value on DAC $index is $result.\n");
    return $result;
}

#
# WRITE_DAC - Writes current to sources or sinks.
#  FIXME AUDIT: somewhere in the v1 code the LLA is not computing properly
#
#  args: type, index, current
#
sub write_dac {
    my $type    = $_[0];
    my $index   = $_[1];
    my $data    = $_[2];
    my $channel, $command, $encoded_data, $prefix, $response, $result;

    #
    # Write EAC (hardware v1) DAC
    #
    #  Command: sources, sinks = DccdddZ
    #                     llas = FccdddZ
    #
    if($HARDWARE eq $EACV1) {
	my $offset;

	# Adjust the index of the channel for sinks
	#  FIXME: AUDIT variable usage here (num_sources)
	$offset = 0;
	if($type eq $SINK) { $offset = $num_sources; }

	# Encode the channel
	$channel = sprintf("%02x", $index + $offset);

	# For sources and sinks, compute the command prefix and the
	#  3-character HEX-based ASCII encoded current (10-bit=2^10=1024: ASCI(0000-1023), or HEX(000-3FF))
	if($type eq $SOURCE || $type eq $SINK) {
	    $prefix = 'D';

	    # BUGFIX: The difference between this toolkit and Bryce's original scripts
	    #  a factor of 1000; thus we need to scale back by THIS value, not max_current
	    my $ascii_current    = sprintf("%02d", $data * ($hardware_current_max / 1000));
#	    my $ascii_current    = sprintf("%02d", $data * ($hardware_current_max / $max_current));

	    my $hardware_current = sprintf("%03x", $ascii_current);
	    $encoded_data = $hardware_current;
	    &printc("write_dac(): Input current $data $current_unit " .
		    "converted to ASCII($ascii_current), HEX($hardware_current).\n");
	}

	# For LLAs, compute the command prefix and the
	#  3-character HEX-based function (001-01B)
	elsif($type eq $LLA_IN) {
	    $channel = sprintf("%02x", $index); # HACK
	    $prefix       = 'L';
	    $encoded_data = sprintf("%03x", $data);
	}

	# Issue the command and wait for a reply
	$command  = $prefix . $channel . $encoded_data . 'Z';
	$response = &write_command($command);
    }

    #
    # Write uEAC (hardware v2) DAC
    #
    #  Commands: source = PccddddZ
    #              sink = DccddddZ
    #
    # NOTE: Sources map current MIN-MAX inversely to 0000-4095.  This means
    #  that current MIN is actually 4095 for sources, while current MAX is
    #  0000.  Sinks operate as you would expect them to, MIN-MAX = 0000-4095.
    #
    # TODO: uEAC LLA support
    #
    elsif($HARDWARE eq $EACV2) {
	my $hardware_current, $translated_current;

	# Convert the channel to 2-character ASCII encoding
	$channel = sprintf("%02d", $index);

	#
	# Convert source current to decimal-based ASCII encoding --
	#  12-bit = 2^12 = 4096: ASCII(0000-4095)
	#
	# The formula for conversion is:
	#  amps  = ((4095 - value) * .000805) / 2500, or
	#  value = 4095 - (2500/.000805) * (mA * .000001)
	#
	if($type eq $SOURCE) { 
	    $prefix = 'P';
	    $translated_current = int(4095 - (2500 / .000805) * ($data * .000001));
	    $hardware_current   = sprintf("%04d", $translated_current);
	    &printc("write_dac(): Input current $data $current_unit converted to " . 
		    "$translated_current, ASCII($hardware_current).\n");
	}

	#
	# Convert sink current to decimal-based ASCII encoding (see above)
	#
	# The formula for conversion is:
	#  amps  = (value * .000805) / 2500
	#  value = (2500 * (mA * .000001)) / .000805
	# 
	elsif($type eq $SINK) { 
	    $prefix = 'M';
	    $translated_current = int((2500 * ($data * .000001)) / .000805);

	    # HACK: The prototype uEAC leaks current, we have to compensate for it here
	    my $ueac_hack = 64;
	    if($translated_current < $ueac_hack) { $translated_current = $ueac_hack; }
	    $hardware_current    = sprintf("%04d", $translated_current);
	    &printc("write_dac(): Input current $data $current_unit converted to " . 
		    "$translated_current, ASCII($hardware_current).\n");
	}

	# Something illegal
	else { &crash("write_dac(): Unrecognized connection type recieved ($type).\n"); }

	# Issue the command and wait for a reply
	my $command = $prefix . $channel . $hardware_current . 'Z';
	my $response = &write_command($command);
    }

    # Illegal hardware
    else { &crash("write_dac(): Unsupported hardware flag recieved ($HARDWARE).\n"); }

    # Format the response and return
    if($type eq $SOURCE) { 
	$result = "$data $current_unit written to source channel " . ($index + $feedback_adjustment) . ".\n";
    }
    elsif($type eq $SINK) { 
	$result = "$data $current_unit written to sink channel "   . ($index + $feedback_adjustment) . ".\n";
    }
    else {
	$result = "LLA function $data written to LLA channel "         . ($index + $feedback_adjustment) . ".\n";
    }
    return $result;
}



# =============== EAC/uEAC INTERFACE FUNCTIONS (2) ===============

#
# INIT_HARDWARE - Switches hardware modes.
#
# HACK: There are, at present, two versions of the EAC (hardware
#  v1), one that uses semi-conductiv foam and one that uses
#  silicon.  There are two issues with this:
#
#  1) Pin layout - the foam sheets are arranged in a grid while the
#     silicon chip is arranged radially.  This effects reporting.
#
#  2) Input and impedance - the foam sheet accepts input between
#     0-200 uA with comparitvely low impedance while the silicon
#     chip accepts 0-1000 uA with comparatively high impedance. This
#     effects both the range of acceptible input, and the process
#     of computation itself.
#
#  I didn't really think about either of these issues when I
#  orignally designed the initialization code.  Most of the code
#  uses the HARDWARE flag as an indicator of the number of sources,
#  sinks, and LLAs.  The idea of arrangement and variable current
#  wasn't really present until I hacked it in.  So the EACV1 and
#  EACV2 flags, originally meant to be mnemonics for HARDWARE flag
#  codes now are themselves flags for the various architectures.
#
#  Check out the notes in globals.pm for more notes on this, or
#  contact me if you have any questions about this.
#
sub init_hardware() {
    my $version = $_[0];

    # If input is set to be 1-based, activate an adjustment
    #  variable to convert to internal 0-based representation
    if($use_zero_based_positions eq $TRUE) { $feedback_adjustment = 0; }
    else { $feedback_adjustment = 1; }

    # Close any active connections to other EACs
    &close_socket();
    &close_serial_port();

    # Set the hardware flag
    $HARDWARE = $version;

    #
    # Initialize EAC (hardware v1) specific platform variables
    #
    if($version eq $EACV1) {

	# Define valid connections
	$min_position = 0;
	$max_position = $num_sources - 1;

	# Define current conversion variables
	$hardware_current_max = $eac_hardware_current_max;

	# Foam
	if($EACV1 eq $EAC_FOAM) { 
	    $eac = $default_foam_eac; 
	    $min_current = $min_foam_current;
	    $max_current = $max_foam_current;
	}

	# Silicon
	elsif($EACV1 eq $EAC_SILICON) { 
	    $eac = $default_silicon_eac; 
	    $min_current = $min_silicon_current;
	    $max_current = $max_silicon_current;
	}

	# Illegal substrate
	else { &crash("init_hardware(): Unsupported substrate recieved ($EACV1).\n"); }
    }

    #
    # Initialize uEAC (hardware v2) specific platform variables
    #
    elsif($version eq $EACV2) {

	# Define valid connections
	$min_position = 0;
	$max_position = ($num_rows * $num_cols) - 1;
	$min_row = 1;
	$max_row = $num_rows;
	$min_col = 1;
	$max_col = $num_cols;

	# Define valid current values
	$min_current = $min_ueac_current;
	$max_current = $max_ueac_current;
	$hardware_current_max  = $ueac_hardware_current_max;

	# USB
	if($EACV2 eq $UEAC_NET) { $eac = $default_net_ueac; }

	# Network
	elsif($EACV2 eq $UEAC_USB) { $eac = $default_usb_ueac; }

	# Illegal mode
	else { &crash("init_hardware(): Unsupported uEAC communication mode recieved ($EACV2).\n"); }
    }

    #
    # Illegal hardware mode
    #
    else { &crash("init_hardware(): Unsupported hardware flag recieved ($version).\n"); }

    # Print some debug information
    &printc("init_hardware(): Using communication protocol \'$HARDWARE\'.\n");
    &printc("init_hardware(): Minimum connection index is $min_position, " . 
	    "maximum connection index is $max_position.\n");
    &printc("init_hardware(): Minimum current is $min_current, maximum current is $max_current.\n");
    &printc("init_hardware(): Default EAC is at \'$eac\'.\n");
}

#
# WRITE_COMMAND - Writes a formatted command string to the EAC and returns its response.
#
sub write_command() {
    my $command = $_[0] . "\r";
    my $response;

    # Do not issue the command in test mode
    unless($TEST_MODE eq $FALSE) {
	return "Cannot reset in test mode.\n";
    }

    #
    # Write to the EAC (hardware v1) via a socket connection
    #
    if($HARDWARE eq $EACV1) {
	&open_socket();
	print S $command;
	$response = <S>;

	#
	# HACK: There is some kind of nasty unprintable character attached
	#  to $response -- chop and chomp either can't touch it or kill the
	#  whole string.  So this is my way of getting the relevant portion
	#  of the command results from the EAC.
	#
	$response = substr($response, 0, 7);
    }

    #
    # Write to the uEAC (hardware v2) via the USB connection
    #
    elsif($HARDWARE eq $EACV2) {
	&open_serial_port();
	$SerialPort->write($command);

	#
	# HACK: Lacking formal handshaking, we have to sleep for some
	#  amount of time to ensure we do not saturate the connection.
	#  As far as I know, this tries to select some undefined object
	#  for $SLEEP_TIME, then continues on when it (obviously) fails
	#  to do so... I dunno, I found this online when looking for an
	#  alternative to sleep() that could pause less than a second.
	#
	select(undef, undef, undef, $SLEEP_TIME);

	$response = $SerialPort->read(32);
	$response = substr($response, 0, 8);

	# HACK: Until the report sentence can be updated on the uEAC, we
	#  have to use R*Z, and subsequently read input differently
	# TODO: Parameterize the read amount
#	if($_[0] eq 'RVZ' ) {
#	    $response = $SerialPort->read(3 * 1024);
#	}
#	else {
#	    $response = $SerialPort->read(32);
#	}
    }

    # Illegal hardware mode
    else  { &crash("write_command(): Unsupported hardware flag recieved ($HARDWARE).\n"); }

    # Return the response
    &printc("write_command(): $HARDWARE command-response trace is $_[0]:$response.\n");
    return $response;
}



# =============== EAC/uEAC COMMUNICATION LAYER (1) ===============

#
# NOTE: This is the base abstraction layer, responsible
#  for minding direct communication with the EAC/uEAC.
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


# --------------- Socket connections ---------------

#
# NOTE: The EACs (hardware v1) all communicate over the network, and
#  as such can use the same networking plumbing.  I expect that the uEAC
#  proxy server will likewise use something like this, and that its
#  communication routines will simply need wrappers around the basic
#  socket routines here.
#

#
# OPEN_SOCKET - Maintains a network socket connection to the EAC.
#
sub open_socket() {
    if($TEST_MODE eq $TRUE) { return; }

    if($socket_open eq $FALSE) {
	my $port  = $EAC_PORT;
	my $iaddr = inet_aton("$eac") or
	    &crash("open_socket(): No host error: $eac.\n");
	my $paddr = sockaddr_in($port, $iaddr);
	my $proto = getprotobyname("tcp");
	socket(S, PF_INET, SOCK_STREAM, $proto) or
	    &crash("open_socket(): Socket error: $!.\n");
	connect(S, $paddr) or
	    &crash("open_socket(): Connection error: $!.\n");
	select(S); $|=1; select("stdout");
	$socket_open = $TRUE;
	&printc("open_socket(): Socket connection opened.\n");
    }
    else {
	&printc("open_socket(): Socket connection already open.\n");
    }
}

#
# CLOSE_SOCKET - Closes the active socket cleanly, if one exists.
#
sub close_socket() {
    if($socket_open eq $TRUE) {
	close S;
	$socket_open = $FALSE;
	&printc("open_socket(): Socket connection closed.\n");
    }
    else {
	&printc("open_socket(): There is no socket to close.\n");
    }
}



# --------------- Virtual serial port connections  ---------------

#
# NOTE: While there are two models of the EAC (foam and silicon),
#  uEACs, are, as far as I know, all the same.  And while both
#  versions of the EAC use the same network communication routines,
#  the uEAC will eventually operate over both USB, and through a
#  network proxy.  I suspect the latter versions will make use of
#  the socket functions above.
#

#
# OPEN_SERIAL_PORT - Maintains a virtual serial connection to a uEAC.
#
sub open_serial_port() {

    if($TEST_MODE eq $TRUE) { return; }

    # Open the serial port, if necessary
    if($serial_port_open eq $FALSE) {
	$SerialPort = new Device::SerialPort($eac,1) or
	    &crash("open_serial_port(): Cannot open serial port: $!.\n");
	$SerialPort->databits(8);
	$SerialPort->parity("none");
	$SerialPort->stopbits(1);
	$SerialPort->baudrate(19200);
	$SerialPort->handshake("none");
	&printc("open_serial_port(): Serial port opened.\n");
	$serial_port_open = $TRUE;
    }
    else {
	&printc("open_serial_port(): Serial port already open.\n");
    }
}

#
# CLOSE_SERIAL_PORT - Closes the open serial port connection, if one exists.
#
sub close_serial_port() {
    if($serial_port_open eq $TRUE) {
	$SerialPort->close() or 
	    &crash("close_serial_port(): Cannot close serial port connection.\n");
	$serial_port_open = $FALSE;
	&printc("open_serial_port(): Serial port closed.\n");
    }
    else {
	&printc("open_serial_port(): There is no serial port to close.\n");
    }
}
