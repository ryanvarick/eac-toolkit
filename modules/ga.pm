#!/usr/bin/perl
#
# GA.PM - 
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
#  Stuff goes here.
#
#

package ga;

use diagnostics;
use strict;
use warnings;

use fitness;
use hardware;



# =============== USER CONFIGURATION ===============

# T/F should be imported from somewhere
# my $TRUE = $common:TRUE;
my $NULL  = -1;
my $TRUE  = (1 == 1);
my $FALSE = (1 == 0);

our $FEEDBACK_ON      = $TRUE;
our $VERBOSE_ON       = $TRUE;
our $DEBUG_ON         = $TRUE;
our $DEBUG_GENOME_ON  = $FALSE;

our $ONE_BASED_FEEDBACK_ON = $TRUE;

our $max_generations = 1;
our $population_size = 5;

# fitness
our $max_fitness       = 100;
our $fitness_threshold = 100;
our $fitness_mask      = "%2.2f";

# init
our $non_coding_prob = .50;
our $use_gene_values = $FALSE;

# default eac configuration stuff 
our $max_sources = 8;
our $max_sinks   = 8;
our $max_llas    = 6;

# default ueac configuration stuff
our $num_rows = 5;
our $num_cols = 5;

# --------------- DO NOT EDIT BELOW THIS LINE ---------------

# connection things
our $SOURCE_TYPE    = 'S';
our $SINK_TYPE      = 'K';
our $LLA_IN_TYPE    = 'L';
our $LLA_SRC_TYPE   = 's';
our $LLA_SNK_TYPE   = 'k';
our $NONCODING_TYPE = '-';

# these are arbitrary
our $FITNESS_SUFFIX   = '-f';
our $GENETYPE_SUFFIX  = '-t';
our $GENEVALUE_SUFFIX = '-v';

our $eac;
our $protocol;
our $hardware_layout;
our $genome_length;
our $feedback_adjustment;
our $ga_start_time;
our $ga_end_time;

our %population;


# this needs a lot of work
our %error_table = 
    ('E_UNSUPPORTED_LAYOUT' => 'Unsupoorted hardware layout encountered',
     'E_GENE_OUT_OF_BOUNDS' => 'Gene index out of bounds',
     'E_GENERAL'            => '');

# =============== END USER CONFIGURATION  ===============

# TODO: Remove this and chmod 644 this when debugging is done
#  or, check how this is called and run like this if we want
&ga::run();







# =============== PROGRAM START ===============

#
# GA_RUN - This function oversees the exectution of the GA.
#
#  args:    none
#  returns: nothing
#
sub run() 
{

    #
    # 1) Make sure we have everything set up before we start the GA
    #
    &ga::printf("\n");
    &ga::printd("ga::run(): ");
    &ga::printf("Initializing the genetic algorithm...\n");
    &ga::init();


    #
    # 2) Randomly initialize the first generation of the population
    #
    &ga::printd("ga::run(): ");
    &ga::printf("Initializing the first population...\n");
    &ga::printd("\n");
    &ga::init_population();


    #
    # 3) Run the GA for N generations (most of this is just print statements)
    #
    for(my $generation = 0; $generation < $ga::max_generations; $generation++) 
    {
	# Print-friendly version of $generation
	my $gen_prt = $generation + $ga::feedback_adjustment;

	# This check is here because we want the loop to stop after evaluating the
	#  final generation; however, if we blindly breed/evaluate, we will end up
	#  skipping the initial population
	if($generation > 0) 
	{
	    &ga::printg("-------------- BREEDING NEW GENERATION $gen_prt/$ga::max_generations --------------\n\n");
	    &ga::breed_new_generation();
	    &ga::printg("\n");
	}

	# Now that we are sure we're doing things in the right order, we can go ahead
	#  and evaluate each genome in the population
	&ga::printf("\n\n");
	&ga::printf("=============== EVALUATING GENERATION $gen_prt/$ga::max_generations ===============\n\n");

	&ga::evaluate_population();

	# With evaluation done, get the genome and fitness score
	my $best_genome  = &ga::get_best_genome();
	my $best_fitness = &ga::get_fitness($best_genome);

	# Check the best fitness against the desired fitness and report accordingly
	&ga::printf("\n\n");
	if($best_fitness >= $ga::fitness_threshold) 
	{
	    &ga::printf("-------------- FITNESS THRESHOLD SATISFIED --------------\n");
	    &ga::printf("Something witty.\n\n");
	    return;
	}
	else 
	{
	    &ga::printf("------------ FITNESS THRESHOLD NOT SATISFIED ------------\n\n");
	    &ga::printf("Statistics for generation $gen_prt/$ga::max_generations: " . 
			"f_min=" . sprintf($ga::fitness_mask, 0) . ", " .
			"f_max=" . sprintf($ga::fitness_mask, 0) . ", " .
			"f_avg=" . sprintf($ga::fitness_mask, 0) . ".\n");
	    &ga::printf("\n");
	    &ga::printf("Best genome so far is at index $best_genome; fitness is " .
			sprintf($ga::fitness_mask, $best_fitness) . "/$ga::max_fitness.\n\n");
	}
    }


    #
    # 4) If the loop finishes, report that no suitable genome was found and exit
    #
    &ga::printf("\n");
    &ga::printf("Genetic algorithm completed in " . &ga::get_running_time() . " seconds.\n");
    &ga::printf("No suitable genomes were found.\n\n");
    return;

}







