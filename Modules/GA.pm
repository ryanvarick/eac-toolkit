#
# GA.PM - A genetic alogorithm designed to evolve configurations
#  for the extended analog computer.
#
#
# Copyright (C) 2006 Ryan R. Varick <toolkit@ryanvarick.com>
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of
# the License, or (at your option) any later version.
#
#

package GA;

use diagnostics;
use strict;
use warnings;

use fitness;                       # user-defined fitness functions

Toolkit::load_module("Math::NumberCruncher");

# use Math::NumberCruncher;          # CPAN statistic module (TODO: Autoload this)



# ====================[ CONFIGURATION ]====================

use constant TRUE  => (1 == 1);
use constant FALSE => (0 == 1);
use constant NULL  => -1;

our $VERSION       =  '3.0.0';
our $DEBUG_ON      =  FALSE;

#
# NOTE: I'm using 'our' for most of these variables because, with
#  a module this large, I think it is clearer to reference globals
#  as $GA::variable_name than to try to determine scope otherwise.
#

# feedback control
our $VERBOSE_ON        = TRUE;   # TODO: daisy-chain on top of interface::printf()
                                 # TODO: is this option necessary?
our $DEBUG_BREEDING_ON = FALSE;  # DEPRICATED (TODO: consolidate into printd())
our $DEBUG_GENOME_ON   = FALSE;

our $ONE_BASED_FEEDBACK_ON = TRUE;

# general GA parameters
our $max_generations = 10;
our $population_size = 5;

our $breed_with_elitism              = TRUE;
our $breed_with_crossover            = TRUE;
our $breed_with_mutation             = TRUE;
our $breed_with_tournament_selection = TRUE;

# crossover
our $num_crossover_regions        = 4;

our $use_static_crossover_regions = FALSE;   # TODO: regions -> regions_length (query replace)
our $min_crossover_region_length  = 3;
our $max_crossover_region_length  = 10;

our $require_different_parents    = TRUE;    # disable this to allow same parent for crossover

# mutation
our $mutation_rate       = 0.15;

our $use_noise_mutation  = TRUE;
our $noise_mutation_rate = 0.50;
our $current_noise_scaling_factor = 0.10;

# fitness criteria
our $min_fitness       =   0.0;
our $max_fitness       = 100.0;
our $fitness_threshold = 100.0;
our $fitness_mask      = "%2.1f";

our $num_elites = 3;
our $num_tournament_opponents = 3;

# initialization parameters
our $non_coding_prob  = .50;
our $init_gene_values = FALSE;

# -------------------- INTERNAL constants and flags --------------------

# print flags, used by the genome printers
our $GS_CONN = 'conn';
our $GS_MAP  = 'map';
our $GS_FULL = 'full';

# mutation print flags (noise = lowercase, random = uppercase)
our $NO_MUTATION           = '-';
our $NONCODING_MUTATION    = '?';     # TODO: Audit variable name and usage
our $CURRENT_MUTATION      = 'c';
our $LLA_FUNCTION_MUTATION = 'f';
our $LLA_POSITION_MUTATION = 'p';

# connection type flags
our $SOURCE_TYPE    = 'S';
our $SINK_TYPE      = 'K';
our $LLA_IN_TYPE    = 'L';
our $LLA_SRC_TYPE   = 's';
our $LLA_SNK_TYPE   = 'k';
our $NONCODING_TYPE = '-';

# crossover flags
our $FATHER = 'f';
our $MOTHER = 'm';

# used for gene indexing in the population store
our $FITNESS_SUFFIX   = '-f';
our $GENETYPE_SUFFIX  = '-t';
our $GENEVALUE_SUFFIX = '-v';

# used for gene encoding
our $SEPERATOR = ':';

# used to indicate temporary indices in the population store
#  (negative indices are disallowed when strict refs is active)
our $TEMP_DELIMITER       = 'T';
our $TEMP_POPULATION_BASE = -1;

our $crossover_region_length;
our $feedback_adjustment;
our %population;

# used for complex debugging (like a global register)
our $debug_string;

# ====================[ END CONFIGURATION ]====================







#
# GA_RUN - This function oversees the exectution of the GA.
#
#  args:    none
#  returns: status:
#             integer = index of the genome
#             false   = none found
#             null    = error
#
sub run() 
{
    GA::printv("\n");
    GA::printv("Initializing the genetic algorithm...\n");

    my $init_ok = GA::init();
    unless($init_ok eq TRUE)
    {
	Toolkit::printf("There is no active EAC driver, exiting.\n");
	return NULL;
    }

    GA::printv("Randomly initializing the first population...\n");
    GA::init_population();

    my $generation = 1;
    my $suitable   = NULL;
    LOOP:
      {
	  Toolkit::printf("\n");
	  Toolkit::printf("=============== EVALUATING GENERATION $generation/$GA::max_generations ===============\n\n");

	  my($best_genome, $best_fitness) = GA::evaluate_population();
	  my $report                      = GA::get_generation_statistics($generation);

	  # check the fitness threshold
	  Toolkit::printd("\n", 0);
	  if($best_fitness >= $GA::fitness_threshold)
	  {
	      $suitable = $best_genome;
	      Toolkit::stop_timer();

	      Toolkit::printf("-------------- FITNESS THRESHOLD SATISFIED --------------\n");
	      Toolkit::printf("\n");
	      Toolkit::printf($report);
	      Toolkit::printf("\n");
	      Toolkit::printf("Suitable genome found at index " . ($best_genome + $GA::feedback_adjustment) . 
			      "; fitness is $best_fitness:\n");
	      Toolkit::printf("\n");
	      Toolkit::printf(GA::get_genome_string($best_genome));
	      Toolkit::printf("\n");
	      last LOOP;
	  }
	  else
	  {
	      Toolkit::printf("------------ FITNESS THRESHOLD NOT SATISFIED ------------\n");
	      Toolkit::printf("\n");
	      Toolkit::printf($report);
	      Toolkit::printf("\n");
	      Toolkit::printf("Best genome so far is at index " . ($best_genome + $GA::feedback_adjustment) . 
			      "; fitness is $best_fitness:\n");
	      Toolkit::printf("\n");
	      Toolkit::printf(GA::get_genome_string($best_genome));
	      Toolkit::printf("\n");
	  }

	  if(++$generation <= $GA::max_generations)
	  {
	      GA::printv("-------------- BREEDING NEW GENERATION $generation/$GA::max_generations --------------\n\n");
	      GA::breed_new_generation();
	      redo LOOP;
	  }
	  else
	  {
	      Toolkit::printf("No suitable genomes were found.\n");
	      Toolkit::stop_timer();
	      last LOOP;
	  }
      }

    Toolkit::printf("Genetic algorithm completed in " . Toolkit::get_elapsed_time() . " seconds.\n");
    return $suitable;
}







