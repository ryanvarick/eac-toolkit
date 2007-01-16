#
# LOGGING.PM - File I/O and data logging routines.
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



# =============== DATA DIRECTORY MANAGEMENT ===============

#
# GET_DATADIR - Returns the current data directory.
#  FIXME:  What happens when a NULL datadir is opened?
#
sub get_datadir() {
    return $current_datadir;
}

#
# OPEN_DATADIR - Opens a data directory; if it does not exist
#   the directory will be created.
#
sub open_datadir() {
    my $dir = $datadir_prefix . $_[0];
    if($datadir_open eq $TRUE) {
	&printlog("Data directory at \'$dir\' is already open.\n");
    }
    elsif(-e $dir) {
	&printlog("Reusing data directory found at \'$dir\'.\n");
	$datadir_open = $TRUE;
    }
    else {
	&init_datadir($dir);
	$datadir_open = $TRUE;
	&printlog("Created a new data directory at \'$dir\'.\n");
    }
    $current_datadir = $dir;
}

#
# CLOSE_DATADIR - Closes the specified data directory, if open.
#
sub close_datadir() {
    my $dir = &get_datadir();
    if($datadir_open eq $FALSE) {
	&printlog("Data directory at \'$dir\' is not currently open.\n");
    }
    else {
	$current_datadir = $NULL;
	$datadir_open = $FALSE;
	&printlog("Data directory at \'$dir\' closed.\n");
    }
}

#
# INIT_DATADIR - (Re)initializes a data directory.
#
sub init_datadir() {
    my $dir = $_[0];
    
    # If the directory exists, reset; otherwise, create it
    if(-e $dir) {
	$status = `rm -rf $dir`;
    }
    $status = `mkdir $dir`;
    $status = `mkdir $dir/$image_dir`;
    $status = `mkdir $dir/$genotype_dir`;
    $status = `mkdir $dir/$gradient_dir`;

    # Populate datadir
    my $id = $generation_id_base . $id_seperator . $genome_id_base . $id_seperator . $gradient_id_base;
    $status = `echo $id > $dir/$state_file`;
    $status = `echo > $dir/$statistics_file`;
    &printlog("Wrote $id to the \'$dir/$state_file\'.\n");
    &printlog("Data directory created at \'$dir\'.\n");
}

#
# SAVE_DATADIR - Saves the current data directory and creates a new one.
#
sub save_datadir() {
    my $dir = &get_latest_datadir();
    my $old_dir = $datadir_prefix . $dir;
    my $new_dir = $datadir_prefix . (++$dir);

    &printlog("Saving directories through \'$old_dir\'.\n");

    &close_datadir();
    &init_datadir($new_dir);

    $current_datadir = $new_dir;
}

#
# FIND_LATEST_DATADIR - Looks for the highest numbered datadir. If 
#  reuse_last_datadir is true, this function returns the index
#  of the last found data directory; otherwise it returns index+1
#
# NOTE: This routine is usually only called during program start up.
#
sub get_latest_datadir() {
    my $num_found = 0;
    my $testing = $datadir_base;
    my $last_found = $testing;

    # Scan from $datadir_base onward looking for data directories;
    # last_found is the "safe bet", the index returned if we are reusing 
    # directories, otherwise testing is the index returned.  We use 
    # num_found because datadir_base is not guarenteed to be equal to zero.
    while(-e ($datadir_prefix . $testing)) {
	$last_found = $testing;
	$num_found++;
	$testing++;
    }
    &printlog("Found $num_found existing data directories.\n");

    # Return the index (or possibly index+1)
    if($reuse_last_datadir eq $TRUE) { return $last_found; }
    else { return $testing; }
}



# ========== STATE MANAGEMENT ==========

#
# GET_STATEFILE - Returns the current statefile.
#  FIXME: Like get_datadir(), what happens if there is no statefile?
#
sub get_statefile() {
    return &get_datadir() . "/$state_file";
}

#
# GET_ID - Returns the full generation-genome-gradient identifier.
#
sub get_id() {
    my $id = &get_generation_id() . $id_seperator . &get_genome_id() . $id_seperator . &get_gradient_id();
    &printlog("Current identifier is \'$id\'.\n");
    return $id;
}

#
# GET_LAST_ID - Return the last-used identifier.
#
sub get_last_id() {
    return $last_id;
}