# --------------- INIT FUNCTIONS ---------------
#
# These functions are called, sometimes indirectly, 
#  by the overseer function, run().  They are used
#  primarily to initialize the first generation.
#



#
# INIT - This function figures out what we need to
#  know about the hardware we are working with.
#
#  args:    none
#  returns: nothing
#
sub init() 
{
    # Start the timer
    $ga::ga_start_time = time;

    # Determine whether output is 0- or 1-based
    if($ga::ONE_BASED_FEEDBACK_ON)
    {
	$ga::feedback_adjustment = 1;
    }
    else
    {
	$ga::feedback_adjustment = 0;
    }

    # NOTE: this routine is hardware dependent
    #  FIXME TODO: I don't know if we need this really
    $ga::eac = 'null';
    $ga::protocol = 'test-mode';


    # Determine which genome configuration to use
    $ga::hardware_layout = $hardware::CONNECTION_LAYOUT;

    if($ga::hardware_layout eq $hardware::LINEAR_LAYOUT) 
    {
	$ga::genome_length = $ga::max_sources + $ga::max_sinks + $ga::max_llas;	
    }
    elsif($ga::hardware_layout eq $hardware::GRID_LAYOUT) 
    {
	$ga::genome_length = $ga::num_rows * $ga::num_cols;
    }
    else
    {
	&crash('E_UNSUPPORTED_LAYOUT', 'ga::init()', $ga::hardware_layout);
    }


    # Debugging information
    &ga::printd("  ga::init(): Feedback adjustment is +$ga::feedback_adjustment.\n");
    &ga::printd("  ga::init(): Active EAC is located at '$eac'.\n");
    &ga::printd("  ga::init(): Using communication protocol '$protocol'.\n");
    &ga::printd("  ga::init(): Connection layout is '$ga::hardware_layout'.\n");
    &ga::printd("  ga::init(): Genome length is $ga::genome_length.\n");
    &ga::printd("  ga::init(): Non-coding probability is $ga::non_coding_prob.\n");
    &ga::printd("\n");
}



#
# INIT_POPULATION - This function iterates genome
#  intialization over the entire population.
#
#  args:    none
#  returns: nothing
#
sub init_population() 
{
    for(my $genome = 0; $genome < $ga::population_size; $genome++) 
    {
	&ga::printd("ga::init_population(): Generating initial genome " . ($genome + $ga::feedback_adjustment) . 
		    "/$population_size...\n");
	&ga::init_genome($genome);

	# If we're in debugging mode, let's (visually) check that the 
	#  genome initialized okay
	if($ga::DEBUG_ON eq $TRUE)
	{
	    &ga::printd(&ga::get_printable_genome($genome) . "\n");
	}
    }
}



