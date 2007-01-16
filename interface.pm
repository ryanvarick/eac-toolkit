#!/usr/bin/perl -
#
# INTERFACE.PM - A user interface for the extended analog computer.
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
#  This module provides an interface to the extended analog
#  computers available at Indiana University.  The interface
#  itself is a simple read-eval-print-loop that in turn provides
#  two major sets of functionality:
#
#  1) Tools to interact with and manipulate the analog machines.
#  2) Tools to evolve configurations for the analog machines.
#
#  Refer to the manual for specific command information.
#
#
# MODULE OVERVIEW:
#
#  While this module can be thought of as the entry point for
#  this program, it does not necessarily have to be.  Each of the
#  modules provides different functionality:
#
#  config.pm    - Default values and global variables.
#  interface.pm - A simple user interface to the analog computer.
#  hardware.pm  - Hardware abstraction layer for the analog computer.
#  logging.pm   - File I/O and data logging routines.
#  utilities.pm - Various utility functions.
#  ga.pm        - Genetic algorithm package for analog.
#    fitness.pm - Fitness functions for the GA; you'll want to code here.
#
#
# OTHER FILES:
#
#  README       - Nothing right now.
#  HELPFILE     - Commands and notes for using the interface.
#  LICENSE      - A copy of the GPL.
#  /tests       - Some simple test scripts (for debugging).
#  /dataset*    - Logfiles, see notes in logging.pm.
#

require 'config.pm';


# use strict;

# use warnings;
# use diagnostics;



&main();
sub main() {

    # Check for and ignore command line mode
    if(@ARGV ne 0) {
	print "There is no command line support at this time, try \'./interface.pm\' instead.\n";
	exit;
    }

    # Catch interrupts so we can exit gracefully
    $SIG{'INT'} = 'break_handler';

    # Open (or create) and verify the initial data directory --
    #  Refer to the notes in globals.pm for more information
    &open_datadir(&get_latest_datadir());
    if($autoclean eq $TRUE) {
	my $dir = &get_datadir();
	&printlog("Autoclean enabled, re-initializing \'$dir\'.\n");
	&init_datadir($dir);
    }

    # Initialize the default EAC hardware
    &init_hardware($HARDWARE);

    # Splash screen
    &printf("\n");
    &printf("EAC Toolkit v$VERSION\n");
    &printf("\n");
    &printf("Before getting started, please take a look at the usage manual. If you\n");
    &printf("have comments or questions, please email me at <rvarick\@indiana.edu>.\n");
    &printf("\n");
    &printf("Type \"help\" for the command reference or \"quit\" to exit.\n\n");

    # Now start the program -- a very basic read-eval-print-loop (REPL)
    while($TRUE) {

	if($show_prompt eq $TRUE) {
	    &printf("> ");
	}

	# Wait for a line of input, tokenize it, and pass off 
	#  for processing (see below)
	my $kybd  = <STDIN>;  chomp $kybd;
	my @input = split(" ", $kybd);
	&process_tokens(@input);

	# An extra newline for prettiness
	&printf("\n");
    }
}



# =============== TOKEN PROCESSING ===============