#
# GET_GENERATION_ID - Returns the current generation identifier.
#
sub get_generation_id() {
    &open_statefile($READ);
    my $generation = $state[0];
    &printlog("Returning generation $generation.\n");
    return $generation;
}

#
# GET_GENOME_ID - Returns the current genome identifier.
#
sub get_genome_id() {
    &open_statefile($READ);
    my $genome = $state[1]; 
    &printlog("Returning genome $genome.\n");
    return $genome;
}

#
# GET_GRADIENT_ID - Returns the current gradient identifier.
#
sub get_gradient_id() {
    &open_statefile($READ);
    my $gradient = $state[2];
    &printlog("Returning gradient $gradient.\n");
    return $gradient;
}

#
# INCREMENT_GRADIENT_ID - Increments the gradient indentifier.
#
sub increment_gradient_id() {
    $last_id = &get_id();
    my $gradient = &get_gradient_id();
    $gradient++;
    my $id = &get_generation_id() . $id_seperator . &get_genome_id . $id_seperator . $gradient;
    &printlog("New identifier is \'$id\'.\n");
    &write_statefile($id);
}

#
# INCREMENT_GENOME_ID - Increments the genome identifier (and the
#   generation ID, if necessary).
#
sub increment_genome_id() {

    # Update the last ID
    $last_id = &get_id();

    # Get the current ID
    my $generation = &get_generation_id();
    my $genome     = &get_genome_id();

    # Update
    $genome++;
    if($genome > $population_size) {
	$generation++;
	$genome = $genome_id_base;
    }
    my $id = $generation . $id_seperator . $genome . $id_seperator . $gradient_id_base;
    &printlog("New identifier is \'$id\'.\n");
    &write_statefile($id);
}

#
# OPEN_STATEFILE - Opens the statefile for read or write access.
#
sub open_statefile() {
    my $mode = $_[0];
    my $statefile = &get_statefile();

    if($statefile_open eq $TRUE) {
	&printlog("Statefile is already open.\n");
    }

    # Read
    elsif($mode eq $READ) {
	&printlog("Opening statefile at \'$statefile\' for read access.\n");
	open(STATE, "< $statefile") or &crash("open_statefile(): Statefile access error: \'$!\'.");
	@state = split($id_seperator, <STATE>);
	$statefile_open = $TRUE;
	chomp $state[2];
	&printlog("Statefile contains: $state[0], $state[1], $state[2].\n");
    }

    # Write 
    elsif($mode eq $WRITE) {
	&printlog("Opening statefile at \'$statefile\' for write access.\n");
	open(STATE, "> $statefile") or &crash("open_statefile(): Statefile access error: \'$!\'.");
    }

    # Illegal access mode
    else {
	&crash("open_statefile(): Unknown access mode requested ($mode).\n");
    }

    $statefile_open = $TRUE;
}

#
# CLOSE_STATEFILE - Closes the statefile.
#
sub close_statefile() {
    if($statefile_open eq $TRUE) {
	my $statefile = &get_datadir() . "/$state_file";
	&printlog("Closing statefile at \'$statefile\'.\n");
	close STATE;
	$statefile_open = $FALSE;
    }
    else {
	&printlog("Statefile is already closed.\n");
    }
}

#
# WRITE_STATEFILE - Writes an identifier to the statefile.
#
sub write_statefile() {
    my $statefile = &get_statefile();
    &close_statefile();
    &open_statefile($WRITE);
    open(STATE, "> $statefile") or &crash("write_statefile(): Statefile access error: \'$!\'.");
    print STATE $_[0];
    &close_statefile();
}





# ========== MORE LOGGING STUFF ==========

#
# GET_GENERATION_STATISTICS - Returns the statistics for the given generation.
#
sub get_generation_statistics() {
    my $index = $_[0];
    my $statfile = &get_datadir() . "/$statistics_file";

    &printlog("Retrieving statistics for generation " . int($index) . " from \'$statfile\':\n");

    # Read the statistics file
    open(STATS, "< $statfile") or 
	&crash("get_generation_statistics(): Could not read from statistics file: $!\n");
    my @stats = <STATS>;
    close STATS;

    return $stats[$index];
}

