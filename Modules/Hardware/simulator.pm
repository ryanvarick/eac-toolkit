#
# SIMULATOR.PM - Driver for Bryce's spice-based EAC simulator.
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
# DESCRIPTION:
#
#  Goes here.
#

package simulator;

use diagnostics;
use strict;
use warnings;



# ====================[ CONFIGURATION ]====================

use constant TRUE  => (1 == 1);
use constant FALSE => (0 == 1);
use constant NULL  => -1;

our $VERSION       =  '1.0.0';
our $DEBUG_ON      =  TRUE;

#
# Simulator names - collects stuff, so these differentiate types.
#  add here and in init_*() to support new simulator classes
#
my $EAC_NAME  = 'EAC simulator';
my $UEAC_NAME = 'uEAC simulator';



# 
use constant SIM_CURRENT_PRECISION_MASK => "%2.2f";
use constant SIM_MIN_CURRENT            =>   0.0;
use constant SIM_MAX_CURRENT            => 200.0;

use constant SIM_MIN_LLA_FUNCTION       =>    1;
use constant SIM_MAX_LLA_FUNCTION       =>   27;

use constant GRID_MAX_DIM  =>  1000;

my $GRID_SIZE_X;
my $GRID_SIZE_Y;
my $NODE_RESISTANCE;



# Simulator configuration (ngspice)
my $UNIT       = 'uA';
my $SPICE_UNIT = 'u';

my $SPICE_LOCATION = 'ngspice';



# Spice configuration

my $output_file = "TEST";



# internal book keeping
my $current_input_counter;
my $lla_input_counter;

my @current_source_array;
my @lla_position_array;
my @lla_array;

# execute - transient, no need to reset
my %voltage_hash;

# simulator control (TODO: implement flushing/autoflushing)
my $FLUSH_IMMEDIATELY     = FALSE;      # true = execute immediately, false = execute on read
my $CONFIGURATION_CHANGED = TRUE;       # used to track changes when flushing is off

# ====================[ END CONFIGURATION ]=====================







#
# INIT_DRIVER - Initialize the simulator.
#
#  args:    requested driver mode, requested eac
#  returns: status
#
sub init_driver($)
{
    my $driver = $_[0];

    #
    # set up the simulator for the requested EAC version --
    #
    #  NOTE: right now, this just effects the layout and genome
    #
    if($driver eq $Driver::EAC_SIMULATOR_DRIVER)     { simulator::init_eac_simulator();  }
    elsif($driver eq $Driver::UEAC_SIMULATOR_DRIVER) { simulator::init_ueac_simulator(); }
    else
    {
	Toolkit::crash('E_BAD_HARDWARE_MODE', $driver);
    }

    # initialize common values
    $Driver::unit                      = $UNIT;
    $Driver::attempt_device_connection = FALSE;

    # bookkeeping
    $current_input_counter = 0;
    $lla_input_counter     = 0;
    $CONFIGURATION_CHANGED = TRUE;

    # sanity check
    if(($GRID_SIZE_X < 1) || ($GRID_SIZE_X > GRID_MAX_DIM))
    {
	Toolkit::printd("X dimension out of range of 1<=x_dim<=GRID_MAX_DIM\n");
	return $Driver::ERROR;
    }
    if(($GRID_SIZE_Y < 1) || ($GRID_SIZE_Y > GRID_MAX_DIM))
    {
	Toolkit::printd("Y dimension out of range of 1<=y_dim<=GRID_MAX_DIM\n");
	return $Driver::ERROR;
    }

    if(($NODE_RESISTANCE <= 0) || ($NODE_RESISTANCE > 100000))
    {
	Toolkit::printd("Node resistance out of range 0<node_res<100000\n");
	return $Driver::ERROR;
    }

    Toolkit::printd("Simulator initialized, dimensions=${GRID_SIZE_X}x${GRID_SIZE_Y}, resistance=$NODE_RESISTANCE.\n");

    return $Driver::OK;
}

sub init_eac_simulator()
{
    # TODO: read from config
    $GRID_SIZE_X     = 7;
    $GRID_SIZE_Y     = 13;
    $NODE_RESISTANCE = 10000;

    $Driver::current_precision_mask = SIM_CURRENT_PRECISION_MASK;
    $Driver::min_current            = SIM_MIN_CURRENT;
    $Driver::max_current            = SIM_MAX_CURRENT;
    $Driver::min_lla_function       = SIM_MIN_LLA_FUNCTION;
    $Driver::max_lla_function       = SIM_MAX_LLA_FUNCTION;

    $Driver::hardware_layout = $Driver::FIXED_LAYOUT;
    $Driver::genome_length   = 8 + 8 + 6;

    $Driver::eac = $EAC_NAME;
}