# --------------------[ Initialization ]--------------------
#
# These functions are called, sometimes indirectly, by the 
#  overseer function, run().  They are used primarily to
#   initialize the first generation.
#



#
# INIT - Initialize the GA.
#
#  args:    none
#  returns: status (ok = true, error = false)
#
sub init() 
{
    # check the driver mode
    if($Driver::driver eq $Driver::NULL_DRIVER) { return FALSE; }

    Toolkit::printd("Starting the timer, current UNIX time is " . Toolkit::start_timer() . ".\n");

    # check that the hardware is properly initialized
    unless(defined $Driver::hardware_layout && defined $Driver::genome_length)
    {
	Toolkit::crash('E_BAD_HARDWARE_MODE');
    }

    # describe the hardware mode (for debugging mode only)
    Toolkit::printd("EAC driver mode is '$Driver::driver'.\n");
    Toolkit::printd("Active EAC is '$Driver::eac'.\n");
    Toolkit::printd("Genome connection layout is '$Driver::hardware_layout'.\n");
    Toolkit::printd("EAC parameters: min_current=$Driver::min_current, max_current=$Driver::max_current, " . 
		"min_lla=$Driver::min_lla_function, max_lla=$Driver::max_lla_function\n");
    Toolkit::printd("Genome length is $Driver::genome_length.\n");

    # configure crossover
    if($GA::use_static_crossover_regions eq TRUE)
    {
	# TODO: verify that this is a proper integer
	$GA::crossover_region_length = ($Driver::genome_length / $GA::num_crossover_regions);
	Toolkit::printd("Using static crossover regions, length is $GA::crossover_region_length.\n");
    }
    else
    {
	# TODO: sanity check variable region lengths here
	Toolkit::printd("Using $GA::num_crossover_regions crossover regions, " .
		    "variable region lengths (min=$GA::min_crossover_region_length, max=$GA::max_crossover_region_length)\n");
    }

    # more debugging information
    Toolkit::printd("Initial gene non-coding probability is $GA::non_coding_prob.\n");
    Toolkit::printd("Mutation rate is $GA::mutation_rate.\n");

    # Determine whether output is 0- or 1-based
    if($GA::ONE_BASED_FEEDBACK_ON eq TRUE) { $GA::feedback_adjustment = 1; }
    else { $GA::feedback_adjustment = 0; }
    Toolkit::printd("Feedback adjustment is +$GA::feedback_adjustment.\n");
    Toolkit::printd("\n", 0);

    return TRUE;
}



#
# INIT_POPULATION - Initialize each genome in the population.
#
#  args:    none
#  returns: nothing
#
sub init_population() 
{
    for(my $genome = 0; $genome < $GA::population_size; $genome++) 
    {
	Toolkit::printd("Generating initial genome " . ($genome + $GA::feedback_adjustment) . "/$population_size...\n");
	&GA::init_genome($genome);

	# Visually verify genome initialization if debugging is enabled
	if($GA::DEBUG_ON eq TRUE)
	{
	    Toolkit::printd(GA::get_genome_string($genome) . "\n", 0);
	}
    }

    # The NULLth key is the pointer for the temp. population
    $GA::population{NULL} = $GA::TEMP_POPULATION_BASE;
}



#
# INIT_GENOME - Intialize the genes of a particular genome.
#
#  args:    index of a genome to initialize
#  returns: nothing
#
sub init_genome() 
{
    my $genome = $_[0];

    # NOTE: To debug genome initialization, the connection string is built up
    #  dynamically here, to be (optionally) printed afterward (see below)
    $GA::debug_string = 'Connection string is:  ';

    #
    # 1) Set the genome's fitness score to NULL
    #
    &GA::set_fitness($genome, NULL);

    #
    # 2) For each gene in the genome, initialize it to NULL (start with a clean slate)
    #
    for(my $gene = 0; $gene < $Driver::genome_length; $gene++) 
    {
	&GA::set_gene_type($genome, $gene, NULL);
	&GA::set_gene_value($genome, $gene, NULL);
    }

    #
    # 3) Now that the individual genome is prepped, we can activate specific genes
    #
    for(my $gene = 0; $gene < $Driver::genome_length; $gene++) 
    {
	# We need to randomly decide whether or not to use this particular gene
	if(rand(1) > $GA::non_coding_prob) 
	{
	    &GA::init_gene($genome, $gene);
	    $GA::debug_string .= &GA::get_gene_type($genome, $gene);
	}
	else 
	{
	    $GA::debug_string .= $NONCODING_TYPE;
	}
    }

    # Now that the genome is initialized, we can use the debugging string
    Toolkit::printd($GA::debug_string . "\n");
    &GA::reset_debug_string();
}