#
# RECORD_GENERATION_STATISTICS - Computes the statistics for the generation and
#  appends the results to the statistics file.
#
sub record_generation_statistics() {
    my $min = sprintf($fitness_format, $_[0]);
    my $max = sprintf($fitness_format, $_[1]);
    my $avg = sprintf($fitness_format, $_[2] / $population_size);
    my $generation = &get_generation_id() - 1;

    my $conv  = "$generation $min\n";
    my $stats = "Results for generation $generation/$num_generations: max=$max, min=$min, avg=$avg.\n";

    my $convfile = &get_datadir() . "/$convergence_file";
    my $statfile = &get_datadir() . "/$statistics_file";

    # Write the statistics file
    open(STATS, ">> $statfile") or 
	&crash("record_generation_statstics(): Could not write to statistics file: $!\n");
    print STATS "$stats";
    close STATS;

    # Write the convergence file
    open(CONV,  ">> $convfile") or 
	&crash("record_generation_statistics(): Could not open convergence file: $!\n");
    print CONV "$conv";
    close CONV;
}

#
#
#
sub record_genome() {
    my $index = $_[0];
    my $genefile   = &get_datadir() . "/$genotype_dir/" . 
	&get_generation_id() . $id_seperator . &get_genome_id() . ".cfg";

    open(GENE, "> $genefile") or 
	&crash("record_genome(): Could not write to the genome configuration file: $!\n");
    print GENE &get_full_genome($index);
    close GENE;

    &printlog("Genome saved to \'$genefile\'.\n");
}













# ========== PROCESSING ==========

sub record_gradient() {
    my $id = $_[0];
    my $gradient = $_[1];
    my $gradfile = &get_datadir() . "/${gradient_dir}/${id}.dat";
    &printlog("Writing gradient to \'$gradfile\'.\n");
    open(GRAD, "> $gradfile") or &crash("record_gradient(): Cannot write gradient: $!\n");
    print GRAD $gradient;
    close GRAD;
    &printf("Voltage gradient saved to \'$gradfile\'.\n");
}

#
# PLOT - plots a voltage gradient using gnuplot
#   FIXME:  Figure out what to do about the fitness function
#
sub plot {
    my $id       = $_[0];
    my $gradient = $_[1];
    my $fitness  = $_[2];
    if(not(defined($_[2]))) { $fitness = 'N/A'; }

    # Figure out various file locations
    my $dir = &get_datadir() . '/';
    my $datafile = $dir . "${gradient_dir}/${id}.dat";
    my $plotfile = $dir . "plot.cmd";
    my $imagedir = $dir . "${image_dir}";
    my $feedback, $imagefile;

    # Open the plotfile
    #  BUGFIX: We need autoflushing to ensure the plotfile is written over NFS
    open(DATA, "> $plotfile") or &crash("plot(): Plotfile write error: \'$!\'.\n");
    DATA->autoflush(1);

    # HACK:  'Convergence' is just a fancy name for a negative id number
    #  indicate special functionality rather than a regular genome
    if($id eq $CONVERGENCE) {
#	$image    = $convergence_file . '.jpg';
#	$feedback = 'Convergence graph';
#	print DATA qq {
#	    set terminal jpeg
#	    set output "$imageloc/$image"
#	    set time
#	    set title "Convergence Rate"
#	    set nokey
#	    plot "$convergence_file" with lines \n
#	};
    }

    # Normal gradient plotting
    else {
        my $fitness = &get_fitness($id);
	$imagefile  = "${id}.jpg";
	$feedback   = "Voltage gradient";

	print DATA qq {
	    set terminal jpeg
	    set output "$imagedir/$imagefile"
	    set data style lines
	    set parametric
	    set hidden3d

	    set grid
	    set dgrid3d 30,30,2 
	    set view 60, 120
	    set autoscale

	    set time
	    set title "Sheet Voltage Gradient $id (fitness: $fitness)"
	    set nokey

	    splot "$datafile" matrix \n
	};
    }

    # Plot and view the gradient
    &printlog("Plot file written to \'$plotfile\'.\n");
    system("$gnuplot $plotfile");
    &printf("$feedback plotted to \'$imagedir/$imagefile\'.\n");
}

#
# VIEW - opens the given plot in a viewer, as well as printing at the command line
#
sub view() {
    my $id        = $_[0];
    my $datafile  = &get_datadir() . "/${gradient_dir}/${id}.dat";
    my $imagefile = &get_datadir() . "/${image_dir}/${id}.jpg";

    system("$viewer $imagefile &");
    system("cat $datafile");
    print "\n";
}


