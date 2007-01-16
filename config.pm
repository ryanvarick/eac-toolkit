#
# CONFIG.PM - Lots of parameters for your tweaking pleasure.
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
# DESCRIPTION: These are all various parameters and values that
#  can be tweaked throughout the program, I hope.  This is due
#  for a rewrite.
#



#
# Other files to include
#

# use Hardware; # TODO: Need an original name, updated calls
require 'hardware.pm';  # Core - HAL
require 'logging.pm';   # Core - data logging module
require 'utilities.pm'; # Core - miscellaneous functions
require 'fitness.pm';   # Core (should be extra)
require 'ga.pm';        # Core (should be extra)

# Experimental support for strict
use strict;


# ========== USER DEFINED VALUES ==========

#
# NOTE: Variables in this section can be tweaked to modify program behavior.
#  The variables in the 'Internals' section are not meant to be modified.
#  It just so happened that this file morphed into the central registry for
#  all globals variables used by the program.
#

#
# NOTE: I didn't know Perl supported booleans at the time I started this
#  monstrosity.  I apologize for sucking at life.
#
our $NULL  = -1;
our $TRUE  =  1;
our $FALSE =  0;

# Program version
our $VERSION = '2.0.2';



# ---------- Feedback control ----------

our $FEEDBACK    = $TRUE;                    # Basic feedback, can be disabled for silent running
our $GA_FEEDBACK = $TRUE;                    # Extended feedback when running the GA
our $SHOW_TIPS   = $TRUE;                    # Help messages for mistyped commands
our $show_prompt = $TRUE;                    # A basic prompt, you probably want this enabled



# ---------- Debugging control ----------

#
# NOTE: If you are debugging, you should probably set the population and generations
#  low -- these will generate *a lot* of feedback to sift through.
#

our $DEBUG         = $FALSE;                 # General debugging messages
our $DEBUG_COMM    = $FALSE;                  # Communication specific debugging messages
our $DEBUG_LOGGING = $FALSE;                 # Logging specific debugging messages
our $DEBUG_GA      = $FALSE;                 # GA specific debugging messages

our $TEST_MODE = $FALSE;                     # Disable communication with the EAC



# ---------- Logging parameters ----------

our $HELPFILE = 'docs/commands';                  # Location of the quick help sheet

our $viewer  = 'eog';                        # Default image viewer (eog = "Eye of Gnome")
our $gnuplot = 'gnuplot';                    # Path the gnuplot, a rather useless variable

our $datadir_prefix    = 'dataset';          # Name of the directory logs are to be saved to --
our $datadir_seperator = '-';                #  Multiple datasets are stored in sequentially numbered
our $datadir_base      = '00';               #  directories, modified by these variables

our $genotype_dir      = 'genotypes';        # Directory used by the GA to store configurations
our $gradient_dir      = 'gradients';        # Directory used to store voltage gradients
our $image_dir         = 'images';           # Directory used to store plots of the voltage gradient

our $state_file       = 'statefile';         # File used to store the current identifier
our $statistics_file  = 'statsfile';         # File used to store the generational statistics
our $convergence_file = 'convergence';       # File used to store overall convergence statistics

our $generation_id_base = '01';              # The identifier is in the format of 00-000-000
our $genome_id_base     = '001';             #  The first number is the generation id, the second
our $gradient_id_base   = '001';             #  number is the genome id, and the third is the
our $id_seperator       = '-';               #  gradient id associated with that genome

our $reuse_last_datadir = $TRUE;             # Whether to reuse the latest data directory or create
our $autoclean          = $TRUE;             #  a new directory, and, if reusing, whether to reset first

our $use_zero_based_input = $FALSE;          # Whether user interface input is 1-based --
                                             #  Internally, everything is 0-based, which is easy
                                             #  to forget about.  This variable allows for a bit more
                                             #  intuitive operation, I think.



# ---------- Hardware parameters ----------

