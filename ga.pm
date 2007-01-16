#
# GA.PM - A genetic algorithm for the EAC/uEAC.
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
#  A genetic algorithm to evolve analog configurations.  Candidates
#  are tested against an actual extended analog computer, reducing
#  the amount of time spent modelling on a digital computer.
#
#  The GA supports both the EAC (foam and silicon subtstrates) and
#  the new uEAC available at Indiana University.
#
#  NOTE: This file contains the mechanics of the GA.  The fitness 
#   routines are found in 'fitness.pm'.
#
#   
# ENCODING:  
#  Perl does not have good complex data structure support (namely,
#  two-dimensional arrays), so the encoding system may seem a bit
#  contrived.
#
#  Genomes are stored in an associative array (hash), the
#  %population.  Genomes are indexed sequentially, from zero, like
#  a normal array.  However, since the population is a hash and
#  not an array, accessing things is a bit different.
#
#  The index, and the index plus a fitness tag, are keys into the hash:
#
#  %population = {
#    <id>           =>   <genome>,
#    <id-fitness>   =>   <fitness score> };
#
#  So really, the %population is really a kind of staggered hash-of-
#  arrays / hash-value structure.
#
#  EDIT: Other interesting data can be added to this in the same way.
#
#
# GENOME:
#  The GA supports two versions of the EAC.
#
#  Version 1 features 8 sources, 8 sinks, and 6 configurable LLAs.
#  Version 2 is a 5x5 grid of reconfigurable connection points.
#
#  The two are very different, and difficult to encode together.
#  Version 1 has no concept of position, the connections are simply
#  enumerated, while version 2 enumerates positions and makes no
#  guarentees about what connection will be where.
#
#  Pratically speaking, this means the hardware versions are encoded
#  differently using the same architecture:
#
#  Version 1 encoding:
#    gene[00-07] = current on each source wire
#    gene[08-16] = current on each sink wire
#    gene[17-23] = function of each LLA
#
#  Version 2 encoding:
#    gene[00-24] = connection string at each position on the sheet
#
#       position = connection: ( TYPE   -  VALUE )
#         01-25                   src       mA
#                                 snk       mA
#                               lla-in    function
#                               lla-src  parent lla
#                               lla-snk  parent lla
#
#  Version 1 encodings are fairly straightforward, version 2 encodings
#  are more complicated.  Version 1 encodings are simply index like
#  an array.  Version 2 encodings are key-value pairs encoded as
#  strings, stored in an array, stored inside a hash.  If Perl
#  supported nested arrays, version 2 encodings would look like:
#
#    $population[$genome[$gene[$type]]] = $value;
#
#  Instead, it looks like:
#
#    $population{$genome}[$gene] = "$type-$value";
#
#  This would likely get rather hard to manage manually, which is why
#  there are a number of auxiliarly functions to maintain the
#  abstraction.
#
#
# INITIALIZATION:
#  Initializing the genome can be somewhat confusing.  As said above,
#  hardware v1 has no notion of position, while hardware v2 is
#  exclusively concerned with position.  Abstractly, the procedure
#  to initialize a genome looks like this:
#
#  Hardware v1                Hardware v2
#   1) Use source (1-8)?       1) Use position (1-25)?
#   2) Choose value (mA)       2) Choose type
#                              3) Choose value
#   3) Use sink (1-8)?
#   4) Choose value (mA)
#
#   5) Use LLA (1-6)?
#   6) Choose LLA
#
#  The logic for hardware v1, expressed this way, is more
#  complicated than v2.  However, if we determine the genome
#  length before running the GA (v1=22, v2=25), we can initialize
#  both architectures v2's way.  Hardware v1 becomes:
#
#   1) Use position (1-22)?
#   2) What type should we be using now?
#   3) Choose value
#
#
# PRINTING:
#  printf()  - general feedback
#  printg()  - verbose feedback
#  printgd() - debugging information
#
#  In general, printf() and printg() are used by RUN_GA and top-
#  level GA functions.  Other routines should use printgd().
#  Also, strings sent to printgd() should include a prefix value
#  that indicates from where the debug message is being sent.
#
#
# EFFICIENCY:
#  Perl is a neat language.  I like it for its motto, "there's more
#  than one way to do it."  With that said, I generally prefer
#  verbose, slightly less efficient code to code that I won't be
#  able to decipher in a year.
#
#  There are more efficient ways to do a lot of things here.  But
#  effiency really isn't the goal here, readability is.  Plus,
#  communication with the EAC is the real bottleneck here (I think).
#

