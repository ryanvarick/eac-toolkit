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


package config;

use diagnostics;
use strict;
use warnings;



our $NULL  = -1;
our $TRUE  =  1;
our $FALSE =  0;

# Program version
our $VERSION = '2.1.0-alpha1';



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
our $DEBUG_COMM    = $FALSE;                 # Communication specific debugging messages
our $DEBUG_LOGGING = $FALSE;                 # Logging specific debugging messages
our $DEBUG_GA      = $FALSE;                 # GA specific debugging messages

our $TEST_MODE = $FALSE;                     # Disable communication with the EAC





# =============== GA PARAMETERS ===============

our $max_generations = 10;