#
# FIXME:
#
# the uEAC simulator doesn't work right now because the GA does not fully
#  support advanced EAC components (LLA_SRC/LLA_SNK)
#
sub init_ueac_simulator()
{
    # TODO: read from config
    $GRID_SIZE_X     = 5;
    $GRID_SIZE_Y     = 5;
    $NODE_RESISTANCE = 10000;

    $Driver::current_precision_mask = SIM_CURRENT_PRECISION_MASK;
    $Driver::min_current            = SIM_MIN_CURRENT;
    $Driver::max_current            = SIM_MAX_CURRENT;
    $Driver::min_lla_function       = SIM_MIN_LLA_FUNCTION;
    $Driver::max_lla_function       = SIM_MAX_LLA_FUNCTION;

    $Driver::hardware_layout = $Driver::FREE_LAYOUT;
    $Driver::genome_length   = 5 * 5;

    $Driver::eac = $UEAC_NAME;
}



#
# CONNECT/DISCONNECT - These routines aren't applicable for the simulator.
#
#  args:    <variable>
#  returns: status=NA
#
sub connect_to_device($)
{
    Toolkit::printd("Connect not necessary in simulator mode.\n");
    return $Driver::NA;
}

sub disconnect_from_device()
{
    Toolkit::printd("Disconnect not necessary in simulator mode.\n");
    return $Driver::NA;
}







# ====================[ API IMPLEMENTATION ]====================

#
# NOTE: The write routines simply updates the configuration in 
#  memory; we only need to run the simulator on read.  Further, we
#  can cache the results of the simulator until the configuration
#  changes.  Thus the use of a change-tracking flag.
#



#
# WRITE_* - Add a source or sink to the configuration.  To the 
#  simulator, the two are the same thing.  Sources add positive
#  current, while sinks add negative current.
#
#  args:    index, value
#  returns: status (assumed OK)
#
#  NOTE: 
#
#  TODO: globalize arrays
#
sub write_source { simulator::write_dac(@_); }
sub write_sink   { simulator::write_dac(@_); }

sub write_dac
{
    my $channel = $_[0];
    my $value   = $_[1];

    # TODO: check for NULL return value
    my($x, $y)  = Toolkit::translate_to_coords($channel, $GRID_SIZE_X);

    my $string0 = "I,$x,$y,-$value$SPICE_UNIT";
    my $string = "I,3,1,$value$SPICE_UNIT";
    Toolkit::printd("Writing $value $Driver::unit to channel $channel($x,$y) : $string ($string0)\n");

    $current_source_array[$current_input_counter++] = $string;
    $current_source_array[$current_input_counter++] = $string0;

    $lla_array[0] = 'L,3,3';

    $CONFIGURATION_CHANGED = TRUE;
    Toolkit::printd("Command successfully queued.\n");
}



#
# READ_* - Read a source or sink.  If the configuration has changed,
#  the simulator is run first; otherwise, the cached value is return
#
#  args:    index
#  returns: value
#
sub read_sink { simulator::read_dac(@_); }
sub read_source { simulator::read_dac(@_); }

sub read_dac
{
    # TODO: args go here (what to read)

    # if something has changed, we need to re-run the simulator
    if($CONFIGURATION_CHANGED eq TRUE)
    { 
	Toolkit::printd("Configuration changed, running simulator to update values...\n");
	simulator::run(); 
	$CONFIGURATION_CHANGED eq FALSE;
    }

    # if nothing has changed, we can read the cached values
    else
    {
	# process from cache
    }
}


sub read_lla
{
    # TODO: probably similar to read_dac
}

sub write_lla
{
    Toolkit::printd("Writing LLA... NOT ENABLED YET.\n ");

#    $lla_array[$lla_input_counter++] = $current_line;
}

sub reset
{
    # TODO: reset arrays

    $current_input_counter = 0;
    $lla_input_counter     = 0;

    @current_source_array  = ();
    @lla_position_array    = ();
    @lla_array             = ();

    Toolkit::printd("Simulator values cleared.\n");
}

















# ====================[ SPICE INTERACTION ]====================

#
# NOTE: Spice interaction is taken more-or-less verbatim from
#  Bryce's original simulator scripts.
#
# TODO: Globalize temporary files and spice location
#