#
# INIT_GENE - Initialize a specific gene.
#
#  args:    genome index, gene index
#  returns: nothing
#
#  NOTE: This function is hardware-aware.
#
sub init_gene()
{
    my $genome = $_[0];
    my $gene   = $_[1];
    my $type   = NULL;
    my $value  = NULL;


    #
    # 1) Choose a random connection type for the gene: this particular
    #    step is hardware sensitive -- for the EAC, the genome is encoded
    #    linearly; for the uEAC and simulator, the connections are random
    #
    if($Driver::hardware_layout eq $Driver::FIXED_LAYOUT) 
    {
	$type = &GA::get_connection_type_by_index($gene);
    }
    elsif($Driver::hardware_layout eq $Driver::FREE_LAYOUT)
    {
	$type = &GA::get_random_connection_type();
    }
    else
    {
	Toolkit::crash('E_UNSUPPORTED_LAYOUT', $Driver::hardware_layout);
    }


    #
    # 2) Now check whether we should randomly initialize the connection
    #    right now, or if we should wait until later (in the fitness function)
    #
    if($GA::init_gene_values eq TRUE)
    {
	# FIXME:  here we have to worry about LLA src/snk points, this isn't handled right now
#	$value = &GA::get_random_value($type);
    }
    else
    {
	# The value is already initialized to NULL, do nothing
    }


    #
    # 3) Finally, encode the type/value pair
    #
    &GA::set_gene_type($genome, $gene, $type);
    &GA::set_gene_value($genome, $gene, $value);
}









# ====================[ GENERATION-LEVEL FUNCTIONS ]====================



#
# ACTIVATE_NEW_GENERATION - Copies the genomes from the temporary
#  population to the active population
#
#  args:    none
#  returns: nothing
#
sub activate_new_generation()
{
    for(my $i = 0; $i < $GA::population_size; $i++)
    {
	# Translate the index into the tempoary population
	my $base   = $GA::TEMP_POPULATION_BASE - $i;
	my $index  = $GA::TEMP_DELIMITER . $base;

	&GA::printdb("GA::activate_new_population(): Copying child genome from temporary index [$index] to index [$i].\n");

	my @genome = &GA::get_genome($index);
	
	for(my $gene = 0; $gene < $Driver::genome_length; $gene++)
	{
	    &GA::printdb("GA::activate_new_population(): Gene $gene is [$genome[$gene]].\n");
	    my ($gene_type, $gene_value) = &GA::unpack_gene($genome[$gene]);
	    
	    &GA::set_gene_type($i, $gene, $gene_type);
	    &GA::set_gene_value($i, $gene, $gene_value);
	}
    }

    # reset temp population pointer
    $GA::population{NULL} = $GA::TEMP_POPULATION_BASE;
}



#
# BREED_NEW_GENERATION - Breeds a new generation of genomes from
#  the current population.
#
#  args:    none
#  returns: nothing
#
sub breed_new_generation() 
{

    # Save elites, if enabled
    if($GA::breed_with_elitism eq TRUE)
    {
	my @elites = &GA::get_elites($GA::num_elites);

	#
	# Copy elites to the temporary population --
	#
	#  NOTE: It is wasteful to copy unchanged genomes, but it is easier
	#        to track members of the new population this way
	#
	foreach my $elite_index (@elites)
	{
	    &GA::printdb("GA::breed_new_generation(): Saving elite at index [$elite_index]...\n");
	    my @genome = &GA::get_genome($elite_index);
	    &GA::copy_to_temp(@genome);
	    &GA::printdg("\n");
	}

	&GA::printdb("\n");
	GA::printv("Saved $GA::num_elites elites.\n\n");
    }

    # Breed the rest of the population
    for(my $i = $GA::num_elites; $i < $GA::population_size; $i++) 
    {
	my @child;
	my $genome_address;

	&GA::printdb("GA::breed_new_generation(): ");
	GA::printv("Breeding new genome " . ($i + 1) . " (crossover regions = " .
		    "$GA::num_crossover_regions, mutation rate = $GA::mutation_rate):\n");


	# Apply crossover, if enabled
	if($GA::breed_with_crossover eq TRUE)
	{
	    @child = &GA::breed_with_crossover();
	}

	# Otherwise, use (tournament) selection
	else
	{
	    @child = &GA::get_genome(&GA::select_random_genome());
	}
	

	# Apply mutation, if enabled
	if($GA::breed_with_mutation eq TRUE)
	{
	    @child = &GA::mutate_genome(@child);
	}
	

	# Save child and print diagnostic information
	$genome_address = &GA::copy_to_temp(@child);
	GA::printv(" Resultant genome after applying breeding: \t" . &GA::get_connection_string($genome_address) . "\n");
	GA::printv("\n");
    }

    # Activate the new population 
    &GA::activate_new_generation();
    GA::printv("Breeding complete.\n\n");
}



#
# EVALUATE_POPULATION - Evaluate each genome against the fitness function.
#
#  args:    none
#  returns: nothing
#
sub evaluate_population() 
{
    my $best_fitness = NULL;
    my $best_genome  = NULL;

    for(my $genome = 0; $genome < $GA::population_size; $genome++) 
    {
	Toolkit::printf("Evaluating configuration " . ($genome + $GA::feedback_adjustment) . 
		    "/$GA::population_size on '$Driver::eac'...\n");
	GA::printv("  Connection string is: \t" . &GA::get_connection_string($genome) . "\n");

	my $fitness = &fitness::evaluate_genome($genome);
	&GA::set_fitness($genome, $fitness);
	GA::printv("  Fitness is $fitness.\n\n");

	if($fitness > $best_fitness) 
	{ 
	    $best_fitness = $fitness; 
	    $best_genome  = $genome;
	}

#	my $location = &Logger::log_genome($genome);
#	GA::printv("  Genome saved to $location.\n");
    }

    return $best_genome, $best_fitness;
}