require 'config.pm';



# =============== MAIN GENETIC ALGORITHM FUNCTIONS ===============

#
# RUN_GA - The main genetic algorithm loop.
#
#  args: none
#
sub run_ga() {

    &init_ga();

    # Initialize the first generation
    &init_population();

    # Run the GA
    for(my $generation = 0; $generation < $num_generations; $generation++) {

	# The first generation has not been evaluated, do not breed yet
	if($generation > 0) {
	    &breed_new_generation();
	}

	# Evaluate the generation
	#  TODO: Plot fitness
	if(&evaluate_generation() eq $TRUE) { return; };
    }
}

#
# INIT_GA - Perform necessary startup actions for the GA.
#
#  args: none
#
sub init_ga() {

    #
    # Initialize for the EAC (hardware v1)
    #
    if($HARDWARE eq $EACV1) {

	# Check if LLAs are disabled
	unless($use_llas eq $TRUE) { $num_llas = 0; }

	# TODO: These should be globalized or removed
	$source_begin_index = 0;
	$source_end_index   = $source_begin_index + ($num_sources - 1);
	$sink_begin_index   = $source_end_index + 1;
	$sink_end_index     = $sink_begin_index + ($num_sinks - 1);
	$lla_begin_index    = $sink_end_index + 1;
	$lla_end_index      = $lla_begin_index + ($num_llas - 1);

	$genome_length      = $num_sources + $num_sinks + $num_llas;

	&printgd("init_ga(): Using EAC at \'$eac\', protocol is \'$HARDWARE\'.\n");
	&printgd("init_ga(): Source indices: $source_begin_index-$source_end_index, " .
		"Sink indices: $sink_begin_index-$sink_end_index, " .
		"LLA indices: $lla_begin_index-$lla_end_index.\n");
    }

    #
    # Initialize for the uEAC (hardware v2)
    #
    elsif($HARDWARE eq $EACV2) {

	# Check if LLAs are disabled
	unless($use_llas eq $TRUE) { $num_types = 2; }

	$genome_length = $num_rows * $num_cols;
	&printgd("init_ga(): Using EAC at \'$eac\', protocol is \'$HARDWARE\'.\n");
	&printgd("init_ga(): Using hardware version 2.\n");
    }

    # Bounds on the genome
    $genome_begin = 0;
    $genome_end   = $genome_length - 1;

    &printgd("init_ga(): Genome length is $genome_length.\n");
    &printgd("init_ga(): Fitness threshold is $fitness_threshold.\n\n");
}



# =============== GENERATION-LEVEL FUNCTIONS ===============

#
# NOTE: These functions operate on the generational-level; that is,
#  they process across the entire population.
#

#
# INIT_POPULATION - Randomnly initializes the genomes of the population.
#
#  args: none
#
sub init_population() {

    for(my $i = 0; $i < $population_size; $i++) {
	&printgd("init_population(): Generating initial genome " . ($i + 1) . "/$population_size:\n");
	&printgd("init_population(): Non-coding probability is $non_coding_probability, " .
		 "genome length is $genome_length.\n");

	# Initialize the fitness score to NULL
	&set_fitness($i, $NULL);

	# Initialze the genes to NULL (not-encoded)
	for(my $j = 0; $j < $genome_length; $j++) {
	    $population{$i}[$j] = &encode($NULL, $NULL);
	}

	#
	# Now randomly activate and encode the genes; we only want to
	#  generate a new gene when:
	#
	#  1) The non_coding_probability is satisfied (higher values
	#     for this variable drive toward simpler initial species).
	#  2) The current gene is not yet initialized (NULL).  This
	#     is only an issue with LLAs, which may take up more than
	#     one gene, depending on whether their source and/or
	#     sink outputs are applied back to the sheet.
	#
	# That said, only hardware v2 is concerned with where the
	# outputs of the LLAs go.  That is why the random_connection_type
	# function takes an index into the genome.  For hardware v1, we 
	# simply return sources, sinks, and LLAs, in that order.
	#
	for(my $j = 0; $j < $genome_length; $j++) {

	    # Check if the gene is currently coding for something
	    my $encoded = &is_encoded($i, $j);
	    if(rand(1) > $non_coding_probability && $encoded eq $FALSE) {
	  
		# Choose a connection type (see notes above)
		my $type  = &random_connection_type($j);
		my $value = $NULL;
	  
		# Sources and sinks
		if($type eq $SOURCE || $type eq $SINK) {
		    $population{$i}[$j] = &encode($type, &random_current());
		}

		# LLAs (LLA_IN)
		elsif($type eq $LLA_IN) {
		    $population{$i}[$j] = &encode($type, &random_lla());
		}

		# LLA_SRCs and LLA_SNKs (hardware v2 ONLY)
		elsif($type eq $LLA_SRC || $type eq $LLA_SNK) {

		    # First mark the connection as encoding using a placeholder value
		    $population{$i}[$j] = &encode($type, 'PLACEHOLDER');

		    # Choose a random, non-coding position from the rest of the
		    # genome for the LLA_IN connection, if one exists
		    my $counter   = 1;
		    my $max_tries = $genome_length;
		    my $location  = $NULL;
		    do {
			$location = &randint($genome_begin, $genome_end);
			$encoded = &is_encoded($i, $location);
		    }
		    while($encoded eq $TRUE && ($counter++) ne $max_tries);
		    if($counter eq $max_tries) { 
			&printgd("init_population(): Cannot find a noncoding gene.\n");
		    }

		    # Encode the new LLA_IN connection
		    $population{$i}[$location] = &encode($LLA_IN, &random_lla());

		    # Re-encode the actual connection with its parent LLA_IN
		    $population{$i}[$j] = &encode($type, $location);
		}

		# If something else is chosen, crash
		else {
		    &crash("init_population(): Null or invalid connection type recieved ($type).\n");
		}
	    }
	}
	&printgd(&get_genome($i) . "\n");
    }
}

