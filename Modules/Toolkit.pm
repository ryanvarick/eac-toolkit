#
# TOOLKIT.PM - General tools and utilities used by the toolkit.
#
#
# Copyright (C) 2006 Ryan R. Varick <toolkit@indiana.edu>
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of
# the License, or (at your option) any later version.
#
#

package Toolkit;

use diagnostics;
use strict;
use warnings;

use POSIX qw(ceil floor);



# ====================[ CONFIGURATION ]====================

use constant TRUE  => (1 == 1);
use constant FALSE => (0 == 1);
use constant NULL  => -1;

our $VERSION       =  '1.0.0';
our $FEEDBACK_ON   =  TRUE;

# if enabled, this will use the standard toolkit crash handler
#  when a module fails to load
our $CATCH_MODULE_ERRORS = TRUE;

my %error_table = 
    (

     'E_BAD_HARDWARE_MODE'    =>  'Hardware failed to initialize properly.',
     'E_BREAK_ENCOUNTERED'    =>  'Terminated by user (CTRL+C).',
     'E_GENE_OUT_OF_BOUNDS '  =>  'Gene index is out-of-bounds.',
     'E_GENERAL'              =>  'General error encountered.',
     'E_INVALID_ARGUMENT'     =>  'Invalid argument received.',
     'E_INVALID_GENE_TYPE'    =>  'Invalid gene type encountered.',
     'E_MODULE_NOT_FOUND'     =>  'A required module is not properly installed.',
     'E_NETWORK_ERROR'        =>  'Network error, see details below.',
     'E_UNHANDLED_EXCEPTION'  =>  'Unhandled exception, see details below.',
     'E_UNKNOWN_DRIVER_MODE'  =>  'Driver mode not recognized.',
     'E_UNSUPPORTED_LAYOUT'   =>  'Unsupported hardware layout encountered.',
     'E_UNSUPPORTED_GS_MODE'  =>  'Unsupported print mode requested.',

    );

my $timer_start;
my $timer_end;

# ====================[ END CONFIGURATION ]=====================







# ---------------------[ Timer ]--------------------

#
# *_TIMER - Start and stop the timer.
#
#  args:    none
#  returns: nothing
#
sub start_timer()
{
    $timer_start = time();
    return $timer_start;
}

sub stop_timer()
{
    $timer_end = time();
    return $timer_end;
}

#
# GET_RUNNING_TIME - Returns the time the timer has been
#  running, in seconds.
#
#  args:    none
#  returns: running time in seconds
#
sub get_elapsed_time() 
{
    return $timer_end - $timer_start;
}



# --------------------[ Print Handlers ]--------------------

#
# PRINTD - Generic debug wrapper.
#
#  args:    printable string, optional prefix override
#  returns: nothing
#
#  NOTE: This routine will automatically prepend the calling
#        subroutine name unless the override flag is present.
#
sub printd($;$)
{
    # get the calling subroutine and construct the debug variable
    my $caller    = Toolkit::get_subroutine(1);
    my @pieces    = split('::', $caller);
    my $debug_var = $pieces[0] . '::DEBUG_ON';

    # check for prefix omission
    my $prefix = '';
    unless(defined($_[1]))
    {
	$prefix = $caller . '(): ';
    }

  PRINT:
    {
	no strict 'refs';
	if(${$debug_var} eq TRUE)
	{
	    Toolkit::printf($prefix . $_[0]);
	}
    }
}

#
# PRINTF - General feedback wrapper.
#
#  args:    printable string
#  returns: nothing
#
sub printf($)
{
    if($Toolkit::FEEDBACK_ON eq TRUE)
    {
	print $_[0];
    }
}



# --------------------[ Miscellaneous ]----------------------

#
# BREAK_HANDLER - Handles user interrrupts.
#
#  args:    none
#  returns: nothing
#
sub break_handler()
{
    Toolkit::crash('E_BREAK_ENCOUNTERED');
}