#
# GET_ELITES - Returns the indices of the top genomes, sorted by fitness.
#
#  args:    none
#  returns: sorted array of elite indices
#
sub get_elites()
{
    my (@elites, @genomes);
    my %backtrack;
    my $fitness;

    # 1) Get all the fitness scores
    for(my $i = 0; $i < $GA::population_size; $i++)
    {
	# Get the individual genome fitness
	$fitness = &GA::get_fitness($i);

	# Put it in a sequential array for sorting
	$genomes[$i] = $fitness;

	# And make it a key in the backtracking hash so we can get
	#  the original index back later
	$backtrack{$fitness} = $i;
    }

    # 2) Sort the fitness scores
    @genomes = sort {$b <=> $a} @genomes;
    &GA::printdb("GA::get_elites(): Raw fitness scores in descending order: @genomes\n");

    # 3) Return the top elites
    &GA::printdb("GA::get_elites(): ");
    &GA::printdb("Top $GA::num_elites genomes by fitness are at indices ");
    for(my $i = 0; $i < $GA::num_elites; $i++)
    {
	# Get the elite index out of the backtrack hash (see above)
	$elites[$i] = $backtrack{$genomes[$i]};
	&GA::printdb("($elites[$i], f=$genomes[$i]) ");
    }
    &GA::printdb("\n");

    # Return the elites
    return @elites;
}



#
# GET_GENERATION_STATISTICS - Prepares general statistics about the
#  current generation.
#
#  args:    none
#  returns: index of the fittest genome, 
#           index of the least fit genome,
#           average fitness of the population
#
sub get_generation_statistics() 
{
    my $generation    = $_[0];
    my $best_fitness  = NULL;
    my $best_genome   = 0;
    my $worst_fitness = $GA::max_fitness + 1;
    my $worst_genome  = 0;
    my @scores;

    # Build the array of fitness scores, look for best and worst genomes
    for(my $i = 0; $i < $GA::population_size; $i++)
    {
	my $fitness = &GA::get_fitness($i);
	$scores[$i] = $fitness;

	if($fitness > $best_fitness)
	{
	    Toolkit::printd("New fitness maxima found at index" . ($i + $GA::feedback_adjustment) . 
			    " (p = $best_fitness, n = $fitness).\n");

	    $best_fitness = $fitness;
	    $best_genome  = $i;
	}

	if($fitness < $worst_fitness)
	{
	    Toolkit::printd("New fitness minima found at index " . ($i + $GA::feedback_adjustment) . 
			    " (p = $worst_fitness, n = $fitness).\n");

	    $worst_fitness = $fitness;
	    $worst_genome  = $i;
	}
    }

    # Some more advanced stats (TODO: abort if stdv = NaN)
    my $mean = &Math::NumberCruncher::Mean(\@scores);
    my $stdv = &Math::NumberCruncher::StandardDeviation(\@scores, 1);
    my $var  = &Math::NumberCruncher::Variance(\@scores, 1);

    # Now package up the report
    my $report = '';

    $report .= "Statistics for generation $generation/$GA::max_generations:\n";
    $report .= "\n";
    $report .= "  best_fitness:  $best_fitness, index=" . ($best_genome + $GA::feedback_adjustment) . "\n";
    $report .= "  worst_fitness: $worst_fitness, index=" . ($worst_genome + $GA::feedback_adjustment) . "\n";
    $report .= "  mean_fitness:  " . sprintf($GA::fitness_mask, $mean) . "\n";
    $report .= "  threshold:     " . sprintf($GA::fitness_mask, $GA::fitness_threshold) . "\n";
    $report .= "  std_deviation: $stdv\n";
    $report .= "  variance:      $var\n";

    return $report;
}







# ====================[ GENOME-LEVEL FUNCTIONS ]====================



#
# BREED_WITH_CROSSOVER - Returns the offspring of two parent genomes.
#
#  args:    none
#  returns: genome
#
#  NOTE: The crossover loop tracks four simultaneous variables:
#    - The current donor, take gene from the mother or the father
#    - The number of crossover points (num crossover points)
#    - The placement of the crossover points (min/max region length)
#    - The index of the current donor gene
#
sub breed_with_crossover()
{
    &GA::printdb("GA::breed_with_crossover(): Starting crossover, " . 
		 "using $GA::num_crossover_regions crossover regions.\n");

    # Select two random parents
    my $mother = &GA::select_random_genome();
    my $father;

    do 
    {
	$father = &GA::select_random_genome();
    }
    while(($GA::require_different_parents eq TRUE) && ($father eq $mother));

    my @child;
    my $donor         = $GA::MOTHER;
    my $region_length = 0;
    my $genes_used    = 0;

    &GA::printdb("GA::breed_with_crossover(): Mother is at index $mother, father is at index $father.\n");


    # Loop over the entire genome
    for(my $i = 1; $i <= $GA::num_crossover_regions; $i++)
    {

	# ---------------[ Determine crossover region ]---------------

	#
	# NOTE: We can't just zip through the entire genome at once, we 
	#       have to track crossover region.  To do that, we use a gene 
	#       pointer to figure out where we are in the crossover process, 
	#       then we check for some special cases.  An inner for-loop
	#       (below) doesthe actual copy-n-splicing.
	#
	my $genes_left = $Driver::genome_length - $genes_used;

	# Edge case #1: The last crossover region (either static or
	#  variable length) extends to the end of the genome
	if($i eq $GA::num_crossover_regions)
	{
	    $region_length = $genes_left;
	}

	# Edge case #2: Static regions have fixed lengths
	elsif($GA::use_static_crossover_regions eq TRUE)
	{
	    $region_length = $GA::crossover_region_length;
	}

	# Normal case: Variable regions have a random length
	else
	{
	    # Check for two more special cases:
	    #  1) if no genes remain, ignore the rest of the regions
	    #  2) if too few genes remain, use all of them now
	    if($genes_used eq $Driver::genome_length)
	    {
		$region_length = 0;
	    }
	    elsif($genes_left <= $GA::min_crossover_region_length)
	    {
		$region_length = $genes_left;
	    }

	    # Now, if things check out, choose a random length
	    else
	    {
		do
		{
		    $region_length = 
			Toolkit::randint($GA::min_crossover_region_length, $GA::max_crossover_region_length);
		}
		while($region_length > $genes_left);
	    }
	}

	&GA::printdb("GA::breed_with_crossover(): Crossing region $i, donor = $donor; " . 
		     "genes available = $genes_left, region length = $region_length.\n");



	# ---------------[ Splice genes ]---------------

	#
	# Now that we have the region length determined, we copy the
	#  appropriate number of genes from the current parent genome
	#
	for(my $j = 0; $j < $region_length; $j++)
	{
	    my $gene;
	    my $value;
	    my $packed_gene;

	    # Calculate proper offset
	    my $g = $genes_used + $j;

	    # Get the gene
	    if($donor eq $GA::MOTHER) 
	    { 
		$packed_gene = &GA::get_packed_gene($mother, $g);
	    }
	    else 
	    { 
		$packed_gene = &GA::get_packed_gene($father, $g);
	    }
	    
	    # Copy the gene to the child
	    $child[$g] = $packed_gene;

	    &GA::printdb("GA::breed_with_crossover(): Spliced gene at position $g is [$child[$g]]\n");
	}


	# Mark used genes
	$genes_used += $region_length;

	# Toggle donor genomes
	if($donor eq $GA::MOTHER) { $donor = $GA::FATHER; }
	else { $donor = $GA::MOTHER; }
    }


    GA::printv(" Using mother at index $mother (fitness = " . &GA::get_fitness($mother) . 
		"): \t" . &GA::get_connection_string($mother) . "\n");
    GA::printv(" Using father at index $father (fitness = " . &GA::get_fitness($father) . 
		"): \t" . &GA::get_connection_string($father) . "\n");

    return @child;
}