#
# BREED_NEW_GENERATION - Breeds a new generation by applying crossover, elitism,
#  tournament selection, and mutation to the existing population.
#
#  args: none
#
sub breed_new_generation() {

    # Select the elites
    my @elites = &get_elites();

    #
    # Copy each elite to the new generation -
    # 
    # NOTE: We don't want to muck around with the current generation
    #  until crossover, etc. is complete. 
    #
    for(my $i = 0; $i < scalar(@elites); $i++) {
	my $index = $elites[$i];
	&printgd("breed_new_generation(): Copying genome $index to the new population at index $i:\n");

	#
	# HACK: Perl is kind of particular with its data structures.
	#  Something like $new{$key}=$old{$key} won't work in this context
	#  because we are dealing with a hash of arrays.  Perl will only
	#  copy the reference to the array, which we will be destroying later.
	#  Similarly, $new{$key}=&copy(@array) will force Perl into a 
	#  scalar context.  There are probably better ways to do this.
	#
	my @genome = &copy_genome($index);
	$new_population{$i} = [ @genome ];
    }
    &printgd("\n");

    # Breed the rest of the new generation
    &printg("Skipping " . scalar(@elites) . " elites.\n\n");
    my @genome  = [];
    for(my $i = $num_elites; $i < $population_size; $i++) {

	&printgd("breed_new_genome(): BREEDING NEW GENOME $i:\n");

	# Either use crossover,
	if($use_crossover eq $TRUE) {
	    my $mother;
	    my $father = &random_genome();
	    do { 
		$mother = &random_genome();
	    }
	    while($mother eq $father);

	    @genome = &new_genome_with_crossover($mother, $father);

	    &printg("Creating new genome " . ($i + 1) . " (number of crossover points is " .
		    "$num_crossover_points, mutation rate is $mutation_rate):\n");
	    &printg(" Using parent genome at index $mother (fitness=" . &get_fitness($father) . "):\t\'" . 
		    &get_connection_string($mother) . "\'.\n");
	    &printg(" Using parent genome at index $father (fitness=" . &get_fitness($mother) . "):\t\'" . 
		    &get_connection_string($father) . "\'.\n");
	    &printg(" Resultant genome after applying crossover:\t\t\'" . 
		    &get_connection_string('NEW') . "\'.\n");
	}

	# Or use regular (tournament) selection
	else {
	    @genome = &copy_genome(&random_genome());
	}

	# Mutate the new genome
	&printg(" Mutation mask to be applied to the new genome is:\t'");
	my @mutated = &mutate_genome(@genome);
	&printg("\'.\n");

	&printgd("MUTATE: Comparing the original and mutated genomes for genome $i:\n");
	for(my $j = 0; $j < $genome_length; $j++) {
	    &printgd("($genome[$j]=$mutated[$j]) ");
	}
	&printgd("\n");

	# Save the new, mutated genome
	$new_population{$i} = [ @mutated ];
	&printg("\n");
    }

    # Now that we have a new generation, replace the current generation
    for(my $i = 0; $i < $population_size; $i++) {
	&printgd("REPLACE: Copy new genome " . ($i + 1) ."; comparing with the existing genome:\n");
	for(my $j =0; $j < $genome_length; $j++) {
	    &printgd("($new_population{$i}[$j]=$population{$i}[$j]) ");
	    $population{$i}[$j] = $new_population{$i}[$j];
	}
	    
	# Keep the elites' fitness scores, set others to NULL
	if($i < $num_elites) { &set_fitness($i, &get_fitness($elites[$i])); }
	else { &set_fitness($i, $NULL); }
	&printgd("\n\n");
    }

    &printg("Breeding complete.\n\n");
}