#
# INIT_GENOME - This function intializes the genes
#  of a particular genome.
#
#  args:    genome index
#  returns: nothing
#
sub init_genome() 
{
    my $genome = $_[0];

    # To debug genome initialization, the connection string is built up dynamically
    #  here, to be (optionally) printed afterward (see below)
    my $debug_str = 'ga::init_genome(): Connection string is:  ';

    #
    # 1) Set the genome's fitness score to NULL
    #
    &ga::set_fitness($genome, $NULL);

    #
    # 2) For each gene in the genome, initialize it to NULL (start with a clean slate)
    #
    for(my $gene = 0; $gene < $ga::genome_length; $gene++) 
    {
	&ga::set_gene_type($genome, $gene, $NULL);
	&ga::set_gene_value($genome, $gene, $NULL);
    }

    #
    # 3) Now that the individual genome is prepped, we can activate specific genes
    #
    for(my $gene = 0; $gene < $ga::genome_length; $gene++) 
    {
	# We need to randomly decide whether or not to use this particular gene
	if(rand(1) > $ga::non_coding_prob) 
	{
	    &ga::init_gene($genome, $gene);
	    $debug_str .= &ga::get_gene_type($genome, $gene);
	}
	else 
	{
	    $debug_str .= $NONCODING_TYPE;
	}
    }

    # Now that the genome is initialized, we can use the debugging string
    &ga::printd("$debug_str\n");
}



#
# INIT_GENE - This function initializes one specific gene.
#
#  args:    genome index, gene index
#  returns: nothing
#
#  NOTE: Other than init(), this is the only initializer function
#   that needs to know about the hardware mode.
#
sub init_gene()
{
    my $genome = $_[0];
    my $gene   = $_[1];
    my $type   = $NULL;
    my $value  = $NULL;


    # 1) Choose a random connection type for the gene: this particular
    #    step is hardware sensitive -- for the EAC, the genome is encoded
    #    linearly; for the uEAC and simulator, the connections are random
    if($ga::hardware_layout eq $hardware::LINEAR_LAYOUT) 
    {
	$type = &ga::get_connection_type_by_index($gene);
    }
    elsif($ga::hardware_layout eq $hardware::GRID_LAYOUT) 
    {
	$type = &ga::get_random_connection_type();
    }
    else
    {
	&crash('E_UNSUPPORTED_LAYOUT', 'ga::init_gene()', $ga::hardware_layout);
    }


    # 2) Now check whether we should randomly initialize the connection
    #    right now, or if we should wait until later (in the fitness function)
    if($ga::use_gene_values eq $TRUE)
    {
	# FIXME:  here we have to worry about LLA src/snk points, this isn't handled right now
#	$value = &ga::get_random_value($type);
    }
    else
    {
	# The value is already initialized to NULL, do nothing
    }


    # 3) Finally, encode the type/value pair
    &ga::set_gene_type($genome, $gene, $type);
    &ga::set_gene_value($genome, $gene, $value);
}









# ---------- GENERATION-LEVEL FUNCTIONS ---------------



#
#
#
#
#
sub breed_new_generation() 
{
    # Prevailing method:
    #   1) Select elites
    #   2) Copy elites to temp
    #   3) Breed
    #        - 1) with crossover
    #        - 2) or simply select more elites
    #   4) Mutate
    #   5) Copy mutants to temp
    #   6) Activate temp (temp -> population)

    # New method:
    #   1) Breed
    #        - 1) select elites, crossover remainder
    #        - 2) simply select via tournament selection
    #   2) Mutate (straight into temp)
    #   3) Activate temp

    for(my $genome = 0; $genome < $ga::population_size; $genome++) 
    {
	&ga::printg("Select elites, tournament select mates, cross, mutate.\n");
    }

}



#
# EVALUATE_POPULATION - Sends each genome to the fitness
#  function for evaluation.
#
#  args:    none
#  returns: nothing
#
sub evaluate_population() 
{
    for(my $genome = 0; $genome < $ga::population_size; $genome++) 
    {
	&ga::printf("Evaluating configuration " . ($genome + $ga::feedback_adjustment) . 
		    "/$ga::population_size on \'$ga::eac\'...\n");

	my $fitness = &fitness::evaluate_genome($genome);
#	my $fitness = rand(1);
	&ga::set_fitness($genome, $fitness);

    }
}