#
# COPY_TO_TEMP - Copies a genome to the 'temporary' population.
#
#  args:    encoded genome
#  returns: location of the stored genome
#
#  NOTE: The temporary population really just piggybacks on the normal
#        population store.  It uses the negatively-indexed side of the
#        store.  We can get away with this since we're using a hash, 
#        but yeah, I'm kind of regretting using Perl right now.  Here's 
#        what the population data structure looks like:
#
#
#  $population{  -n  }         -  child genome n+2
#  $population{ -n+1 }         -  child genome n+1
#  $population{ -n+2 }         -  child genome n
#
#                ...
#
#  $population{NULL}          -  Pointer to the next temp. location (-n - 1)
#
#  $population{ n }            -  genome n
#  $population{ n.FITNESS }    -  fitness for genome n
#  $population{ n+1 }          -  genome n+1
#  $population{ n+1.FITNESS }  -  fitness for genome n+1
#
#               ...
#
sub copy_to_temp()
{
    my @genome = @_;

    #
    # The NULLth key of the hash stores the current copy pointer
    #
    #  NOTE: We can't use negative numbers as keys into a hash with strict refs
    #        enabled, thus the need to concatenate the delimeter onto the base index
    #
    my $base  = $GA::population{NULL};
    my $index = $GA::TEMP_DELIMITER . $base;

    &GA::printdb("copy_to_temp(): Copying genome to index [$index]; ");

    # NOTE: We're multiplying by -1 here because the temp. pop. uses negative indices
    for(my $gene = 0; $gene < $Driver::genome_length; $gene++)
    {
	# Unpack the gene and copy to the temp. population
	my ($gene_type, $gene_value) = &GA::unpack_gene($genome[$gene]);

	&GA::set_gene_type($index, $gene, $gene_type);
	&GA::set_gene_value($index, $gene, $gene_value);
    }

    #
    # (Re)set the fitness --
    #
    #  FIXME: Note that get_genome() encodes the fitness as the last index
    #         of the genome array.  However, we are not currently using that
    #         value because the encapsulation is shaky.  This has the side
    #         effect of breaking fitness caching.  Every genome must be checked.
    #
#    my $gene_fitness = $genome[$Driver::genome_length];
    my $gene_fitness = NULL;
    &GA::set_fitness($index, $gene_fitness);
    &GA::printdb("fitness is $gene_fitness.\n");

    # Decrement the pointer to the nextmost negative slot in the population
    $base--;
    $GA::population{NULL} = $base;

    return $index;
}



#
# GET_GENOME - Returns an encoded copy of a particular genome.
#
#  args:    index of the genome to encode
#  returns: an encoded genome array
#
#  NOTE: The type-value pairs are concatenated and stored in the
#        genome encoding array.  The fitness score is stored in the
#        last array element.
#
sub get_genome() 
{
    my $index = $_[0];
    my @genome;

    # Encode type-value pairs
    for(my $gene = 0; $gene < $Driver::genome_length; $gene++)
    {
	$genome[$gene] = &GA::get_packed_gene($index, $gene);
    }

    # Encode fitness
    $genome[$Driver::genome_length] = 'F' . $GA::SEPERATOR . &GA::get_fitness($index);

    &GA::printdg("GA::get_genome(): Encoding for genome [$index] (len=" . scalar(@genome) . "): @genome.\n");
    return @genome;
}



#
# MUTATE_GENOME - Mutates a genome.
#
#  args:    genome
#  returns: mutated genome
#
sub mutate_genome()
{
    my @genome = @_;
    my @mutated;

    &GA::printdb("GA::mutate_genome(): Starting mutation, mutation rate is $GA::mutation_rate.\n");

    # Process each gene
    for(my $i = 0; $i < $Driver::genome_length; $i++) 
    {
	# Should we mutate?
	if(rand(1) < $GA::mutation_rate)
	{
	    &GA::printdb("GA::mutate_genome(): Applying mutation to gene $...\n");
	    $mutated[$i] = &GA::mutate_packed_gene($genome[$i]);
	}
	else
	{
	    &GA::printdb("GA::mutate_genome(): Ignoring gene $i.\n");
	    $GA::debug_string .= $GA::NO_MUTATION;
	    $mutated[$i] = $genome[$i];
	}
    }

    GA::printv(" Mutation mask to be applied to the genome:\t$GA::debug_string\n");
    &GA::reset_debug_string();

    return @mutated;
}