#
# NOTE: This turned out more complicated than I intended.  This
#  system of 'flags' is supposed to allow the program to be extended
#  in the future as new hardware variations are added.  These variables
#  need to convey three things:
#
#  1) The HARDWARE details of the EAC.
#  2) The LOCATION of the EAC.
#  3) The PROTOCOL to use to communicate with the EAC.
#
#  Unfortunately I didn't think this through enough so the final result
#  is somewhat confusing.  The first group of variables conveys (1), the
#  second group of variables conveys (2), and the third conveys (3).
#
#  Generally, when making decisions about the hardware, the protocol flag
#  is tested (i.e., if($HARDWARE eq $EACV1) { ... } ).  This is usually
#  okay outside of hardware.pm, since the most important difference
#  between the hardware versions is EAC vs. uEAC.  I've tried to abstract
#  the rest of the program such that the protocol differences, location,
#  and hardware minutia (grid vs. radial, etc) are confined to hardware.pm.
#
#  From the user's perspective, $HARDWARE conveys the essential
#  information -- are we using one of the EACs?  Or are we using one of
#  the more flexible uEACs?  Leave it to hardware.pm to figure out the
#  the details. 
#

our $EAC_FOAM    = 'v1-foam';                # EAC (hardware v1) substrates --
our $EAC_SILICON = 'v1-silicon';             #  foam (grid) and silicon (radial)
our $UEAC_NET    = 'v2-net';                 # uEAC (hardware v2) communication protocols --
our $UEAC_USB    = 'v2-usb';                 #  net (network) and USB (virtual serial port)

our $default_foam_eac    = 'eac3.cs.indiana.edu';     # Locations of various default EACs
our $default_silicon_eac = 'eac4.cs.indiana.edu';
our $default_usb_ueac    = '/dev/ttyUSB0';
our $default_net_ueac    = '';

our $EACV1 = $EAC_FOAM;                      # Protocol flags, what protocol to use with
our $EACV2 = $UEAC_USB;                      #  each architecture -- EAC = EACV1, uEAC = EACV2

our $HARDWARE = $EACV1;                      # Default communication protocol
our $eac = $default_foam_eac;             # Default machine to use

#
# Defaults specific to the EAC (hardware v1)
#
our $min_foam_current = 0;                   # Minimum and maximum amount of current the foam EACs
our $max_foam_current = 200;                 #  should try to use
our $min_silicon_current = 0;                # Minimum and maximum amount of current the silicon EACs
our $max_silicon_current = 1000;             #  should try to use

our $num_sources = 8;                        # Number of sources to index (1-based)
our $num_sinks   = 8;                        # Number of sinks to index (1-based)
our $num_llas    = 6;                        # Number of LLAs to index (1-based)
                                             #  NOTE: If you want to disable LLAs altogether, then
                                             #  you should set the use_llas variable below to FALSE


# FIXME
our $current_unit = 'uA';


#
# Defaults specific to the uEAC (hardware v2)
#
our $min_ueac_current = 0;                   # Minimum and maximum amount of current the
our $max_ueac_current = 200;                #  sources and sinks suppport
our $num_rows = 5;                           # Dimensions of the sheet (1-based)
our $num_cols = 5;

#
# Defaults shared by both hardware versions
#
our $min_lla  = 1;                           # Inclusive bounds on the LLAs (DEPRICATED)
our $max_lla  = 27;                          #
our $use_llas = $TRUE;                       # Whether to encode LLAs or not (used by the GA)

our $initial_current_scaling_value = 1;      # During initialization, scale current by this value
our $current_precision = "%2.1f";            # Current precision (a sprintf mask)
our $voltage_precision = "%2.3f";            # Voltage precision (a sprintf mask)

our $reset_board = $FALSE;                   # Whether to reset the board before each GA evaluation
our $num_report_samples = 1;                 # Number of times to sample when reporting the gradient