#
# CRASH - A slight improvement on 'die'.
#
#  args:    error code, details
#  returns: nothing
#
sub crash($;$)
{
    my $flag = 'E_GENERAL';
    if(defined $_[0]) { $flag = $_[0]; }

    my $details = '<none specified>';
    if(defined $_[1]) { $details = $_[1]; }

    my $subroutine = Toolkit::get_subroutine(1);
    if(defined($subroutine)) { $subroutine .= '()'; }
    else { $subroutine = '<none specified>'; }

    print STDERR "\n";
    print STDERR "-----------------------------------------------------------\n";
    print STDERR " PROGRAM ERROR:\t $error_table{$flag}\n";
    print STDERR " Error flag:\t $flag\n";
    print STDERR " Originated in:\t $subroutine\n";
    print STDERR " Crash details:\t $details\n";
    print STDERR "-----------------------------------------------------------\n";
    print STDERR "\n";

    unless($flag eq 'E_BREAK_ENCOUNTERED')
    {
	print STDERR " NOTE: If you are seeing this error message, you may have uncovered\n";
	print STDERR " a bug. Email me at <toolkit\@ryanvarick.com> and I'll look into it.\n";
	print STDERR "\n";
    }

    die("Stopping with errors.  Call trace follows:\n");
}

#
# GET_SUBROUTINE - Returns the name of a requested subroutine.
#
#  args:    stack depth of the subroutine to look up
#  returns: package-qualified subroutine name
#
sub get_subroutine($)
{
    my $depth = $_[0] + 1;
    my($pack, $filename, $line, $subroutine, 
       $hasargs, $wantarray, $evaltext, $is_require, $hints, $bitmask) = caller($depth);
    return $subroutine;
}

#
# LOAD_MODULE - Tries to load external libraries.
#
#  args:    module to load
#  returns: nothing
#
sub load_module($)
{
    my $module = $_[0];
    my $exec_string = "use $module";

    eval $exec_string;

    # we know what a module error looks like, so it is safe
    #  to dissect and reformat it here
    if($@) 
    {
	   my @pieces = split(/\(/, $@);

	   if($Toolkit::CATCH_MODULE_ERRORS eq TRUE)
	   {
#		  Toolkit::crash('E_MODULE_NOT_FOUND', $pieces[0] . '...');

	       Toolkit::printf("Module not found.\n");
	       Toolkit::printf("Module not found.\n");
	       Toolkit::printf("Module not found.\n");
		 exit;

	   }
	   else
	   {
		  die @$;
	   }
    }
}

#
# RANDOM - Returns a random number between two values.
#
#  args:    lower bound, upper bound
#  returns: random number
#
#  NOTE: This is necessary because Perl's rand() function returns
#        a number between 0-$seed.  Sometimes that isn't what we
#        want.  I probably reinvented the wheel here. :-/
#
sub random($$) 
{
    my $lower  = $_[0];
    my $upper  = $_[1];
    my $random = 0.0;

    do 
    {
	$random = rand($upper);
    }
    while($random < $lower);

    return $random;
}

#
# RANDINT - Returns a random integer between (inclusive) two integers.
#
#  args:    lower bound, upper bound
#  returns: random integer
#
#  NOTE: This function wraps the return value from random() in an integer
#        cast.  We have to be careful here because int() works like the floor
#        function in Perl.  Thus the provided upper bound will be returned only
#        very rarely.  To compensate, we pass ($upper + .999) to random().  This
#        ensures that the upper bound is returned more regularly, while taking
#        care to never actually return a value outside of the provided range
#        (upper+1, for example).  That would not be cool at all!
#
sub randint($$) 
{
    my $lower = $_[0];
    my $upper = $_[1] + .999;
    return int(&random($lower, $upper));
}

#
# TRANSLATE_TO_COORDS - Translates an index into X-Y coordinates.
#
#  args:    index, x-axis length
#  returns: x,y coordinates, or NULL if x or y is < 0
#
sub translate_to_coords($$)
{
    my $index = $_[0];
    my $x_len = $_[1];

    my $x = $index % $x_len;
    my $y = ceil($index / $x_len);

    # sanity check lower bound (TODO: check upper bound)
    if($x < 0 || $y < 0) { return NULL; }

    return ($x, $y);
}

#
# TRANSLATE_TO_INDEX - Translates X-Y coordinates to an index.
#
#   args:    x-y index
#   returns: index
#
sub translate_to_index($$)
{
    my $x = $_[0];
    my $y = $_[1];

    return $x * $y;
}

#
# QUIT - Exits the program.
#
#  args:    none
#  returns: nothing
#
sub quit()
{
    Toolkit::printf("Exiting.\n");
    exit(0);
}

return TRUE;