#
# MUTATE_PACKED_GENE - Mutates an individual gene.
#
#  args:    packed gene
#  returns: packed, mutated gene
#
#  FIXME: We cannot do spontaneous initialization or type
#         changes without breaking hardware independence; even then,
#         we need to know the gene index to properly mutate types.
#         For now, the type is fixed.
#
sub mutate_packed_gene()
{
    my $packed_gene = $_[0];

    &GA::printdb("GA::mutate_packed_gene(): Packed gene to mutate is [$packed_gene]\n");

    my ($gene_type, $gene_value) = &GA::unpack_gene($packed_gene);

    my $mutated_gene;
    my $mutated_gene_type = $gene_type;   # FIXME: ignore the type until the fixme above is resolved
    my $mutated_gene_value;


    #
    # PROCESS MUTATION CASES:
    #

    # (1) Noncoded genes
    if($gene_type eq $GA::NONCODING_TYPE) 
    {
	&GA::printdb("GA::mutate_packed_gene(): Nevermind, gene is not in use.\n");
	$GA::debug_string .= $GA::NONCODING_MUTATION;

	$mutated_gene_type  = $gene_type;
	$mutated_gene_value = $gene_value;
    }

    # (2) Sources and sinks
    elsif($gene_type eq $GA::SOURCE_TYPE || $gene_type eq $GA::SINK_TYPE) 
    {
	&GA::printdb("GA::mutate_packed_gene(): Gene codes for a DAC, mutating its current...\n");
	$mutated_gene_value = &GA::mutate_current($gene_value);
    }

    # (3) LLA input channels
    elsif($gene_type eq $GA::LLA_IN_TYPE)
    {
	&GA::printdb("GA::mutate_packed_gene(): Gene codes for an LLA, mutating its function...\n");
	$mutated_gene_value = &GA::mutate_lla_function($gene_value);
    }

    # (4) LLA source output channels
    elsif($gene_type eq $GA::LLA_SRC_TYPE) 
    {
	# TODO: Add uEAC support
    }

    # (5) LLA sink output channels
    elsif($gene_type eq $GA::LLA_SNK_TYPE) 
    {
	# TODO: Add uEAC support
    }

    else
    {
	Toolkit::crash('E_INVALID_GENE_TYPE', $gene_type);
    }

    # Re-encode and return
    $mutated_gene = &GA::pack_gene($mutated_gene_type, $mutated_gene_value);
    &GA::printdb("GA::mutate_packed_gene(): Packed gene after mutation is [$mutated_gene]\n");
    return $mutated_gene;
}



#
# MUTATE_CURRENT - Mutates a given current.
#
#  args:    current value
#  returns: mutated current value
#
sub mutate_current()
{
    my $current = $_[0];
    my $mutated_current;

    # Noise mutation
    if($GA::use_noise_mutation eq TRUE && rand(1) < $GA::noise_mutation_rate)
    {
	my $noise = &GA::get_random_current() * $GA::current_noise_scaling_factor;

	# Add the noise half the time, subtract it half the time
	#  TODO: Be pedantic, make this Gaussian
	if(rand(1) < 0.5) { $noise *= -1; }
	$mutated_current = sprintf($Driver::current_precision_mask, $current + $noise);

	&GA::printdb("GA::mutate_current(): Noise mutation: adding $noise to $current...\n");
	$GA::debug_string .= lc($GA::CURRENT_MUTATION);
    }
	
    # Random mutation
    else
    {
	$mutated_current = &GA::get_random_current();
	$GA::debug_string .= uc($GA::CURRENT_MUTATION);
    }

    # Check bounds
    if($mutated_current > $Driver::max_current)
    {
	&GA::printdb("GA::mutate_current(): Current is too high, reducing to $Driver::max_current.\n");
	$mutated_current = $Driver::max_current;
    }
    elsif($mutated_current < $Driver::min_current)
    {
	&GA::printdb("GA::mutate_current(): Current is too low, increasing to $Driver::min_current.\n");
	$mutated_current = $Driver::min_current;
    }
    
    &GA::printdb("GA::mutate_current(): Mutated current is $mutated_current.\n");
    return $mutated_current;
}



#
# MUTATE_LLA_FUNCTION - Mutates an LLA function.
#
#  args:    lla function
#  returns: mutated lla function
#
sub mutate_lla_function()
{
    my $function = $_[0];
    my $mutated_function;

    # Noise
    #  FIXME: for now, noise is fixed at +/- 1 function
    if($GA::use_noise_mutation eq TRUE && rand(1) < $GA::noise_mutation_rate)
    {
	$mutated_function = 1;
	if(rand(1) < 0.5) { $mutated_function *= -1; }

	&GA::printdb("GA::mutate_lla_function(): Noise mutation: incrementing LLA function $function by $mutated_function.\n");
	$GA::debug_string .= lc($GA::LLA_FUNCTION_MUTATION);

	$mutated_function += $function;
    }
    else
    {
	$mutated_function = &GA::get_random_lla_function();
	$GA::debug_string .= uc($GA::LLA_FUNCTION_MUTATION);
    }

    # Check bounds
    if($mutated_function > $Driver::max_lla_function)
    {
	&GA::printdb("GA::mutate_lla_function(): Function $mutated_function is out-of-bounds, " . 
		     "reducing to function $Driver::max_lla_function.\n");
	$mutated_function = $Driver::max_lla_function;
    }
    elsif($mutated_function < $Driver::min_lla_function)
    {
	&GA::printdb("GA::mutate_lla_function(): Function $mutated_function is out-of-bounds, " . 
		     "increasing to function $Driver::min_lla_function.\n");
	$mutated_function = $Driver::min_lla_function;
    }
    
    &GA::printdb("GA::mutate_lla_function(): New LLA function is $mutated_function.\n");
    return $mutated_function;
}







# ====================[ GENE-LEVEL FUNCTIONS ]====================

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
#  TODO: implement error checking here, to reduce the amount of
#        error checking that needs to be done in other callers
#

#
# 0) Meta functions
#

