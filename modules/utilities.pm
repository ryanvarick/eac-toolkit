#
# UTILITIES.PM - Miscellaneous functions.
#
#
# Copyright (C) 2005 Ryan R. Varick <rvarick@indiana.edu>
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of
# the License, or (at your option) any later version.
#

package utilities;

use diagnostics;
use strict;
use warnings;

use config;


my $TRUE  = $config::TRUE;
my $FALSE = $config::FALSE;



#
# BREAK_HANDLER - Routine to catch CTRL+C.
#
# NOTE: This used to call cleanup() to exit gracefully, but sometimes
#  cleanup() would fail, creating an infinite loop.  This now exits
#  ungracefully.  So don't use CTRL+C to exit unless the program hangs!
#
sub break_handler() {
    &printf("\n");
    &printf("\n");
    &printf("*** Break caught ***\n");
    &printf("\n");
    die "Exited with errors.";
}

#
# CLEANUP - Common tasks to perform before exiting.
#
# TODO: Rewrite this to allow module independence.
#
sub cleanup() {
    &close_statefile();
    &close_socket();
    &close_serial_port();
}

#
# CRASH - A *slight* improvement on die.
#
sub crash() {
    &printf("\n");
    &printf("ERROR: " . $_[0]);
    &printf("\n");
    &cleanup();
    die "Exited with errors.\n\n";
}

#
# PAUSE - Pause for a number of milliseconds.
#
sub pause() {
    my $time = $_[0] / 1000;
    select(undef, undef, undef, $time);
}

#
# RANDOM - Returns a random number between two values.
#
# NOTE: This is necessary because Perl's rand() function
#  returns a number between 0-$seed.  At least I think it does.
#  I probably reinvented the wheel here.
#
sub random() {
    my $lower  = $_[0];
    my $upper  = $_[1];
    my $random = 0.0;
    do {
	$random = rand($upper);
    }
    while($random < $lower);
    return $random;
}

#
# RANDINT - Returns a random integer between (inclusive) two integers.
#
# NOTE: This function wraps the return value from random() in an int() cast.
#  However, since Perl treats int() as a floor function and has no round()
#  function, the upper bound will be returned very, very rarely.  To
#  compensate, random() is instead seeded with the given $lower and
#  ($upper+.999).  This is sufficient to insure the actual upper bound
#  will be returned fairly regularly while taking care to never actually
#  return ($upper+1).  That would be bad!
#
sub randint() {
    my $lower = $_[0];
    my $upper = $_[1] + .999;
    return int(&random($lower, $upper));
}

#
# QUIT - Clean up and print a nice good bye message. Awww...
#
sub quit() {
    &cleanup();
    &printf("Exiting.\n");
    exit;
}



# ================ PRINT MACROS ===============

#
# PRINTC - Print communication debugging information, when enabled.
#
sub printc() {
    if($config::DEBUG_COMM eq $TRUE) {
	print 'COMM: ' . $_[0];
    }
}

#
# PRINTD - Print general debugging information, when enabled.
#
sub printd() {
    if($config::DEBUG eq $TRUE) {
	print $_[0];
    }
}

#
# PRINTH - Print help messages, when enabled.
#
# TODO: Incomplete (targeted for v2.1.0)
#
sub printh() {
#    if($SHOW_TIPS eq $TRUE) {
#	print $_[0];
#    }
}

#
# PRINTG - Print general GA debugging information, when enabled.
#
sub printg() {
    if($config::GA_FEEDBACK eq $TRUE) {
	print $_[0];
    }
}

#
# PRINTF - Print general feedback, when enabled.
#
sub printf() {
    if($config::FEEDBACK eq $TRUE) {
	print $_[0];
    }
}

#
# PRINTLOG - Print logging debugging information, when enabled.
#
sub printlog() {
    if($config::DEBUG_LOGGING eq $TRUE) {
	print 'LOGGING: ' . $_[0];
    }
}









return $TRUE;