# ---------- Genetic Algorithm Parameters ----------

#
# General parameters
#
our $population_size   = 5;                  # Number of genomes in the population
our $num_generations   = 2;                  # Number of populations to evaluate
                                             #  NOTE: The GA will stop regardless if the fitness
                                             #  threshold is met (see below).

our $non_coding_probability = 0.5;           # Probability that a gene will not encode anything
                                             #  (used during initialization)

our $fitness_threshold = 100.0;              # What constitutes a 'good enough' genome
our $fitness_format    = "%4.3f";            # Fitness precision (a sprintf mask)
our $min_fitness       = 0.0;                # Lower bound on fitness (internal)
our $max_fitness       = 100.0;              # Upper bound on fitness (internal)

#
# Breeding parameters
#
our $num_elites = 1;                         # Number of elites genomes to select before breeding

our $use_tournament_selection = $TRUE;       # Whether to use tournament selection during breeding,
our $num_tournament_opponents = 2;           #  and the number of genomes to compete against

our $use_crossover            = $TRUE;
our $num_crossover_points     = 3;           # FIXME: Should this 0-based, and not broken
our $min_crossover_length     = 2;           # Minimum number of genes that a crossover region must have
our $max_crossover_length     = 10;          # Maximum number of genes that a crossover region may have

#
# Mutation parameters
#
our $mutation_rate        = 0.1;             # Frequency at which mutation should occur
our $noise_mutation_rate  = 0.0;             # When mutating, frequency at which mutation simply adds
                                             #  noise.  This works on the principle that mutation may
                                             #  be too coarse to hone in on the best solution -- that
                                             #  ultimately the GA should be able to explore solutions around
                                             #  a specific point
our $noise_scaling_factor = 1.0;             # Value to multiply the noise (0.0 - 1.0) by



# ---------- Interface options  ----------

#
# PARAMETERS - hash of variables-value pairs (NOTE: NO ERROR CHECKING!)
#
#   1. 'token'     =>  'Variable to set'
#   2. 'token_PS'  =>  'Confirmation message to display' (PS - "print string")
#
our $PARAMETER_SUFFIX = '_PS';
our %parameters =
    ('current-scaling'    => 'initial_current_scaling_value',
     'current-scaling_PS' => "Current (uA) values during GA initialization will be divided by",

     'elites'    => 'num_elites',
     'elites_PS' => "Number of elites per generation is",

     'fitness-threshold'    => 'fitness_threshold',
     'fitness-threshold_PS' => "Fitness threshold is",

     'generations'    => 'num_generations',
     'generations_PS' => "Number of generations is",

     'mutation-rate'    => 'mutation_rate',
     'mutation-rate_PS' => "Mutation rate is",

     'min-current'    => 'min_current',
     'min-current_PS' => "Minimum current (uA) is",
     
     'max-current'    => 'max_current',
     'max-current_PS' => "Maximum current (uA) is",

     'noise-rate'    => 'noise_mutation_rate',
     'noise-rate_PS' => "Noise mutation rate is",

     'noise-scaling'    => 'noise_scaling_factor',
     'noise-scaling_PS' => "Noise mutation is scaled by",

     'noncoding-prob'    => 'non_coding_probability',
     'noncoding-prob_PS' => "Non-coding probability is",

     'psize'    => 'population_size',
     'psize_PS' => "Population size is");

