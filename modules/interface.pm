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

# use diagnostics;
# use strict;
# use warnings;

# use config;

use Term::Complete;



my $input = Complete('> ', ['test', 'johhny', 'max-stuff']);







# tab = 9
# read()
# if(up, hist--), (down, hist++)
# elseif(left, right
use Term::ReadKey;

ReadMode 4;

while( (my $key = ReadKey(0)) ne 'q')
{
   if (ord($key) == 27)
     {
       my $code = ord(ReadKey -1);
       if ($code == 91)
         {
           my $action = ord(ReadKey -1);

           print "Left\n" if ( $action == 68 );
           print "Right\n" if ( $action == 67 );
           print "Up\n" if ( $action == 65 );
           print "Down\n" if ( $action == 66 );

         }
       else
         {
           print "Some other control key ?\n";
         }
      }
   else
      {
        print "$key " . ord($key) . "\n";
      }

}

ReadMode 0; 