#
# EVALUATE_GENERATION - Evaluates each genome on the EAC, assigns a fitness
#  score, and checks if the genome meets the fitness criteria.
#
#  args: none
#
sub evaluate_generation() {
    my $minf   =  1000;
    my $maxf   = -1000;
    my $totalf =  0;
    my $generation = int(&get_generation_id());

    my $fitness_threshold_met = $FALSE;
    my $best   = $NULL;

    &printf("\n");
    &printf("========== EVALUATING GENERATION $generation/$num_generations ==========\n\n");

    # Record and evaluate each member of the generation
    #  TODO: Record the configuration
    for(my $i = 0; $i < $population_size; $i++) {

	# Cache the current ID
	my $id = &get_id();

	&printf("Evaluating genome $id on \'$eac\':\n");
	&printg(&get_genome($i));
	&printg("Type connection string is \'" . &get_connection_string($i) . "\'.\n");

	# Evaluate the fitness (fitness.pm)
	my $fitness = &get_fitness($i);
	if($fitness eq 'NULL') {
	    $fitness = &evaluate(&copy_genome($i));
	    &set_fitness($i, $fitness);
	}
	else {
	    &printgd("evaluate_generation(): Skipping previously evaulated elite genome $i.\n");
	}
	&printg("Fitness score is $fitness out of $max_fitness.\n");

	# Set a flag if the genome meets the fitness threshold
	if($fitness >= $fitness_threshold) {
	    $fitness_threshold_met = $TRUE;
	}

	# Log the fitness score
	if($fitness > $maxf) {
	    $maxf = $fitness;
	    $best = $i;
	}
	elsif($fitness < $minf) {
	    $minf = $fitness;
	}

	# Add fitness to the aggregate statistics
	$totalf += $fitness;

	# Record the genome and increment the id
	&record_genome($i);
	&increment_genome_id();

	&printg("\n");
    }

    # Record the statistics for the current generation
    &record_generation_statistics($minf, $maxf, $totalf);

    # Print the results
    &printf("\n");
    if($fitness_threshold_met eq $TRUE) {
	&printf("---------- FITNESS THRESHOLD MET ----------\n\n");
	&printf(&get_generation_statistics($generation));
	&printf("\n");
	&printf("Genome $best meets the fitness threshold:\n");

    }
    else {
	&printf("---------- FITNESS THRESHOLD NOT MET ----------\n\n");
	&printf(&get_generation_statistics($generation));
	&printf("\n");
	&printf("Best genome so far was found at index $best:\n");
    }
    &printf(&get_full_genome($best));
    &printf("\n");

    # Return whether a suitable genome was found or not
    return $fitness_threshold_met;
}



# =============== GENOME-LEVEL FUNCTIONS ===============

#
# NOTE: These functions operate on the genome level; that is,
#  they process across the genes of a particular genome.
#

#
# EVALUATE - Evaluate a genome on the currently active analog computer.
#
#  args: none
#
#  NOTE: This is basically a wrapper around the fitness functions
#   in fitness.pm -- edit things there instead.
#
sub evaluate() {
    my @genome = @_;

    # Do not evaluate in hardware if in test-mode
    if($TEST_MODE eq $TRUE) {
	&printg("evaluate(): Evaluation not active in test mode.\n");
	return;
    }

    my $fitness = &evaluate_fitness(@genome);
    return $fitness;
}