# =============== GENOME-LEVEL FUNCTIONS ===============



#
# GET_BEST_GENOME - Checks the fitness of each genome, returning
#  the index of the best genome.
#
#  args:    none
#  returns: index of the best genome
#
sub get_best_genome() 
{
    my $best_fitness = -10000;
    my $best_genome  =  $NULL;
    my $fitness      =  $NULL;

    for(my $i = 0; $i < $ga::population_size; $i++) 
    {
	$fitness = &ga::get_fitness($i);

	if($fitness > $best_fitness)
	{
	    &printd("ga::get_best_genome(): Best fitness is " . sprintf($fitness_mask, $fitness) .
		    ", found at index $i (previous best was " . sprintf($fitness_mask, $best_fitness) . ").\n");

	    $best_fitness = $fitness;
	    $best_genome  = $i;
	}
    }

    return $best_genome;
}







# =============== GENE-LEVEL FUNCTIONS ===============

#
# GET/SET_* - These functions set various parts of the genome.
#  Perl does not support 2D arrays, so instead we are using
#  an associative array to store the genome in bits and
#  pieces.  Refer to the NOTES in the header for more details.
#
# The index into the population array is somewhat polymorphic,
#  its meaning is given by its suffix -- here we want to attach
#  a specific suffix so we can get at the various bits of the
#  genome.  It's kind of weird, but then, so am I.  So there.
#
# TODO: implement error checking here, to reduce the amount of
#  error checking that needs to be done in other callers
#



#
# 1) Fitness controls
#
sub get_fitness()
{
    my $genome  = $_[0];
    my $index   = $genome . $ga::FITNESS_SUFFIX;

    # read fitness and return
    my $fitness = $ga::population{$index};
    &printdg("ga::get_fitness(): Retrieved fitness score of $fitness for genome $genome.\n");
    return $fitness;
}

sub set_fitness() 
{
    my $genome  = $_[0];
    my $fitness = $_[1];
    my $index   = $genome . $ga::FITNESS_SUFFIX;

    # write fitness
    $ga::population{$index} = $fitness;
    &printdg("ga::set_fitness(): fitness trace at index $index is $fitness:$ga::population{$index}.\n");
}



# 
# 2) Gene type controls
#
sub get_gene_type()
{
    my $genome = $_[0];
    my $gene   = $_[1];
    my $index  = $genome . $ga::GENETYPE_SUFFIX;

    # read the gene's type 
    my $type   = $ga::population{$index}[$gene];

    # convert NULL gene types to NONCODING
    if($type eq $NULL)
    {
	return $ga::NONCODING_TYPE;
    }
    else
    {
	return $type;
    }
}

sub set_gene_type() 
{
    my $genome = $_[0];
    my $gene   = $_[1];
    my $type   = $_[2];
    my $index  = $genome . $ga::GENETYPE_SUFFIX;

    # write the gene's type
    $ga::population{$index}[$gene] = $type;
    &printdg("ga::set_gene_type(): type trace at index $index is $type:$ga::population{$index}[$gene].\n");
}



#
# 3) Gene value controls
#
# TODO: this should check for null values, and translate
#
sub get_gene_value() 
{
    my $genome = $_[0];
    my $gene   = $_[1];
    my $value  = $_[2];
    my $index  = $genome . $ga::GENEVALUE_SUFFIX;

    # read the gene's value and return
    my $type   = $ga::population{$index}[$genome];
    return $type;
}

sub set_gene_value() 
{
    my $genome = $_[0];
    my $gene   = $_[1];
    my $value  = $_[2];
    my $index  = $genome . $ga::GENEVALUE_SUFFIX;

    # write the gene's value
    $ga::population{$index}[$gene] = $value;
    &printdg("ga::set_gene_value(): value trace at index $index is $value:$ga::population{$index}[$gene].\n");
}







# =============== MISCELLANEOUS FUNCTIONS ===============

#
# Miscellaneous other stuff, useful in specific contexts.
#



# --------------- HELPER FUNCTIONS ---------------