#
# TOGGLES - hash of toggle-able variables (T/F)
#
#   1.  'token'     =>  'Variable to toggle'
#   2.  'token_PS'  =>  'Confirmation message to display'
#
our $TOGGLE_SUFFIX  = '_PS';
our %toggles = 
    ('crossover'     => 'use_crossover',
     'crossover_PS'  => "Crossover is",

     'debug'     => 'DEBUG',
     'debug_PS'  => "General debugging messages are",

     'debug-comm'     => 'DEBUG_COMM',
     'debug-comm_PS'  => "Communication debugging messages are",

     'debug-ga',    => 'DEBUG_GA',
     'debug-ga_PS'  => "GA debugging messages are",

     'ga-feedback'     => 'GA_FEEDBACK',
     'ga-feedback_PS'  => "Verbose feedback for the GA is",

     'debug-logging'     => 'DEBUG_LOGGING',
     'debug-logging_PS'  => "Logging debugging messages are",

     'feedback'     => 'FEEDBACK',
     'feedback_PS'  => "General feedback is",

     'test-mode'     => 'TEST_MODE',
     'test-mode_PS'  => "Test mode is",

     'tournament-selection'     => 'use_tournament_selection',
     'tournament-selection_PS'  => "Tournament selection is",
 );



# ========== INTERNAL GLOBALS ==========

#
# NOTE: These variables aren't really meant to be adjusted.
#  Changing these values could break things.
#

# Socket package
use Socket;
use FileHandle;

# Virtual serial port (USB)
# use Device::SerialPort qw(:PARAM :STAT 0.07);
# use IO::Seekable;




# The two population hashes (refer to ga.pm for notes on how these work)
our %population;
our %new_population;

# Useful genome indices
our $genome_length = $NULL;
our $genome_begin  = $NULL;
our $genome_end    = $NULL;

# Fitness suffix for indexing into the population hash
our $FITNESS_SUFFIX = '_fitness';

#
# HACK: A kind of rudimentary flag system to make the
#  genome get_* functions work without repeating code
#
our $GET_GENOME = 10;
our $GET_CONNECTION_STRING = 20;

#
# HACK: Another set of rudimentary flags to indicate
#  the various connection types.  But they are also
#  used when printing the genome, so their values should
#  make SOME sense (it's actually pretty hard to come
#  up with good, one-character representations for all
#  these things). 
#
our $SOURCE  = 'S';
our $SINK    = 'K';
our $LLA_IN  = 'L';
our $LLA_SRC = 's';
our $LLA_SNK = 'k';

# Mutation flags
our $NOISE_MUTATION     = 'n';
our $CURRENT_MUTATION   = 'c';
our $NON_MUTATION       = '-';  # NOTE: Not currently mutated
our $NONCODING_MUTATION = '-';  # NOTE: Not currently mutated
our $LLA_IN_MUTATION    = 'i';
our $LLA_OUT_MUTATION   = 'o';  # NOTE: Not currently mutated

# Internal representation of the connection string
our $encoding_seperator = ':';  # Internal seperator (NOTE: do not use a dash, it will be mistaken for NULL)
our $noncoding_symbol   = '-';  # Print version of the seperator


# ---------- Hardware encoding ---------

# Current
our $min_current = $NULL;
our $max_current = $NULL;

# Used by the sources and sinks
our $eac_current_encoding_mask  = "%03x";  # EAC
our $ueac_current_encoding_mask = "%04d";  # uEAC

# ASCII encoding for current (ddd, dddd)
our $eac_hardware_current_max  = 1023;
our $ueac_hardware_current_max = 4095;

# hardware
our $SLEEP_TIME = 0.05;     # Time in seconds
our $EAC_PORT   = 17000;    # Port of the EAC (hardware v1)

# Number of connection types
our $num_types    = 5;
our $min_position = $NULL;
our $max_position = $NULL;

# Loggging parameters
$datadir_prefix     .= $datadir_seperator;   # Build the prefix now
our $datadir_open    = $FALSE;
our $current_datadir = $NULL;
our $last_id         = $NULL;

# Socket and file management
# FIXME
our @state;
our $READ  = 100;
our $WRITE = 110;
our $feedback_adjustment  = $NULL;
our $statefile_open       = $FALSE;
our $socket_open          = $FALSE;
our $serial_port_open     = $FALSE;
our $SerialPort;

# Perl will complain without this
return $TRUE;