# gets an encoded gene from an existing genome
sub get_packed_gene()
{
    my $genome = $_[0];
    my $index  = $_[1];

    my $gene_type   = &GA::get_gene_type($genome, $index);
    my $gene_value  = &GA::get_gene_value($genome, $index);
    my $packed_gene = $gene_type . $GA::SEPERATOR . $gene_value;

    &GA::printdg("GA::get_packed_gene(): Packed gene at index [$genome][$index] is [$packed_gene]\n");
    
    return $packed_gene;
}

# packs gene components
sub pack_gene()
{
    my $gene_type  = $_[0];
    my $gene_value = $_[1];
    my $packed_gene = $gene_type . $GA::SEPERATOR . $gene_value;

    &GA::printdg("GA::pack_gene(): Packed type-value pair is [$packed_gene]\n");
    
    return $packed_gene;
}

# unpacks gene components
sub unpack_gene()
{
    my $packed_gene = $_[0];

    my @pieces     = split($GA::SEPERATOR, $packed_gene);
    my $gene_type  = $pieces[0];
    my $gene_value = $pieces[1];

    &GA::printdg("GA::unpack_gene(): Packed gene [$packed_gene] expands to [t=$gene_type, v=$gene_value]\n");
	
    return ($gene_type, $gene_value);
}



#
# 1) Fitness controls
#
sub get_fitness()
{
    my $genome  = $_[0];
    my $index   = $genome . $GA::FITNESS_SUFFIX;

    # read fitness and return
    my $fitness = $GA::population{$index};
    &GA::printdg("GA::get_fitness(): Fitness score for genome at index [$index] is $fitness.\n");
    return $fitness;
}

sub set_fitness() 
{
    my $genome  = $_[0];
    my $fitness = $_[1];
    my $index   = $genome . $GA::FITNESS_SUFFIX;

    # write fitness
    $GA::population{$index} = sprintf($GA::fitness_mask, $fitness);
    &GA::printdg("GA::set_fitness():    Receipt for transaction at index [$index]:\t $fitness:$GA::population{$index}\n");
}



# 
# 2) Gene type controls
#
sub get_gene_type()
{
    my $genome = $_[0];
    my $gene  = $_[1];
    my $index = $genome . $GA::GENETYPE_SUFFIX;

    # read the gene and convert NULL types to NONCODING
    my $type   = NULL;
    my $value = $GA::population{$index}[$gene];

    if($value eq NULL)
    {
	$type = $GA::NONCODING_TYPE;
    }
    else
    {
	$type = $value;
    }

    &GA::printdg("GA::get_gene_type():   Type at index [$genome][$gene] is:\t $type\n");
    return $type;
}

sub set_gene_type() 
{
    my $genome = $_[0];
    my $gene   = $_[1];
    my $type   = $_[2];
    my $index  = $genome . $GA::GENETYPE_SUFFIX;

    # write the gene's type
    $GA::population{$index}[$gene] = $type;
    &GA::printdg("GA::set_gene_type():  Receipt for transaction at index [$index]:\t $type:$GA::population{$index}[$gene]\n");
}



#
# 3) Gene value controls
#
sub get_gene_value() 
{
    my $genome = $_[0];
    my $gene   = $_[1];
    my $index  = $genome . $GA::GENEVALUE_SUFFIX;

    # read the gene's value and return
    my $value  = $GA::population{$index}[$gene];
    &GA::printdg("GA::get_gene_value(): Value at index [$genome][$gene] is:\t $value\n");

    return $value;
}

sub set_gene_value() 
{
    my $genome = $_[0];
    my $gene   = $_[1];
    my $value  = $_[2];
    my $index  = $genome . $GA::GENEVALUE_SUFFIX;

    # write the gene's value
    $GA::population{$index}[$gene] = $value;
    &GA::printdg("GA::set_gene_value(): Receipt for transaction at index [$index]:\t $value:$GA::population{$index}[$gene]\n");
}







# ====================[ OTHER GA FUNCTIONS ]====================



#
# GET_CONNECTION_TYPE_BY_INDEX - Given a gene index, return
#  the connection type for linear genomes (generally used by
#  genome_init()).
#
#  args:    gene index
#  returns: connection type
#
#  NOTE: This routine is hardware-aware (EAC).
#
sub get_connection_type_by_index() 
{
    my $index = $_[0];
    my $type  = NULL;

    # Compute some important places in the genome
    my $sources_start = 0;
    my $sinks_start   = $Driver::max_sources;
    my $llas_start    = $Driver::max_sources + $Driver::max_sinks;
    my $genome_end    = $Driver::max_sources + $Driver::max_sinks + $Driver::max_llas;

    if(($sources_start <= $index) && ($index < $sinks_start))
    {
	$type = $GA::SOURCE_TYPE;
    }
    elsif(($sinks_start <= $index) && ($index < $llas_start))
    {
	$type = $GA::SINK_TYPE;
    }
    elsif(($llas_start <= $index) && ($index < $genome_end))
    {
	$type = $GA::LLA_IN_TYPE;
    }
    else
    {
	Toolkit::crash('E_GENE_OUT_OF_BOUNDS', $index);
    }

    &printdg("GA::get_connection_type_by_index(): Index $index corresponds to type $type.\n");
    return $type;
}



#
# GET_RANDOM_CONNECTION_TYPE - 
#
#  args:    
#  returns: 
#
#  FIXME TODO: in use [?]
#
sub get_random_connection_type() 
{
    # this'n just picks a connection at random (used in nonlinear mode)
    return '*';
}



#
# GET_RANDOM_CURRENT - Returns a random (legal) current value.
#
#  args:    none
#  returns: random current
#
# TODO: should this use the precision mask or return a raw value?
#
sub get_random_current() 
{
    return sprintf($Driver::current_precision_mask, 
		   Toolkit::random($Driver::min_current, $Driver::max_current));
}

#
# GET_RANDOM_LLA_FUNCTION - Returns a random LLA function.
#
#  args:    none
#  returns: random lla function
#
sub get_random_lla_function() 
{
    return Toolkit::randint($Driver::min_lla_function, $Driver::max_lla_function);
}