#
# GET_CONNECTION_TYPE_BY_INDEX - Given a gene index, return
#  the connection type for linear genomes (generally used by
#  genome_init()).
#
#  args:    gene index
#  returns: connection type
#
sub get_connection_type_by_index() 
{
    my $index = $_[0];
    my $type  = $NULL;

    # Compute some important places in the genome
    my $sources_start = 0;
    my $sinks_start   = $ga::max_sources;
    my $llas_start    = $ga::max_sources + $ga::max_sinks;
    my $genome_end    = $ga::max_sources + $ga::max_sinks + $ga::max_llas;

    if(($sources_start <= $index) && ($index < $sinks_start))
    {
	$type = $ga::SOURCE_TYPE;
    }
    elsif(($sinks_start <= $index) && ($index < $llas_start))
    {
	$type = $ga::SINK_TYPE;
    }
    elsif(($llas_start <= $index) && ($index < $genome_end))
    {
	$type = $ga::LLA_IN_TYPE;
    }
    else
    {
	&crash('E_GENE_OUT_OF_BOUNDS', 'ga::get_connection_type_by_index()', $index);
    }

    &printd("ga::get_connection_type_by_index(): Index $index corresponds to type $type.\n");
    return $type;
}



#
#
#
#
#
sub get_random_connection_type() 
{

    # this'n just picks a connection at random

    return '*';
}



# --------------- DATA FORMATTING FUNCTIONS ---------------

#
# GET_PRINTABLE_GENOME - 
#
#  args:    genome
#  returns: printable genome string
#
#  NOTE: This function is hardware dependent.
#  TODO: ga-v2 flag support -- connection string, genome string, etc.
#
sub get_printable_genome() 
{
    my $genome = $_[0];
    my $string = '';

    # 
    if($ga::hardware_layout eq $hardware::LINEAR_LAYOUT)
    {
	$string = &get_linear_genome_string($genome);
    }
    elsif($ga::hardware_layout eq $hardware::GRID_LAYOUT)
    {
	$string = &get_grid_genome_string($genome);
    }
    else 
    {
	&crash('E_UNSUPPORTED_LAYOUT', 'ga::get_printable_genome()', $ga::hardware_layout);
    }

    return $string;
}



#
#
#
#
#
sub get_linear_genome_string()
{
    my $genome = $_[0];
    my $string = '';
    my $gene   = 0;


    # 1) Sources
    $string .= 'Source indices:  ';
    for(my $i = 0; $i < $ga::max_sources; $i++)
    {
	if(&get_gene_type($genome, $gene) eq $ga::NONCODING_TYPE)
	{
	    # Ignore noncoding genes
	}
	elsif($ga::use_gene_values eq $FALSE)
	{
	    $string .= ($i + $feedback_adjustment) . ' ';
	}
	else
	{
#	    $string .= ($i + $feedback_adjustment) . ' (v=' . &ga::get_gene_value($genome, $gene) . ')  ';
	}

	$gene++;
    }
    $string .= "\n";


    # 2) Sinks
    $string .= 'Sink indices:    ';
    for(my $i = 0; $i < $ga::max_sinks; $i++) 
    {
	if(&get_gene_type($genome, $gene) eq $ga::NONCODING_TYPE)
	{
	    # Ignore noncoding genes
	}
	elsif($ga::use_gene_values eq $FALSE)
	{
	    $string .= ($i + $feedback_adjustment) . ' ';
	}
	else
	{
#	    $string .= ($i + $feedback_adjustment) . '(' . &ga::get_gene_value($genome, $gene) . ')  ';
	}

	$gene++;
    }
    $string .= "\n";


    # 3) LLAs
    $string .= 'LLA indices:     ';
    for(my $i = 0; $i < $ga::max_llas; $i++)
    {
	if(&get_gene_type($genome, $gene) eq $ga::NONCODING_TYPE)
	{
	    # Ignore noncoding genes
	}
	elsif($ga::use_gene_values eq $FALSE)
	{
	    $string .= ($i + $feedback_adjustment) . ' ';
	}
	else
	{
#	    $string .= ($i + $feedback_adjustment) . '(f=' . &ga::get_gene_value($genome, $gene) . ')  ';
	}

	$gene++;
    }
    $string .= "\n";


    # All done!
    return $string;
}