#
# NEW_GENOME_WITH_CROSSOVER - Breeds two genomes from the %population hash
#  using crossover and tournament selection and whatever else I throw in.
#
#  args: mother, father
#
sub new_genome_with_crossover() {
    my $mother = $_[0];
    my $father = $_[1];

    my @genome = [];
    my $current_gene_pointer = 0;
    my $select_from_mother = $TRUE;
    my $debug_string = '';
    my $regions = '';

    &printgd("CROSSOVER: Crossing genomes $mother and $father.\n");
    &printgd("CROSSOVER: Crossover regions are between $min_crossover_length and " . 
	     "$max_crossover_length genes, genome length is $genome_length.\n");
    &printgd("CROSSOVER: Selecting " . ($num_crossover_points + 1) . " regions: ");

    for(my $i = 0; $i < $num_crossover_points; $i++) {

	#
	# Choose a random crossover point -- this was tricky to write
	#  abstractly enought to allow things to be parameterized:
	#
	#  1) It is unlikely our final crossover point will extend to
	#     the end of the genome, so we generally have to extend the
	#     final crossover point (hence the outer if-statement).
	#  2) By that same token, we have to make sure the final crossover
	#     point does not extend beyond end of the genome.  We can easily
	#     check for this with the loop invariant, provided we ignore
	#     the case [1], which is covered by the if-statement.
	#
	my $crossover_point = $NULL;
	if($i eq ($num_crossover_points - 1)) {
	    $crossover_point = $genome_length - 1;
	}
	else {
	    do {
		my $length = &randint($min_crossover_length, $max_crossover_length);
		$crossover_point = $current_gene_pointer + $length;
	    }
	    while($crossover_point > $genome_length);
	}
	$regions .= "[${current_gene_pointer}-${crossover_point}] ";
		
	# Splice together the new genome from the current pointer to the crossover point
	for(my $j = $current_gene_pointer; $j <= $crossover_point; $j++) {
	    if($select_from_mother eq $TRUE) {
		$genome[$j] = $population{$mother}[$j];
		$debug_string .= "m($genome[$j]=$population{$mother}[$j]) ";
	    }
	    else {
		$genome[$j] = $population{$father}[$j];
		$debug_string .= "f($genome[$j]=$population{$father}[$j]) ";
	    }
	}

	# Increment the gene pointer
	$current_gene_pointer = $crossover_point + 1;
	
	# Next time select from the other parent
	if($select_from_mother eq $TRUE) { $select_from_mother = $FALSE; }
	else { $select_from_mother = $TRUE; }
    }

    #
    # HACK: Use a little hash trickery to tuck the new genome away
    #  until it can be copied - instead of using the population index
    #  as the hash key, we use 'NEW'.
    #
    $population{'NEW'} = [ @genome ];
    chop($regions);

    &printgd("$regions\n");
    &printgd("CROSSOVER: Crossing genes:\n");
    &printgd("$debug_string\n");
    return @genome;
}

#
# MUTATE_GENOME - Randomly mutates some of the genes in a genome.
#  TODO: Option to initialize non-coding regions?
#  TODO: Option to flip sources and sinks?
#
sub mutate_genome() {
    my @genome  = @_;
    my @mutated;

    for(my $i = 0; $i < $genome_length; $i++) {
	my $type  = &get_type($genome[$i]);
	my $value = &get_value($genome[$i]);

	# Should we mutate?
	if(rand(1) < $mutation_rate) {

	    # Noncoding regions
	    if($type eq $NULL) {
		&printg($NONCODING_MUTATION);
		$mutated[$i] = $genome[$i];
	    }

	    # Mutate sources and sinks (change the current)
	    elsif($type eq $SOURCE || $type eq $SINK) {

		# Should we just add noise, or randomly mutate the current?
		if(rand(1) < $noise_mutation_rate) {
		    &printg($NOISE_MUTATION);
		    my $noise = rand(1) * $noise_scaling_factor;
		    
		    # Half the time add noise, half the time subtract noise
		    #   TODO:  Be pedantic, make this Gaussian
		    if (rand(1) < 0.5) { $noise = $noise * -1; }
		    $value += $noise;
		}
		else {
		    &printg($CURRENT_MUTATION);
		    $value = &random_current();
		}

		# Check the range on the mutated current, then encode
		if($value < $min_current) { $value = $min_current; }
		elsif($value > $max_current) { $value = $max_current; }
		$mutated[$i] = &encode($type, $value);
	    }

	    # Mutate LLAs (choose a random function)
	    elsif($type eq $LLA_IN) {
		&printg($LLA_IN_MUTATION);
		$mutated[$i] = &encode($type, &random_lla());
	    }

	    # Mutate LLA_SRCs (change to LLA_SNK)
	    elsif($type eq $LLA_SRC) {
		&printg($LLA_OUT_MUTATION);
		$mutated[$i] = &encode($LLA_SNK, $value);
	    }

	    # Mutate LLA_SNKs (change to LLA_SRC)
	    elsif($type eq $LLA_SNK) {
		&printg($LLA_OUT_MUTATION);
		$mutated[$i] = &encode($LLA_SRC, $value);
	    }

	    # Crash on anything else
	    else {
		&crash("ga::mutate_genome(): Unrecognized connection type ($type).\n");
	    }
	}

	# No mutation for the current gene
	else {
	    $mutated[$i] = $genome[$i];
	    &printg($NON_MUTATION);
	}
    }

    # Return the mutated genome
    return @mutated;
}