sub report
{
    print "Creating a report of sheet voltages -> $output_file.v\n";
    open (VOLTAGE_GRADIENT,">$output_file.v");
    for (my $y=0;$y<$GRID_SIZE_Y;$y++) {
	for (my$x=0;$x<$GRID_SIZE_X;$x++) {
	    my $index=($y*$GRID_SIZE_X)+$x+1;
	    print VOLTAGE_GRADIENT "$voltage_hash{$index} ";
	}
	print VOLTAGE_GRADIENT "\n";
    }
    close (VOLTAGE_GRADIENT);




    print "Creating a report of LLA input currents -> $output_file.i\n";
    print "\n*** LLA Input Currents ***\n";
    open (CURRENT_REPORT,">$output_file.i");
    foreach (@lla_position_array) {
	my $lla_node=$_;
	my $lla_voltage=$voltage_hash{$lla_node};
	my $lla_current=$lla_voltage/10;
	my $lla_x = $lla_node%$GRID_SIZE_X;
	my $lla_y = int($lla_node/$GRID_SIZE_X)+1;
	print CURRENT_REPORT "LLA$lla_x\_$lla_y,$lla_current\n";
	print "LLA$lla_x\_$lla_y,$lla_current\n";
    }
    print "\n";
    close (CURRENT_REPORT);






    open(GNUPLOT_CMD,">gnuplot.cmd");
    print GNUPLOT_CMD "set terminal png\n";
    print GNUPLOT_CMD "set output \"$output_file.png\"\n";
    print GNUPLOT_CMD "set data style lines\n";
    print GNUPLOT_CMD "set parametric\n";
    print GNUPLOT_CMD "set time\n";
    print GNUPLOT_CMD "set title \"Sheet Voltage Gradient Simulation\"\n";
    print GNUPLOT_CMD "set nokey\n";
    print GNUPLOT_CMD "set hidden3d\n";

    my $x_scale;
    my $y_scale;

    if ($GRID_SIZE_X<20) {
	$x_scale = 4*$GRID_SIZE_X;
    }
    else {
	$x_scale=$GRID_SIZE_X;
    }
    if ($GRID_SIZE_Y<20) {
	$y_scale = 4*$GRID_SIZE_Y;
    }
    else {
	$y_scale=$GRID_SIZE_Y;
    }
    print GNUPLOT_CMD "set dgrid3d $x_scale,$y_scale,2\n";
    print GNUPLOT_CMD "set view 70,75,1,1\n";
    print GNUPLOT_CMD "splot \"$output_file.v\" matrix\n";
    close(GNUPLOT_CMD);
    print "Creating a surface plot of the voltage gradient -> $output_file.png\n";
    `gnuplot gnuplot.cmd`;


    system("eog $output_file.png > /dev/null &");

    # #`rm gnuplot.cmd`;
    # #`rm conductive_sheet.cir`;
}







#
# RUN - Run the simulator: first generate the spice file, then run
#  spice and process the results.
#
#  args:    none
#  returns: nothing (results stored indirectly)
#
sub run()
{
    simulator::write_spice_file();
    simulator::execute_spice_file();
    simulator::report();
}

#
# WRITE_SPICE_FILE - Translate stored simulator configuration to
#  a spice script.
#
#  args:    none
#  returns: nothing
#
sub write_spice_file
{
    open(SPICE_FILE, ">conductive_sheet.cir");
    print SPICE_FILE "vEAC Circuit\n";
    for (my $y=0;$y<$GRID_SIZE_Y;$y++) {
	for (my $x=0;$x<($GRID_SIZE_X-1);$x++) {
	    my $node = (($y*$GRID_SIZE_X)+$x+1);
	    my $next_node = $node+1;
	    print SPICE_FILE "RH$node $node $next_node $NODE_RESISTANCE\n";
	}
    }
    for (my $x=1;($x<$GRID_SIZE_X+1);$x++) {
	for (my $y=0;$y<($GRID_SIZE_Y-1);$y++) {
	    my $node = ($y*$GRID_SIZE_X)+$x;
	    my $next_node = $node + $GRID_SIZE_X;
	    print SPICE_FILE "RV$node $node $next_node $NODE_RESISTANCE\n";
	}
    }

    foreach (@current_source_array){
	my $current_line=$_;
	my @source_array=split(/,/,$current_line);
	if ((($source_array[1]>0) && ($source_array[1]<=$GRID_SIZE_X))&& \
	    (($source_array[2]>0) && ($source_array[2]<=$GRID_SIZE_Y))) {
	    my $position = (($source_array[2]-1)*$GRID_SIZE_X) + $source_array[1];
	    print SPICE_FILE "I$source_array[1]_$source_array[2] 0 $position $source_array[3]\n";
	    Toolkit::printd("Writing $current_line\n");
	}
	else {
	    die "invalid current source line -> $current_line\n";
	}
    }

    my $i=0;
    foreach (@lla_array) {
	my $current_line=$_;
	my @lla_arguments=split(/,/,$current_line);
	if ((($lla_arguments[1]>0) && ($lla_arguments[1]<=$GRID_SIZE_X))&& \
	    (($lla_arguments[2]>0) && ($lla_arguments[2]<=$GRID_SIZE_Y))) {
	    my $position = (($lla_arguments[2]-1)*$GRID_SIZE_X) + $lla_arguments[1];
	    print SPICE_FILE "Rlla$lla_arguments[1]_$lla_arguments[2] $position 0 10\n";
	    $lla_position_array[$i++]=$position;
	}
    }
    print SPICE_FILE ".op\n";
    close (SPICE_FILE);
}

#
# EXECUTE - Run spice and read the results into memory.
#
#  args:    none
#  returns: nothing (raw values stored in voltage_hash)
#
sub execute_spice_file
{
#    Toolkit::printd("@current_source_array");

    open(SPICE_RESULTS, "$SPICE_LOCATION -b conductive_sheet.cir |");
    while(<SPICE_RESULTS>)
    {
	my $current_line=$_;
	if($current_line =~ m/\s+V\(/) 
	{
	    chomp($current_line);
	    $current_line =~ s/\s+V\(/ /;
	    $current_line =~ s/\)/ /;
	    $current_line =~ s/\s+/ /;
	    my @fields = split(/\s+/, $current_line);
	    $voltage_hash{$fields[1]} = $fields[2];
	}
    }
    close(SPICE_RESULTS);
}

return TRUE;
