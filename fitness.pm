#
# FITNESS.PM - Fitness functions to guide evolution of
#  analog configurations.
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

package fitness;

use diagnostics;
use strict;
use warnings;



# ====================[ CONFIGURATION ]====================

use constant TRUE  => (1 == 1);
use constant FALSE => (0 == 1);
use constant NULL  => -1;

our $VERSION       =  '1.0.0';
our $DEBUG_ON      =  TRUE;

# this is the name of the active fitness function to use
my $EVALUATION_HANDLER = 'xor_evaluator';

# ====================[ END CONFIGURATION ]=====================







# --------------------[ Common functions ]---------------------

#
# EVALUATE_GENOME - Fitness evaluation bootstrapper.  All this
#  function does is pass the genome to the appropriate fitness
#  evaluator, defined by EVALUATION_HANDLER above.
#
#  args:    encoded genome
#  returns: fitness score
#
sub evaluate_genome(@)
{
    no strict 'refs';
    return &{'fitness::' . $EVALUATION_HANDLER}(&GA::get_genome($_[0]));
}

#
# SEND_TO_HARDWARE - Sends a configuration (represented by a genome)
#  to the active EAC.
#
#  args:    encoded genome
#  returns: nothing
#
sub send_to_hardware(@)
{
    my @genome = @_;

    for(my $i = 0; $i < $Driver::genome_length; $i++)
    {
	my ($gene_type, $gene_value) = GA::unpack_gene($genome[$i]);

	if($gene_type eq $GA::NONCODING_TYPE)
	{
	    # do nothing
	}
	elsif($gene_type eq $GA::SOURCE_TYPE) { Driver::write_source($i, $gene_value); }
	elsif($gene_type eq $GA::SINK_TYPE)   { Driver::write_sink(  $i, $gene_value); }
	elsif($gene_type eq $GA::LLA_IN_TYPE) { Driver::write_lla_in($i, $gene_value); }
	elsif($gene_type eq $GA::LLA_SRC_TYPE || $gene_type eq $GA::LLA_SNK_TYPE)
	{
	    # unsupported (uEAC)
	}
	else 
	{
	    Toolkit::crash('E_INVALID_GENE_TYPE', "type = $gene_type");
	}
    }
}







# --------------------[ Fitness functions ]----------------------

#
# NOTE: These are some sample fitness functions that may be
#  used to evolve various EAC configurations.  EVALUATION_HANDLER
#  tells the GA which function to use (see the configuration above).
#



#
# MINIMIZE_CONNECTIONS_EVALUATOR - This fitness function
#  is a hardware-independent way of testing the GA.  It
#  attempts to minimize the number of connections for each
#  configuration by reducing the fitness score for each gene
#  that is not of type NONCODING.
#
#  args:    encoded genome
#  returns: fitness score
#
#  NOTE: This function never even sends the configuration to the
#        EAC for evaluation.  It is meant to demonstrate that the
#        GA is working properly.
#
#  NOTE: This is kind of a proof-of-concept fitness function.  If
#        you're trying to figure out how to use this toolkit, here's
#        a well-commented starting point. :-)
#
sub minimize_connections_evaluator()
{
    # The encoded genome is passed in through one of Perl's
    #  crazy default variables, @_; 'my' basically says "make
    #  me a local variable"
    my @genome = @_;

    # Initially, the fitness is perfect, we are going to deduct
    #  points for each connection we encounter
    my $fitness  = $GA::max_fitness;
    my $demerits = $fitness / $Driver::genome_length;

    # Go through each gene in the genome
    for(my $i = 0; $i < $Driver::genome_length; $i++)
    {
	# Here's how we get the type-value pair out of our encoded genome
	my ($gene_type, $gene_value) = &GA::unpack_gene($genome[$i]);

	#
	# NOTE: changing the comparison to 'eq' will drive evolution 
	#       toward maximally complex geneomes
	#
	if($gene_type ne $GA::NONCODING_TYPE)
	{
	    $fitness -= $demerits;

	    #
	    # NOTE: The toolkit provides a debugging function that can be
	    #       used to log diagnostic information.  When enabled (either
	    #       from DEBUG_ON in the configuration section or from the
	    #       interface), the debug method will automatically prepend
	    #       the name of the calling function.
	    #
	    Toolkit::printd("Deducting $demerits fitness points for $gene_type.")
	}
    }

    # Finally, we want to be nice and format the fitness score --
    #  we're only using a few digits of precision
    return sprintf($GA::fitness_mask, $fitness);
}



#
# MATCH_GRADIENT_EVALUATOR - This fitness function attempts
#  to find a configuration that matches a predefined gradient
#  shape (useful for butterfly wing simulations).
#
#  args:    encoded genome
#  returns: fitness score
#
sub match_gradient_evaluator()
{

}



#
# XOR_EVALUATOR - This fitness function attempts to find a
#  configuration that represents analog exclusive-or.
#
#  args:    encoded genome
#  returns: fitness score
#
sub xor_evaluator()
{
    fitness::send_to_hardware(@_);
    return $GA::min_fitness;
}



#
# COLLISION_AVOIDANCE_EVALUATOR - This fitness function
#  attempts to evolve "creatures" that can avoid obstacles
#  in a virtual maze.  
#
#  args:    encoded genome
#  returns: fitness score
#
sub collision_avoidance_evaluator()
{

}