# ===============  AUXILIARY FUNCTIONS ===============

#
# NOTE:
#

# --------------- Gene <something> ---------------

#
# NOTE:
#

#
# ENCODE - Encodes type and value information into a gene.
#
#  args: type, value
#
sub encode() {
    my $type  = $_[0];
    my $value = $_[1];
    my $encoding = $type . $encoding_seperator . $value;
    return $encoding;
}

#
# IS_ENCODED - Returns TRUE if the gene is currently coding for some value.
#
#  args: genome_id, gene_id
#
sub is_encoded() {
    my $genome = $_[0];
    my $gene   = $_[1];
    my $value  = &get_type($population{$genome}[$gene]);
    if($value eq $NULL) { return $FALSE; }
    else { return $TRUE; }
}

#
# GET_TYPE - Given an encoded gene (string), returns the type.
#
#  args: gene
#
sub get_type() {
    my @encoding = split($encoding_seperator, $_[0]);
    return $encoding[0];
}

#
# GET_VALUE - Given an encoded gene (string), returns the value.
#
#  args: gene
#
sub get_value() {
    my @encoding = split($encoding_seperator, $_[0]);
    return $encoding[1];
}

#
# GET_FITNESS - Given a genome index, returns the fitness score.
#
#  args: genome_id
#
sub get_fitness() {
    my $index = $_[0];

    #
    # Retrieve the fitness and make it print-friendly;
    #
    # NOTE:  Refer to the notes about the %population data structure
    #  if this is confusing.  Basically, the fitness score exists
    #  outside of the index-genome pair as a seperate key-value pair.
    #
    my $fitness = sprintf($fitness_format, $population{$index . $FITNESS_SUFFIX});
    if(int($fitness) eq $NULL) {
	$fitness = 'NULL';
    }

    return $fitness;
}

#
# SET_FITNESS - Assigns a fitness score to a given genome.
#
#  args: genome_id
#
sub set_fitness() {
    my $index   = $_[0];
    my $fitness = $_[1];
    $population{$index . $FITNESS_SUFFIX} = $fitness;
}

#
# COPY_GENOME - Makes and returns a copy (not reference) of a given genome.
#
#  args: genome_id
#
sub copy_genome() {
    my $index  = $_[0];
    my @genome = [];
    for(my $i = 0; $i < $genome_length; $i++) {
	$genome[$i] = $population{$index}[$i];
	&printgd("($genome[$i]=$population{$index}[$i]) ");
    }
    &printgd("\n");
    return @genome;
}



# --------------- Selection functions ---------------

#
# NOTE: These functions are used to select various, sometimes
#  random components (genes, values, indices, etc).
#

#
# GET_ELITES - Returns the best genomes by fitness score.
#
#  args: none
#
sub get_elites() {

    #
    # Sort by fitness score --
    #
    # NOTE: This is where I start to regret using the convoluted
    #  hash-of-array-of-strings data structure -- we have no sorting efficiency!
    #
    for(my $i = 0; $i < $population_size; $i++) {
	$fitness[$i] = &get_fitness($i) . $encoding_seperator . $i;
    }
    my @fitness = sort {$b <=> $a} @fitness;

    # Select the first n elites ([0] = fitness score, [1] = population index)
    my @elites = [];
    for(my $i = 0; $i < $num_elites; $i++) {
	my @genome = split($encoding_seperator, $fitness[$i]);
	$elites[$i] = $genome[1];
    }

    &printgd("GET_ELITES:  Selected " . scalar(@elites) . " elites with indices at @elites.\n");
    return @elites;
}

#
# RANDOM_CURRENT - Returns a randomly selected current (mA) value.
#
#  args: none
#
sub random_current() {
    return sprintf($current_precision, 
		   (&random($min_current, $max_current) / $initial_current_scaling_value));
}