#
# PROCESS_TOKENS - Given a list of tokenized input, determine what
#  should be done with it.
#
sub process_tokens() {
    my $token = $_[0];
    my $args  = scalar(@_);
    my @input = @_;

    # First make sure we have a defined token
    unless(defined $token) {
	&printd("process_tokens(): Null token caught.\n");
	return;
    }



    # -------------- PROGRAM CONTROL TOKENS ---------------

    #
    # quit, q - Handle exit requests.
    #
    if($token eq 'q' || $token eq 'quit') {
	&quit();
    }

    #
    # help, h - Invoke the help system.
    #  TODO: Abstract the system call here
    #
    elsif($token eq 'h' || $token eq 'help') {
	system("less $HELPFILE");
    }

    #
    # ga - Run the GA (optionally, run n number of times)
    #
    elsif($token eq 'ga') {
	my $runs = 1;
	if($args eq 2) { $runs = $input[1]; }
	for(my $i = 0; $i < $runs; $i++) {
	    &run_ga();
	}
    }

    #
    # hardware - Switch hardware modes.
    #
    elsif($token eq 'hardware') {
	if($input[1] eq $EAC_FOAM) { 
	    $EACV1 = $EAC_FOAM;
	    &init_hardware($EACV1); 
	}
	elsif($input[1] eq $EAC_SILICON) { 
	    $EACV1 = $EAC_SILICON;
	    &init_hardware($EACV1); 
	}
	elsif($input[1] eq $UEAC_NET) { 
	    $EACV2 = $UEAC_NET;
	    &init_hardware($EACV2); }
	elsif($input[1] eq $UEAC_USB) { 
	    $EACV2 = $UEAC_USB;
	    &init_hardware($EACV2); }
	elsif($args eq 2) { 
	    &printh("Usage: hardware <$EAC_FOAM, $EAC_SILICON, $UEAC_NET, $UEAC_USB>\n"); 
	}
	&printf("Using EAC at \'$eac\', protocol is \'$HARDWARE\'.\n");
    }

    #
    # eac - Change the active EAC/uEAC.
    #
    elsif($token eq 'eac') {
	if($args eq 2) {
	    &init_hardware($HARDWARE);
	    $eac = $input[1];
	}
	&printf("Using analog computer at \'$eac\', protocol is \'$HARDWARE\'.\n");
    }



    # -------------- PARAMTER TOKEN PROCESSING ---------------

    #
    # NOTE: These are variables that may be modified via the REPL.
    #  In globals.pm, you'll find a hash structure that contains
    #  a list parameter variables, and their associated print strings.
    #
    elsif(defined $parameters{$token}) {
	&printd("process_tokens(): \'$token\' was found in the parameters hash.\n");

	# Get the variable to be de-referenced -- Perl allows
	#  us to indirectly reference a variable name using the
	#  ${$var} construct.  Kind of a poor man's pointer, I think.
	my $var = $parameters{$token};

	# De-reference the variable and set to the input value
	#  NOTE: THERE IS NO ERROR CHECKING OF INPUT HERE!
	if($args eq 2) {
	    ${$var} = $input[1];
	}

	# Print the current (or new) value
	&printf($parameters{$token . $PARAMETER_SUFFIX} . " ${$var}.\n");
    }



    # -------------- TOGGLE TOKEN PROCESSING ---------------

    #
    # NOTE: These are variables whose values may be toggled via the REPL.
    #  Whereas the parameters above assign values to variables, these
    #  are simply variables that can be toggled on or off.  You'll find
    #  the toggles structure in globals.pm.
    #
    # NOTE: This works the same way as the parameter processor above.
    #
    elsif(defined $toggles{$token}) {
	&printd("process_tokens(): \'$token\' found in the toggles hash.\n");

	my $var = $toggles{$token};
	if($args eq 2) {
	    $toggle = $input[1];
	    if($toggle eq 'on') {
		${$var} = $TRUE; 
	    }
	    elsif($toggle eq 'off') { 
		${$var} = $FALSE;
	    }
	    else {
		&printh("Usage: $token <on|off>\n");
	    }
	}

	my $val = ${$var};
	if($val eq $TRUE) { 
	    &printf($toggles{$token . $TOGGLE_SUFFIX} . " enabled.\n"); 
	}
	else { 
	    &printf($toggles{$token . $TOGGLE_SUFFIX} . " disabled.\n"); 
	}
    }



    # -------------- DATASET MANAGEMENT ---------------

    #
    # clean - Reset the current data directory.
    #
    elsif($token eq 'clean') {
	my $dir = &get_datadir();
	&init_datadir($dir);
	&printf("Data directory at \'$dir\' reset.\n");
    }

    #
    # load - Load an existing data directory.
    #
    elsif($token eq 'load') {
	if($args ne 2) {
	    &printh("load <dataset>\n");
	}
	else {
	    my $id  = $input[1];
	    my $dir = $datadir_prefix . $id;

	    if(-e $dir) {
		&close_datadir();
		&open_datadir($id);
		&printf("Data directory at \'$dir\' loaded.\n");
	    }
	    else {
		&printf("Data directory at \'$dir\' not loaded; directory does not exist.\n");
	    }
	}
    }

    #
    # save - Create a new data directory, saving the current one.
    #
    elsif($token eq 'save') {
	my $old_dir = &get_datadir();
	&save_datadir();
	my $new_dir = &get_datadir();
	&printf("Data directory at\'$old_dir\' saved; new data directory is \'$new_dir\'.\n");
    }



    # -------------- EAC REPORTING UTILITIES ---------------

    #
    # report - Read the voltage gradient on the sheet and save
    #  save it to a file (the location may be set in globals.pm).
    #
    elsif($token eq 'report') {
	my $id = &get_id();
	my $gradient = &get_gradient();
	&record_gradient($id, $gradient);

	# Check for optional 'plot' and 'view' too
	if($input[1] eq 'plot') {
	    &plot($id, $gradient);
	    if($input[2] eq 'view') {
		&view($id);
	    }
	    else {
		&printf($gradient);
	    }
	}
	else {
	    &printf($gradient);
	}

	# Gradients are sequentially indexed using the third
	#  field of the identifier (00-000-00), here we update
	#  after reporting the gradient
	&increment_gradient_id();
    }

    #
    # plot - Plot a voltage gradient.  'plot last' will plot
    #  the last voltage gradient saved by the report keyword.
    #
    elsif($token eq 'plot') {
	if($args ne 2) {
	    &printh("plot <gradient id>\n");
	}
	else {
	    if($input[1] eq 'last') {
		my $id = &get_last_id();
		if($id eq $NULL) { &printf("There is no previous gradient to plot.\n"); }
		else { &plot($id); }
	    }
	    else {
		&plot($input[1]);
	    }
	}
    }

    #
    # view - View a plotted voltage gradient.  Again, 'view last'
    #  can be used to view the last plotted gradient.
    #
    elsif($token eq 'view') {
	if($args ne 2) {
	    &printh("view <plot id>\n");
	}
	else { 
	    if($input[1] eq 'last') {
		my $id = &get_last_id();
		if($id eq $NULL) { &printf("There is no previous plot to view.\n"); }
		else { &view($id); }
	    }
	    else {
		&view($input[1]);
	    }
	}
    }

    #
    # rpv - A handy shortcut for 'report plot view' - Read the gradient,
    #  plot it, and open the plot in the defaut viewer.  Optionally, rpv
    #  accepts a number that indicates how many times to report.
    #
    elsif($token eq 'rpv') {
	my $samples = 1;
	if($args eq 2) { $samples = $input[1]; }
	for(my $i = 0; $i < $samples; $i++) {
	    my $id = &get_id();
	    my $gradient = &get_gradient();
	    &record_gradient($id, $gradient);
	    &plot($id, $gradient);
	    &view($id);
	    &increment_gradient_id();
	}
    }



    # --------------- DIRECT EAC COMMUNICATION ---------------

    #
    # reset - Reset the connections on the sheet.
    #  NOTE: For hardware v1, LLAs are fixed and cannot be reset.
    #
    elsif($token eq 'reset') {
	$status = &reset_board();
	&printf($status);
    }

    #
    # source, sink - Write current to sources and sinks.
    #
    elsif($token eq 'source' || $token eq 'sink') {
	my $range = ($min_position + $feedback_adjustment) . '-' . 
	    ($max_position + $feedback_adjustment);

	# Print a help message
	if($args < 3 || $args > 4) {
	    &printh("$token <position: $range> <current: $min_current-$max_current $current_unit>\n");
	}
	else {

	    # Identify whether to write a source or sink
	    my $type = $NULL;
	    if($token eq 'source') { $type = $SOURCE; }
	    else { $type = $SINK; }

	    # Decode the position(s) and current value --
	    #  the logic for this is more complicated than it might seem,
	    #  read the notes for these functions for more information
	    my $lower = &get_position($input[1]);
	    my $upper;
	    my $current;
	    if($args eq 3) {
		$upper = $lower;
		$current = &get_current($input[2]);
	    }
	    else {
		$upper = &get_position($input[2]);
		$current = &get_current($input[3]);
	    }

	    # Validate the position(s) and current value
	    if($lower eq $NULL || ($upper eq $NULL && $args eq 4)) {
		&printh("Postions should be between $range.\n");
	    }
	    elsif($args eq 4 && $lower > $upper) {
		&printh("Positions should be a valid range.\n");
	    }
	    elsif($min_current > $current || $current  > $max_current) {
		&printh("Current should be between $min_current-$max_current $current_unit.\n");
	    }
	    else {

		# If everything checks out, write the current and
		my $status;
		for(my $i = $lower; $i <= $upper; $i++) {
		    $status .= &write_dac($type, $i, $current);
		}
		&printf($status);
	    }
	}
    }

    #
    # lla - Configure one or more LLAs.
    #
    # NOTE: This function was more trouble to write than it is
    #  worth!  The following cases are supported:
    #
    #   1)  v1: lla p f
    #   2)  v2: lla p f
    #
    #   3)  v1: lla p1 p2 f
    #   4)  v2: lla p1 p2 f
    #
    #   5)  v2: lla p f src
    #   6)  v2: lla p f snk
    #
    #   7)  v2: lla p f src snk
    #
    #  v1/v2    = hardware version
    #   p*      = position(s)
    #   f       = function
    #   src/snk = LLA output connection
    #
    # TODO: The following cases are also possible, but not implemented,
    #  because it doesn't make sense for multiple LLAs to source or
    #  or sink to the same position.
    #
    #   1)  v2: lla p1 p2 f src
    #   2)  v2: lla p1 p2 f snk
    #   3)  v2: lla p1 p2 f src snk
    #
    elsif($token eq 'lla') {
	my($lower, $upper, $function);
	my $source = $NULL;
	my $sink   = $NULL;
	my $positions_verified = $FALSE;

	# HACK: For invalid input, the help message should be shown.  I am
	#  not sure how best to do this, so this variable is set when one
	#  of the input checking steps fails.
	my $show_usage = $FALSE;

	# HACK: Because of the way I implemented position checking, we have
	#  to adjust the value for hardware v1.  Ugly, I know.  See notes in
	#  globals.pm and the notes for init_hardware() in hardware.pm for
	#  more information about this.
	my $saved = $max_position;
	if($HARDWARE eq $EACV1) { $max_position = ($num_llas - 1); }
	my $range = ($min_position + $feedback_adjustment) . "-" . ($max_position + $feedback_adjustment);

	# Print a help message
	if($args < 3 || $args > 5) { $show_usage = $TRUE; }

	# Handle cases (1) and (2)
	elsif($args eq 3) {
	    &printd("process_tokens(): Processing LLA configuration as cases 1-2.\n");

	    # Process configuration
	    $lower = &get_position($input[1]);
	    $upper = $lower;
	    $function = $input[2];

	    # Error checking
	    unless($lower eq $NULL) {
		$positions_verified = $TRUE; 
	    }
	}
	elsif($args eq 4) {

	    # Handle cases (3) and (4)
	    if($input[3] eq int($input[3])) {
		&printd("process_tokens(): Processing LLA configuration as cases 3-4.\n");

		$lower = &get_position($input[1]);
		$upper = &get_position($input[2]);
		$function = $input[3];

		unless($lower eq $NULL || $upper eq $NULL || $lower > $upper) { 
		    $positions_verified = $TRUE;
		}
	    }

	    # Handle cases (5) and (6)
	    elsif($HARDWARE eq $EACV2) {
		&printd("process_tokens(): Processing LLA configuration as cases 5-6.\n");

		$lower = &get_position($input[1]);
		$upper = $lower;
		$function = $input[2];

		# Decode the output connection
		my @output = split('=', $input[3]);
		if($output[0] eq 'src') { $source = &get_position($output[1]); }
		if($output[0] eq 'snk') { $sink   = &get_position($output[1]); }

		unless($source eq $NULL && $sink eq $NULL) {
		    $positions_verified = $TRUE;
		}
	    }
	    else { $show_usage = $TRUE; }
	}

	# Handle case (7)
	elsif($args eq 5 && $HARDWARE eq $EACV2) {
	    &printd("process_tokens(): Processing case 7.\n");
	    $lower = &get_position($input[1]);
	    $upper = &get_position($input[2]);
	    $function = $input[2];

	    # Decode the output connections
	    my @src = split('=', $input[3]);
	    my @snk = split('=', $input[4]);
	    $source = &get_position($src[1]);
	    $sink   = &get_position($snk[1]);
	    
	    unless($lower eq $NULL || $upper eq $NULL || $source eq $NULL || $sink eq $NULL) {		
		$positions_verified = $TRUE;
	    }
	}
	else { $show_usage = $TRUE; }

	# Show help, if necessary
	if($show_usage eq $TRUE) {
	    if($HARDWARE eq $EACV1) {
		&printh("Usage: lla <position:$range> <lla:$min_lla-$max_lla>\n");
	    }
	    else {
		&printh("Usage: lla <position:$range> <lla:$min_lla-$max_lla> " . 
			"(<src=$range> <snk=$range>)\n");
	    }
	}

	# Verify the positions are both in range
	elsif($positions_verified eq $FALSE) {
	    &printh("Postions should be between $range.\n");
	}

	# Check the LLA function before writing
	else {
	    if($function ne int($function) || $min_lla > $function || $function > $max_lla) {
		&printh("LLA function should be between $min_lla-$max_lla.\n");
	    }
	    else {
		for(my $i = $lower; $i <= $upper; $i++) {
		    $status = &write_lla($i, $function, $source, $sink);
		    &printf($status);
		}
	    }
	}

	# HACK: Leave things as we found them (see above)
	$max_position = $saved;
    }

    # FIXME: No error checking
    #  HACK:  Subtacting feedback_adjustment as a compensation for 1-based indexing
    elsif($token eq 'poll-lla') {
	if($args ne 3) {
	    &printh("poll-lla <channel> <number of times>\n");
	}
	else {
	    my $channel = $input[1] - $feedback_adjustment;
	    my $seconds = $input[2];
	    for(my $i = 0; $i < $seconds; $i++) {
		my $status = &report_lla($channel, $channel);
		&printf($status);
		&pause(500);
	    }
	}
    }

    #
    # report-lla - Read the values from an LLA.
    #
    elsif($token eq 'report-lla') {

	# HACK: Same hack as above (lla)
	my $saved = $max_position;
	if($HARDWARE eq $EACV1) { $max_position = ($num_llas - 1); }
	my $range = ($min_position + $feedback_adjustment) . "-" . ($max_position + $feedback_adjustment);

	# Print a help message
	if($args < 2 || $args > 3) {
	    &printh("report-lla <position $range>\n");
	}
	else {

	    # Check the positions
	    my $lower = &get_position($input[1]);
	    my $upper = &get_position($input[2]);
	    if($lower eq $NULL || ($upper eq $NULL && $args eq 3)) {
		&printh("Positions should be between $range.\n");
	    }
	    elsif($args eq 3 && $lower > $upper) {
		&printh("Positions should be a valid range.\n");
	    }
	    else {

		if($lower > $upper) { $upper = $lower; }

		my $status = &report_lla($lower, $upper);
		&printf($status);
	    }
	}

	# HACK: Leave things as we found them (see above)
	$max_position = $saved;
    }

    elsif($token eq 'report-chain') {
	# HACK: input checking sucks
	$index = $input[1] - $feedback_adjustment;

	if($args ne 2) {
	    &printh("report-chain <channel>\n");
	}
	else {
	    my $status = &report_chain($index, $index + 1);
	    &printf($status);
	}
    }

    # FIXME: No error checking
    #  HACK:  Subtacting feedback_adjustment as a compensation for 1-based indexing
    elsif($token eq 'poll-chain') {
	if($args ne 3) {
	    &printh("poll-lla <channel> <number of times>\n");
	}
	else {
	    my $channel = $input[1] - $feedback_adjustment;
	    my $seconds = $input[2];
	    for(my $i = 0; $i < $seconds; $i++) {
		my $status = &report_chain($channel, $channel + 1);
		&printf($status);
		&pause(500);
	    }
	}
    }

    # FIXME:  Assumes daisy-chained LLAs
    elsif($token eq 'sweep-lla') {
	if($args ne 3) {
	    &printh("sweep-lla <channel> <increment>\n");
	}
	else {
	    my $channel   = $input[1] - $feedback_adjustment;
	    my $increment = $input[2];

	    # min and max should be CAPITALIZED
	    for(my $current = $min_current; $current <= $max_current; $current += $increment) {
		my $status  = &write_source(0, $current);
		$status    .= &report_chain($channel, $channel + 1);
		&printf("Testing with source $current uA: " . $status);
	    }
	    for(my $current = $min_current; $current <= $max_current; $current += $increment) {
		my $status = &write_source(1, $current);
		$status   .= &report_chain($channel, $channel + 1);
		&printf("Testing with source $current uA: " . $status);
	    }
	}
    }


    # -------------- UNRECOGNIZED TOKENS ---------------

    else {
	&printd("process_tokens(): Parsing token \'$token\' failed.\n");
	&printf("Command not recognized.  Type \"help\" for usage or \"quit\" to exit.\n");
    }

}

