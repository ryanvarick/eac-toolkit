#
# FITNESS.PM - Fitness functions.
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

require 'config.pm';
# use strict;
# use warnings;


#
# EVALUATE_FITNESS - This is a bootstrapping function.
#
#  This function performs some startup tasks before kicking
#  over to the fitness evaluation routine.  All you should do
#  here is to add the appropriate fitness function to the 
#  return line.
#
sub evaluate_fitness() {

    # Do not re-evaluate elites (if enabled)
#    if($DISABLE_REEVALUATION eq true && fitness)
#    if ($genome[0][$fitness_index]>$NULL) {
#	print "Already evaluated $id, skipping\n";
#	return $genome[0][$fitness_index];
#    }

    # Reset the board (if enabled)
    if($reset_board eq $TRUE) {
	&reset_board();
    }

    # EDIT ME: Replace this with your fitness function.  Keep the @_
    #  operator, it is the current individual's genome.
    return &fitness_xor(@_);
}



# =============== FITNESS FUNCTIONS ===============

#
# FITNESS_TARGET - Drive toward a predefined pattern file
#
sub fitness_xor() {
    my @genome = @_;

    # Send the configuration to the EAC
    &printgd("fitness_xor(): Sending configuration to \'$eac\'...\n");

    # This writes the configuration to the EAC, going through the genome
    #  and setting things as layed out.  NULL values are ignored
#    &write_analog_configuration(@genome);



    # --------------- Begin test cases ---------------
    my $NUM_TESTS   = 1;
    my $accumulator = 0;
    my $result      = '';
    my $pause_time  = 100;

    for(my $i =0; $i < $NUM_TESTS; $i++) {


	# Initialize the "junk" genes first
	my $str = "  Remaining: ";
	for(my $j = 2; $j < $genome_length; $j++) {
	    my $type  = &get_type($genome[$j]);
	    my $value = &get_value($genome[$j]);

	    if($type eq $NULL) {
		$str .= "$j:NULL ";
	    }
	    else {
		$str .= "$j:($type,$value) ";
		if($type eq $SOURCE) {
		    &write_source($j, 115);
		}
		elsif($type eq $SINK) {
		    &write_sink($j, 115);
		}
		elsif($type eq $LLA_IN) {
#		    &printf("\nLLA FOUND\n");
		}
		else {
		    &crash("fitness::fitness_xor(): Illegal type found ($type).\n");
		}
	    }
	}
	&printf($str . "\n");



	# TEST 1: 0 xor 0 = 0
	#  expected output:  4.5
	&write_source(0, 0);
	&write_source(1, 0);
	$result = sprintf("%2.2f", &read_lla_input(1));
	&pause($pause_time);

	$diff = sprintf("%2.2f", abs(4.5 - $result));
	$accumulator += $diff;
	&printf("  Test 1: abs(4.5-$result=$diff)\t\tacc=$accumulator\n");



	# TEST 2: 1 xor 1 = 0
	#  expected output:  4.5
	&write_source(0, 115);
	&write_source(1, 115);
	$result = sprintf("%2.2f", &read_lla_input(1));
	&pause($pause_time);

	$diff = sprintf("%2.2f", abs(4.5 - $result));
	$diff = abs(4.5 - $result);
	$accumulator += $diff;
	&printf("  Test 2: abs(4.5-$result=$diff)\t\tacc=$accumulator\n");



	# TEST 3: 1 xor 0 = 1
	#  expected output:  85.0
	&write_source(0, 115);
	&write_source(1, 0);
	$result = sprintf("%2.2f", &read_lla_input(1));
	&pause($pause_time);

	$diff = sprintf("%2.2f", abs(85.0 - $result));
	$accumulator += $diff;
	&printf("  Test 3: abs(85.0-$result=$diff)\t\tacc=$accumulator\n");



	# TEST 4: 0 xor 1 = 0
	#  expected output:  85.5
	&write_source(0, 0);
	&write_source(1, 115);
	$result = sprintf("%2.2f", &read_lla_input(1));
	&pause($pause_time);

	$diff = sprintf("%2.2f", abs(85.0 - $result));
	$accumulator += $diff;
	&printf("  Test 4: abs(85.0-$result=$diff)\t\tacc=$accumulator\n");

    }

    my $fitness = $max_fitness - $accumulator;
    return $fitness;
}







#
# FITNESS_CHARACTER - Something I used to be working on, I'm
#  not really sure where I was going with this.
#
sub fitness_character() {
    my(@genome) = @_;
    my($fitness) = 0;

    $id = &get_id();

    if ($genome[0][$fitness_index]>$NULL) {
	print "Already evaluated $id, skipping\n";
	return $genome[0][$fitness_index];
    }

    &open_datadir();

    # Load the target file
    open(TARGET, "< target") or &crash("Can't open file: $_!\n");
    @target = <TARGET>;
    close TARGET;

    # Load the candidate file
    #$id = $last_id;
    open(CANDIDATE, "< ${id}.dat") or &crash("Can't open file: $_!\n");
    @candidate = <CANDIDATE>;
    close CANDIDATE;
    

    # Find min and max values in candidate array
    $target_string = join('', @target);
    @target_list = split(" ", $target_string);
    @target_list = sort @target_list;
    $target_min = $target_list[0];
    $target_max = $target_list[34];

    $candidate_string = join('', @candidate);
    @candidate_list = split(" ", $candidate_string);
    @candidate_list = sort @candidate_list;
    $candidate_min = $candidate_list[0];
    $candidate_max = $candidate_list[34];

    $fitness = 0;

    # Tokenize and diff
#    print "\n";
    for($i = 0; $i < 7; $i++) {
	@target_row = split(" ", $target[$i]);
	@candidate_row = split(" ", $candidate[$i]);
	
	for($j = 0; $j < 5; $j++) {
	    $scaled_target = ($target_row[$j] - $target_min)/ ($target_max - $target_min);
	    $scaled_candidate = ($candidate_row[$j] - $candidate_min)/ ($candidate_max - $candidate_min);

	    $fitness += abs($scaled_target - $scaled_candidate);
	}
    }
    
    # Record and return the fitness
    $genome[0][$fitness_index] = $fitness;
    return $fitness;
}