#
# SELECT_RANDOM_GENOME - Gets a random genome according to the
#  active selection strategy.
#
#  args:    none
#  returns: index of a random genome
#
sub select_random_genome()
{
    # Choose a random genome
    my $candidate = Toolkit::randint(0, ($GA::population_size - 1));

    # If tournament selection is enabled, match against N opponents
    if($GA::breed_with_tournament_selection eq TRUE)
    {
	&GA::printdb("GA::select_random_genome(): Using $GA::num_tournament_opponents matches for tournament selection: ");
	for(my $i = 0; $i < $GA::num_tournament_opponents; $i++)
	{
	    my $challenger = Toolkit::randint(0, ($GA::population_size - 1));
	    &GA::printdb("[$candidate vs. $challenger = ");
	    if(&GA::get_fitness($challenger) > &GA::get_fitness($candidate))
	    {
		$candidate = $challenger;
	    }
	    &GA::printdb("$candidate] ");
	}
	&GA::printdb("-> genome $candidate selected.\n")
    }

    else
    {
	&GA::printdb("GA::select_random_genome(): Tournament selection disabled, returning $candidate.\n");
    }

    return $candidate;
}



# --------------------[ Data formatting ]--------------------



# Convenience functions (wrappers)
sub get_connection_string() { return &GA::get_encoding_string($_[0], $GA::GS_CONN); }
sub get_gene_map_string()   { return &GA::get_encoding_string($_[0], $GA::GS_MAP);  }
sub get_genome_string()     { return &GA::get_encoding_string($_[0], $GA::GS_FULL); }

# Generic function (entry point)
sub get_encoding_string() 
{
    my $genome = $_[0];
    my $flag   = $_[1];
    my ($conn_string, $map_string, $return_string);

    # Get the the string components
    if($Driver::hardware_layout eq $Driver::FIXED_LAYOUT)
    {
	($conn_string, $map_string) = &GA::get_linear_genome_string($genome);
    }
    elsif($Driver::hardware_layout eq $Driver::FREE_LAYOUT)
    {
	($conn_string, $map_string) = &GA::get_grid_genome_string($genome);
    }
    else 
    {
	Toolkit::crash('E_UNSUPPORTED_LAYOUT', $Driver::hardware_layout);
    }

    # Use the flag to determine which parts to return
    if($flag eq $GA::GS_CONN)
    {
	$return_string = $conn_string;
    }
    elsif($flag eq $GA::GS_MAP)
    {
	$return_string = $map_string;
    }
    elsif($flag eq $GA::GS_FULL)
    {
	$return_string = "Connections:\t $conn_string\n$map_string";
    }
    else
    {
	Toolkit::crash('E_UNSUPPORTED_GS_MODE', $flag);
    }

    # Return the appropriate string
    return $return_string;
}

#
# GET_LINEAR_GENOME_STRING - Returns printable information
#  about EAC hardware v1 genomes.
#
#  args:    genome
#  returns: connection string, layout string
#
#  TODO: modify to operate on a genome, rather than an index [?]
#  TODO: handle values
#  TODO: better handle indices
#
#  NOTE: This function is hardware-aware.
#
sub get_linear_genome_string()
{
    my $genome = $_[0];
    my ($conn_string, $map_string);

    my ($type, $value);
    my $print_index = 0;

    my $src_string = "Source indices:\t ";
    my $snk_string = "Sink indices:\t ";
    my $lla_string = "LLA indices:\t ";

    for(my $i = 0; $i < $Driver::genome_length; $i++) 
    {
	# Get the type and value of the current gene
	$type  = &GA::get_gene_type($genome, $i);
	$value = &GA::get_gene_value($genome, $i);
	
	# Append the gene type to the connection string
	$conn_string .= $type;

	# Build up the components that make up the gene map string
	if($type eq $GA::SOURCE_TYPE)
	{
	    $src_string .= "$print_index ";
	}
	elsif($type eq $GA::SINK_TYPE)
	{
	    $snk_string .= "$print_index ";
	}
	elsif($type eq $GA::LLA_IN_TYPE)
	{
	    $lla_string .= "$print_index ";
	}
	elsif($type eq $GA::NONCODING_TYPE)
	{
	    # Ignore
	}
	else 
	{
	    Toolkit::crash('E_INVALID_GENE_TYPE', "index=$i, type=$type");
	}

	# TODO: finish using this
	$print_index++;
    }

    # Assemble the gene map string
    $map_string = "$src_string\n$snk_string\n$lla_string\n";

    # Return the completed strings
    return $conn_string, $map_string;
}



#
# GET_GRID_GENOME_STRING - 
#
#  args:
#  returns:
#
#  FIXME TODO
#
sub get_grid_genome_string()
{
    my $genome = $_[0];
    my $string = 'undefined';

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
# 	    if($type eq NULL) {
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







# ====================[ UTILITY FUNCTIONS ]====================



#
# RESET_DEBUG_STRING - Clears the debugging string.
#
#  args:    none
#  returns: nothing
#
#  NOTE: This method exists as a step toward a future, more complex
#        debugging system
#
sub reset_debug_string()
{
    $GA::debug_string = '';
}



#
# PRINT* - These functions allow some control over output by
#  providing different print functions for use in different contexts.
#
#  args:    print-formatted string
#  returns: nothing
#

# Breeding-level debugging (output-intensive)
sub printdb()
{
    if($GA::DEBUG_BREEDING_ON eq TRUE)
    {
	Toolkit::printf($_[0]);
    }
}

# Genome-level debugging (output-intensive)
sub printdg()
{
    if($GA::DEBUG_GENOME_ON eq TRUE)
    {
	Toolkit::printf($_[0]);
    }
}

# Detailed GA feedback
sub printv() 
{
    if($GA::VERBOSE_ON eq TRUE) 
    {
	Toolkit::printf($_[0]);
    }
}

return TRUE;