#
#
#
#
#
sub get_grid_genome_string()
{
    my $genome = $_[0];
    my $string = '';

    return $string;
}

#     # Hardware version 2 encoding
#     else {
# 	for(my $i = 0; $i < $genome_length; $i++) {
# 	    $type  = &get_type($population{$index}[$i]);
# 	    $value = &get_value($population{$index}[$i]);

# 	    # Add row labels (and linebreaks after the first row)
# 	    $str = '';
# 	    if(($i % $num_rows) eq 0) {
# 		if($i > 0) { $gene_string .= "\n"; }
# 		$gene_string .= "Row " . (int($i / $num_rows) + 1) . ":   ";
# 	    }

# 	    # Compute the maximum column width
# 	    my $max_col_width = 5 + length(sprintf($current_precision, 1));

# 	    # Clean up NULL connections
# 	    if($type eq $NULL) {
# 		$type = $noncoding_symbol;
# 		for(my $j = 0; $j < $max_col_width; $j++) {
# 		    $str .= $noncoding_symbol;
# 		}
# 	    }

# 	    # Format sources and sinks with their current value
# 	    elsif($type eq $SOURCE || $type eq $SINK) {
# 		$str = "$type, $value";
# 	    }

# 	    # Format LLAs with their function
# 	    elsif($type eq $LLA_IN) {
# 		$str = "$type, f=$value";
# 	    }

# 	    # Format LLA_SRCs and LLA_SNKs with their parent LLA
# 	    elsif($type eq $LLA_SRC || $type eq $LLA_SNK) {
# 		$value = &decode_position($value);
# 		$str = "$type ($value)";
# 	    }

# 	    # Add extra spacing to narrow columns
# 	    my $len = length($str);
# 	    for(my $j = 0; $j < ($max_col_width - $len); $j++) {
# 		$str .= ' ';
# 	    }

# 	    $type_string .= $type;
# 	    $gene_string .= "$str   ";
# 	}
#     }

#     # Build the final string, depending on we were called
#     if($flag eq $GET_GENOME) {
# 	$string = $gene_string . "\n";
#     }
#     elsif($flag eq $GET_CONNECTION_STRING) {
#        	$string .= $type_string;
#     }
#     else {
# 	&crash("get_string(): Unrecognized flag recieved ($flag).\n");
#     }

#     # Return the final string
#     return $string;
# }







# =============== UTILITY FUNCTIONS ===============



#
# CRASH - A *slight* improvement on 'die'.
#
#  args:    error code, originating function, details
#  returns: nothing
#
#  TODO: Send output to stderr
#
sub crash()
{
    my $flag       = $_[0];
    my $originator = $_[1];
    my $details    = $_[2];

    print("\n");
    print("ERROR: $ga::error_table{$flag}.\n");
    print(" Error flag:\t$flag.\n");
    print(" Originator:\t$originator.\n");
    print(" Details:\t$details\n");
    print("\n");
    die("Stopping");
}



#
# GET_RUNNING_TIME - Returns the time the GA has been
#  running, in seconds, assuming init() has been called.
#
# args:    none
# returns: running time in seconds
#
sub get_running_time() 
{
    $ga::ga_end_time = time;
    return ($ga::ga_end_time - $ga::ga_start_time);
}



#
# PRINT* - These functions allow some control over 
#  output by providing different print functions for
#  use in different contexts.
#
# args:    print-formatted string
# returns: nothing
#

# General-level debugging
sub printd() 
{
    if($ga::DEBUG_ON eq $TRUE) 
    {
	&printf($_[0]);
    }
}

# Genome-level debugging (output-intensive)
sub printdg()
{
    if($ga::DEBUG_GENOME_ON eq $TRUE)
    {
	&printf($_[0]);
    }
}

# Detailed GA feedback
sub printg() 
{
    if($ga::VERBOSE_ON eq $TRUE) 
    {
	&printf($_[0]);
    }
}

# General GA feedback (disable this for silent running)
sub printf() 
{
    if($ga::FEEDBACK_ON eq $TRUE) 
    {
	print($_[0]);
    }
}