#
# RANDOM_CONNECTION_TYPE - Returns a randomly selected connection type.
#
#  NOTE: Refer to the notes at the top of this file for more
#   details as to exactly how this fits into the bigger picture.
#
#  args: index
#
sub random_connection_type {
    my $index = $_[0];

    #
    # Return a random connection for the EAC (hardware v1) --
    #
    # NOTE: Using the index given as a pointer in the genome, we 
    #  determine what component to return.  init_population is 
    #  responsible for non-coding and other issues.
    #
    if($HARDWARE eq $EACV1) {
	if($index >= $source_begin_index && $index <= $source_end_index) {
	    return $SOURCE;
	}
	elsif($index >= $sink_begin_index && $index <= $sink_end_index) {
	    return $SINK;
	}
	elsif($index >= $lla_begin_index && $index <= $lla_end_index) {
	    return $LLA_IN;
	}
	else {
	    &crash("random_connection_type(): The index is beyond the end of the genome ($index).\n");
	}
    }

    #
    # Return a random connection for the uEAC (hardware v2) --
    # 
    # NOTE: SRC, SNK, LLA_IN, LLA_SRC, and LLA_SNK are returned with
    #  roughly equal frequency.  init_population is assumed to figure 
    #  out what to do with the type and handle non-coding issues.
    #
    # TODO: Add an option for LLAs that both source and sink -
    #  (would need to be supported by the calling function too)
    # TODO: Probabilities for specific connections?
    #
    elsif($HARDWARE eq $EACV2) {

	my $type = &randint(1, $num_types);

	# The type constants are not guarenteed to be sequential
	#  integers, so we are stuck with this if tree.
	if($type eq '1') {
	    return $SOURCE;
	}
	elsif($type eq '2') {
	    return $SINK;
	}
	elsif($type eq '3') {
	    return $LLA_IN;
	}
	elsif($type eq '4') {
	    return $LLA_SRC;
	}
	elsif($type eq '5') {
	    return $LLA_SNK;
	}
	else {
	    &crash("random_connection_type(): Unknown connection type selected ($type).\n");
	}

    }

    # Illegal hardware
    else { &crash("random_connection_type(): Unsupported hardware version requested ($type).\n"); }
}

#
# RANDOM_GENOME - Selects a random genome, using tournament
#  selection, if enabled; otherwise, random selection is used.
#
#  args: none
#
sub random_genome() {

    # Choose a random candidate
    my $candidate = &randint(0, ($population_size - 1));

    # Match the candidate against n random candidates,
    if($use_tournament_selection eq $TRUE) {
	&printgd("SELECT: Tournament selection enabled with $num_tournament_opponents matches: ");
	for(my $i = 0; $i < $num_tournament_opponents; $i++) {
	    my $challenger = &randint(0, $population_size);
	    &printgd("[${candidate},${challenger}=");
	    if(&get_fitness($challenger) > &get_fitness($candidate)) {
		$candidate = $challenger;
	    }
	    &printgd("$candidate] ");
	}
	&printgd("\n");
    }

    # Or simply return the candidate if tournament selection is disabled
    else {
	&printgd("SELECT: Tournament selection disabled, selected $candidate.\n");
    }
    return $candidate;
}

#
# RANDOM_LLA - Returns a random LLA function.
#
#  args: none
#
sub random_lla() {
    return &randint($min_lla, $max_lla);
}



# --------------- Print functions ---------------

#
# NOTE: These functions are used to translate various portions
#  of the genome into a print-friendly format.
#

#
# GET_GENOME - Wrapper function for get_gene_string() - Returns
#  a printable version of the genome.
#
sub get_genome() {
    return &get_string($GET_GENOME, $_[0]);
}

#
# GET_CONNECTION_STRING - Wrapper function for get_gene_string() -
#  Returns a printable version of the connection type string.
#
sub get_connection_string() {
    return &get_string($GET_CONNECTION_STRING, $_[0]);
}

#
# GET_FULL_GENOME - Wrapper function for get_gene_string() - Returns
#  a printable version of the genome, connection type string, and fitness.
#
sub get_full_genome() {
    my $index = $_[0];
    my $string = '';
    $string .= &get_genome($index);
    $string .= "Type connection string is \'" . &get_connection_string($index)  . "\'.\n";
    $string .= "Fitness score is \'" . &get_fitness($index)  . "\' out of $max_fitness.\n";
    return $string
}