#
# GET_CURRENT - Returns a sanitized current value or NULL if the
#  input was invalid to begin with.
#
#  NOTE: Validating legitimate value is easy enough, we just compare against
#   min- and max-current.  Testing for nonsense is more difficult, because
#   Perl casts non-numeric values to zero.  To account for that, we have to first
#   explicitly check for '0' or '0.0'.  After that, anything that comes back
#   as zero has been casted by Perl to zero, and is therefore non-numeric.
#
sub get_current() {
    my $current = $_[0];
    my $junk_test = $current + 0;

    # Verify first that a value was recieved
    if(not(defined($current)) || not(defined($current eq 0))) { 
	&printd("get_curent(): No value recieved.\n");
	return $NULL;
    }

    # Verify the value is not garbage
    if($junk_test eq 0 && $current ne '0' && $current ne '0.0') {
	&printd("get_current(): Invalid current value recieved.\n");
	return $NULL;
    }

    # Verify that the value is in range
    if($min_current > $current || $current > $max_current) {
	&printd("get_current(): Current is out of range.\n");
    }

    &printd("get_current(): Current value of $current $current_unit is valid.\n");
    return $current;

}

#
# GET_POSITION - Returns a sanitized, 0-based index or NULL if
#  the input was invalid to begin with.
#
# NOTE: Determining whether a position is valid or not seems like
#  it is far more complicated than it needs to be.  Here are the
#  the issues that need to be considered:
#
#  1) Hardware mode (v1, v2) - this effects the range of valid
#     positions.  For v2 this is 0-24, for v1 it is *generally*
#     0-7 (sources and sinks, see #2 for LLAs).
#  2) Unfortunately, the v1 LLAs are a special case, and they
#     are only valid for 0-5.  It is not worth the trouble to
#     validate for this case, so it is assumed the token processor
#     will handle things accordingly (see HACKs above).
#  3) Index notation vs. row-col notation.  This is fairly easy
#     to handle, row-col notation is tested for and converted to
#     index notation before the actual position is evaluated.
#  4) When given two positions, are they a valid range; that is,
#     is the first position less than the second.
#  5) Are the given positions valid (between $min- and $max_position)?
#  6) Reference mode - is input expected in 0-based or 1-based for?
#     This is handled by a flag in globals.pm.
#
# NOTE: Given these considerations, here's how I am validating:
#
#  1) The position must be defined.
#  2) If it is not equal to the integer cast of itself than it is 
#     assumed to be row-col notatation and thus converted to an index.
#  3) When converting, the position should split into 2 likewise
#     defined values that are equal to the integer casts of themselves.  
#  4) If either of these is not defined, or the conversion does not
#     yield a valid number, then we return NULL.
#
sub get_position() {
    my $value = $_[0];

    # Verify first that a value was recieved
    if(not(defined($value))) {
	&printd("get_position(): No value recieved.\n");
	return $NULL; 
    }

    # Print input assumption for debugging
    elsif($use_zero_based_input eq $TRUE) { 
	&printd("get_position(): Assuming input \'$value\' is zero-based, no conversion necessary.\n"); 
    }
    else { 
	&printd("get_position(): Assuming input \'$value\' is one-based, conversion is necessary.\n"); 
    }

    # If the value is not an integer, try to convert to one
    if($value ne int($value)) {

	# But only for hardware v2 (row-col does not make sense for v1)
	if($HARDWARE ne $EACV2) {
	    &printd("get_position(): Invalid index, conversion is not applicable for hardware v1.\n");
	    return $NULL;
	}

	&printd("get_position(): Trying to convert \'$value\' to index notation.\n");

	my @position = split('x', $value);
	my $row = $position[0];
	my $col = $position[1];

	# Verify that both $row and $col are defined
	if(not(defined($row)) || not(defined($col))) {
	    &printd("get_position(): Conversion failed, one of the row-column indices is not defined.\n");
	    return $NULL;
	}

	# Verify that both $row and $col are valid integers
	if($row ne int($row) || $col ne int($col)) {
	    &printd("get_position(): Conversion failed, one of the row-column " .
		    "indices is not an integer.\n");
	    return $NULL;
	}

	# Convert zero-based input to one-based (0x will cause problems)
	#  NOTE: This is re-adjusted during evaluation (kind of a confusing HACK, I know)
	if($use_zero_based_input eq $TRUE) {
	    $row++;
	    $col++;
	}

	# Verify that $row and $col are legal indices
	if($row < $min_row || $row > $max_row || $col < $min_col || $col > $max_col) {
	    &printd("get_position(): Conversion failed, one of the row-column indices is out of range.\n");
	    return $NULL;
	}

	# Convert the row and column into a single index
	$value = ($row * $num_rows) - ($num_cols - $col);
	&printd("get_position(): Converted value is \'$value\'.\n");
    }

    # Convert one-based input to zero-based input, if necessary
    if($use_zero_based_input ne $TRUE) {
	&printd("get_position(): Converting position \'$value\' to " . 
		"a zero-based index for verification.\n");
	$value--;
    }

    # Verify that the input value is in range
    &printd("get_position(): Verifying $min_position <= $value <= $max_position: ");
    if($min_position > $value || $value > $max_position) {
	&printd("Out of range.\n");
	return $NULL;
    }

    &printd("Position is valid.\n");
    return $value;
}

#
# DECODE_POSITION - Translates an array index into row-column notation.
#  The reverse of get_position(), though the naming could be better.
#
sub decode_position() {
    my $position = $_[0];
    my $row = int($position / $num_rows) + 1;
    my $col = ($position % $num_rows) + 1;
    return $row . 'x' . $col;

}