#
# GET_GENE_STRING - 
#   TODO:  Rewrite v1 string assembly (it works, it's just ugly code)
#
sub get_string() {
    my $flag       = $_[0];
    my $index      = $_[1];

    my $type   = $NULL;
    my $value  = $NULL;
    my $gene_string = '';
    my $type_string = '';
    my $string      = '';

    # Hardware version 1 encoding
    if($HARDWARE eq $EACV1) {
	$gene_string .= 'Sources:  ';
	for(my $i = $source_begin_index; $i <= $source_end_index; $i++) {
	    $value = &get_value($population{$index}[$i]);
	    if($value eq $NULL) {
		$type_string .= $noncoding_symbol;
	    }
	    else {
		$type_string .= $SOURCE;
		$gene_string .= "$i=" . sprintf($current_precision, $value) . ' ';
	    }
	}
	$gene_string .= "\n";
	$gene_string .= 'Sinks:    ';
	for(my $i = $sink_begin_index; $i <= $sink_end_index; $i++) {
	    $value = &get_value($population{$index}[$i]);
	    if($value eq $NULL) {
		$type_string .= $noncoding_symbol;
	    }
	    else {
		$type_string .= $SINK;
		$gene_string .= ($i - $num_sources) . '=' . sprintf($current_precision, $value) . ' ';
	    }
	}
	$gene_string .= "\n";
	$gene_string .= 'LLAs:     ';
	for(my $i = $lla_begin_index; $i <= $lla_end_index; $i++) {
	    $value = &get_value($population{$index}[$i]);
	    if($value eq $NULL) {
		$type_string .= $noncoding_symbol;
	    }
	    else {
		$type_string .= $LLA_IN;
		$gene_string .= ($i - ($num_sources + $num_sinks)) . '='  . $value . ' ';
	    }
	}
    }

    # Hardware version 2 encoding
    else {
	for(my $i = 0; $i < $genome_length; $i++) {
	    $type  = &get_type($population{$index}[$i]);
	    $value = &get_value($population{$index}[$i]);

	    # Add row labels (and linebreaks after the first row)
	    $str = '';
	    if(($i % $num_rows) eq 0) {
		if($i > 0) { $gene_string .= "\n"; }
		$gene_string .= "Row " . (int($i / $num_rows) + 1) . ":   ";
	    }

	    # Compute the maximum column width
	    my $max_col_width = 5 + length(sprintf($current_precision, 1));

	    # Clean up NULL connections
	    if($type eq $NULL) {
		$type = $noncoding_symbol;
		for(my $j = 0; $j < $max_col_width; $j++) {
		    $str .= $noncoding_symbol;
		}
	    }

	    # Format sources and sinks with their current value
	    elsif($type eq $SOURCE || $type eq $SINK) {
		$str = "$type, $value";
	    }

	    # Format LLAs with their function
	    elsif($type eq $LLA_IN) {
		$str = "$type, f=$value";
	    }

	    # Format LLA_SRCs and LLA_SNKs with their parent LLA
	    elsif($type eq $LLA_SRC || $type eq $LLA_SNK) {
		$value = &decode_position($value);
		$str = "$type ($value)";
	    }

	    # Add extra spacing to narrow columns
	    my $len = length($str);
	    for(my $j = 0; $j < ($max_col_width - $len); $j++) {
		$str .= ' ';
	    }

	    $type_string .= $type;
	    $gene_string .= "$str   ";
	}
    }

    # Build the final string, depending on we were called
    if($flag eq $GET_GENOME) {
	$string = $gene_string . "\n";
    }
    elsif($flag eq $GET_CONNECTION_STRING) {
       	$string .= $type_string;
    }
    else {
	&crash("get_string(): Unrecognized flag recieved ($flag).\n");
    }

    # Return the final string
    return $string;
}
















#
# FIXME: Only support for hardware v1 right now
#
sub write_analog_configuration() {
    my @genome = @_;

    for(my $i = 0; $i < $genome_length; $i++) {
	my $type  = &get_type($genome[$i]);
	my $value = &get_value($genome[$i]);

	if($type eq $NULL) { 
	    &printc("write_analog_configuration(): Non-coding gene at index $i ignored.\n");
	}
	elsif($type eq $SOURCE) {  &write_source($index, $value); }
	elsif($type eq $SINK) {    &write_sink(  $index, $value); }
	elsif($type eq $LLA_IN) {  &write_lla(   $index, $value); }
	else {
	    &crash("write_analog_configuration(): Unsupported connection type recieved at index $i ($type).\n");
	}
    }
}
