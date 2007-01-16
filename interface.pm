#!/usr/bin/perl -w
#
# INTERFACE.PM - An interface for direct manipulation of, and
#  interaction with, the extended analog computers produced by
#  Indiana University.
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
# TODO:
#   - add option to log debug output
#   - type initialization / mutation
#   - hierarchical logging (by generation)
#
#   - driver: should I prefix API driver calls with something?
#   - driver: everything should be unset on mode change (genome_length, etc)
#   - driver: driver should set debug flag for driver subclasses
#
# TODO (ga):
#  - replace $CAPS_VARS with CONSTANTS
#  - test parameter permutations
#  - variable crossover regions
#     - init. region length checking (this is important, because crossover
#       is biased toward the the front of the genome right now)
#

package interface;

use diagnostics;
use strict;
use warnings;

# Toolkit components
use Modules::Toolkit;            # common utilities
use Modules::Hardware::Driver;   # hardware interface (invokes: eac.pm, ueac.Pm, simulator.pm)
use Modules::GA;                 # genetic algorithm (invokes: fitness.pm)
use Modules::Logging;            # logging utilities
use Modules::Term;               # terminal manager

#Toolkit::load_module("Modules::Hardware::Driver");
#Toolkit::load_module("Modules::GA");
#Toolkit::load_module("Modules::Logging");
#Toolkit::load_module("Modules::Term");



# ====================[ CONFIGURATION ]====================

use constant TRUE  => (1 == 1);
use constant FALSE => (0 == 1);
use constant NULL  => -1;

our $VERSION       =  '3.0.0';
our $DEBUG_ON      =  TRUE;

# prompt configuration
my $COMMAND_PROMPT  = '> ';
my $TOKEN_DELIMITER = ' ';
my $EXTRA_NEWLINE   = TRUE;

# handler for user interrupt (CTRL+C)
my $break_handler = 'Toolkit::break_handler';

# default driver and eac to initialize
my $DEFAULT_DRIVER = $Driver::EAC_SIMULATOR_DRIVER;
my $DEFAULT_EAC    = $Driver::NULL_EAC;



# --------------------[ Interface definitions ]--------------------
my %commands;
my @valid_tokens;

# command flag declarations
use constant HANDLER        =>  'handler';             # REQUIRED: subroutine to process the token

use constant HELP_MSG       =>  'help_msg';            # standard: contextual help entry
use constant MIN_ARGS       =>  'min_args';            # standard: minimum expected arguments
use constant MAX_ARGS       =>  'max_args';            # standard: maximum accepted arguments
use constant VALID_ARGS     =>  'valid_args_list';     # standard: list of valid arguments

# specific declarations
use constant TOGGLE_VAR     =>  'toggle_var';          # toggle: variable to toggle
use constant PARAMETER_VAR  =>  'parameter_var';       # parameter: variable to update
use constant STATUS_MSG     =>  'status_msg';          # toggle/parameter: reports the status of the variable


# ====================[ END CONFIGURATION ]====================







interface::main();

#
# INIT_INTERFACE - Initializes the command list.
#
#  args:    none
#  returns: nothing
#
#  NOTE: Some commands may have hardware-dependent parameters.
#        Packaging command intialization in a subroutine allows
#        for easier re-definition on hardware mode change.
#
#  NOTE: See the command flag declarations in the configuration
#        section above.
#
sub init_interface()
{
    %commands = 
	(

	 # ---------------[ Main program controls ]----------------

	 'ga' =>
	    {
		HANDLER   =>  'ga_handler',
		HELP_MSG  =>  'Runs the genetic algorithm. An optional argument tells the GA to perform successive runs.',

		MIN_ARGS  =>  0,
		MAX_ARGS  =>  1,
	    },

	 'help' =>
	    {
		HANDLER    =>  'help_handler',
		HELP_MSG   =>  'Shows a help message for a command. Press TAB twice for the list of commands ' .
		    'or type \'help all\' for the manual.',

		MIN_ARGS   =>  0,
		MAX_ARGS   =>  1,
	    },

	 'quit' =>
	    {
		HANDLER   =>  'quit_handler',
		HELP_MSG  =>  'Exits the program.',
	    },



	 # ---------------[ Hardware configuration ]----------------

	 'driver' =>
	    {
		HANDLER     =>  'driver_handler',
		HELP_MSG    =>  'Specifies the EAC driver mode (valid modes: ' . lc(join(', ', @Driver::driver_list)) . ').',

		MIN_ARGS    =>  0,
		MAX_ARGS    =>  1,

		VALID_ARGS  =>  lc(join($TOKEN_DELIMITER, @Driver::driver_list)),
	    },

	 'connect' =>
	    {
		HANDLER     =>  'connect_handler',
		HELP_MSG    =>  'Specifies an EAC to connect to (valid EACs: ' . lc(join(', ', @Driver::eac_list)) . ').',

		ENABLED     =>  $Driver::attempt_device_connection,
		
		MIN_ARGS    =>  1,
		MAX_ARGS    =>  1,

		VALID_ARGS  =>  lc(join($TOKEN_DELIMITER, @Driver::eac_list)),
	    },

	 'disconnect' =>
	    {
		HANDLER     =>  'disconnect_handler',
		HELP_MSG    =>  'Disconnect from the current EAC.',

		ENABLED     =>  $Driver::attempt_device_connection,

		MIN_ARGS    =>  0,
		MAX_ARGS    =>  0,
	    },



	 # ---------------[ Hardware interaction ]----------------

	 'reset' =>
	    {
		HANDLER     =>  'reset_handler',
		HELP_MSG    =>  'Resets the current EAC (either by removing all connections or resetting them to zero).',

		MIN_ARGS    =>  0,
		MAX_ARGS    =>  0,
	    },

	 # TODO: source/sink can probably use the same handler, differentiated by the token
	 'source' =>
	    {
		HANDLER     =>  'source_handler',
		HELP_MSG    =>  'Specifies the EAC driver mode (valid modes: ' . lc(join(', ', @Driver::driver_list)) . ').',

		MIN_ARGS    =>  2,
		MAX_ARGS    =>  2,

#		VALID_ARGS  =>  lc(join($TOKEN_DELIMITER, @Driver::driver_list)),
	    },



	 # ---------------[ Parameters ]----------------

	 #
	 # NOTE: For the parameter message, 'VALUE' will be 
	 #       interpolated with the runtime value of PARAMATER_VAR.
	 #
	 # NOTE: There is no built-in individual argument checking
	 #       for parameters.
	 #

	 'max-generations' =>
	    {
		HANDLER        =>  'parameter_handler',
		HELP_MSG       =>  'Specifies the maximum number of generations the GA breed.',

		PARAMETER_VAR  =>  'GA::max_generations',

		MIN_ARGS       =>  0,
		MAX_ARGS       =>  1,

		STATUS_MSG     =>  "Maximum number of generations is VALUE.",
	    },

	 'population-size' =>
	    {
		HANDLER        =>  'parameter_handler',
		HELP_MSG       =>  'Specifies the number of genomes in each generation.',

		PARAMETER_VAR  =>  'GA::population_size',

		MIN_ARGS       =>  0,
		MAX_ARGS       =>  1,

		STATUS_MSG     =>  "Using VALUE genomes per generation.",
	    },



	 # ---------------[ Feedback control (toggles) ]---------------

	 'feedback' =>
	    {
		HANDLER       =>  'toggle_handler',
		HELP_MSG      =>  'Handles nearly all program feedback, disable this for silent running.',

		TOGGLE_VAR    =>  'Toolkit::FEEDBACK_ON',

		MIN_ARGS      =>  0,
		MAX_ARGS      =>  1,
		VALID_ARGS    =>  'on off',
		
		STATUS_MSG    =>  "Feedback VALUE.",
	    }, 

	 'debug-breeding' =>
	    {
		HANDLER       =>  'toggle_handler',
		HELP_MSG      =>  'Enables or disables breeding debugging information.',

		TOGGLE_VAR    =>  'GA::DEBUG_BREEDING_ON',

		MIN_ARGS      =>  0,
		MAX_ARGS      =>  1,
		VALID_ARGS    =>  'on off',

		STATUS_MSG    =>  "GA breeding diagnostic feedback VALUE.",
	    }, 

	 'debug-ga' =>
	    {
		HANDLER       =>  'toggle_handler',
		HELP_MSG      =>  'Enables or disables high-level GA debugging information.',
		
		TOGGLE_VAR    =>  'GA::DEBUG_ON',

		MIN_ARGS      =>  0,
		MAX_ARGS      =>  1,
		VALID_ARGS    =>  'on off',

		STATUS_MSG    =>  "General GA diagnostic feedback VALUE.",
	    }, 

	 'debug-genome' =>
	    {
		HANDLER       =>  'toggle_handler',
		HELP_MSG      =>  'Enables or disables genome-specific debugging information.',

		TOGGLE_VAR    =>  'GA::DEBUG_GENOME_ON',

		MIN_ARGS      =>  0,
		MAX_ARGS      =>  1,
		VALID_ARGS    =>  'on off',

		STATUS_MSG    =>  "GA genome diagnostic feedback VALUE.",
	    }, 

	 'debug-hardware' =>
	    {
		HANDLER       =>  'toggle_handler',
		HELP_MSG      =>  'Enables or disables hardware debugging information.',

		TOGGLE_VAR    =>  'Driver::DEBUG_ON',

		MIN_ARGS      =>  0,
		MAX_ARGS      =>  1,
		VALID_ARGS    =>  'on off',

		STATUS_MSG    =>  "Hardware diagnostic feedback VALUE.",
	    }, 

	 'debug-interface' =>
	    {
		HANDLER       =>  'toggle_handler',
		HELP_MSG      =>  'Enables or disables interface debugging information.',

		TOGGLE_VAR    =>  'interface::DEBUG_ON',

		MIN_ARGS      =>  0,
		MAX_ARGS      =>  1,
		VALID_ARGS    =>  'on off',

		STATUS_MSG    =>  "Interface diagnostic feedback VALUE.",
	    }, 

	 );

    # Now that the command hash is defined, define the token array
    #  for use by Term::Complete
    Toolkit::printd("Processing command tokens...\n");
    my $i = 0;
    foreach my $key (keys %commands)
    {
	if(defined($commands{$key}{'ENABLED'}) && $commands{$key}{'ENABLED'} eq FALSE)
	{
	    Toolkit::printd("'$key' (disabled)\n");
	}

	# ignore disabled commands
	else
	{
	    Toolkit::printd("'$key'\n");
	    $valid_tokens[$i++] = $key;
	}
    }
    @valid_tokens = sort(@valid_tokens);
}



#
# MAIN - Starts the interface.
#
#  args:    none
#  returns: nothing
#
sub main
{
    Toolkit::printf("\n");
    Toolkit::printf("EAC Toolkit v$VERSION\n");
    Toolkit::printf("\n");
    Toolkit::printf("Before getting started, please take a look at the usage manual. If you\n");
    Toolkit::printf("have comments or questions, please email me at <toolkit\@ryanvarick.com>.\n");
    Toolkit::printf("\n");
    Toolkit::printf("Type \"help\" for command information or \"quit\" to exit.\n");
    Toolkit::printd("\n", 0);
      
    # add hooks to catch interrupts
    $SIG{'INT'}          = $break_handler;
    $Term::break_handler = $break_handler;

    # initialize hardware
    Driver::init_driver($DEFAULT_DRIVER);
    Driver::connect_to_device($DEFAULT_EAC);

    # start the logger
#    Logging::init_logger();

    # build the interface
    interface::init_interface();

  LOOP:
    {
	# here comes the pseudo-shell...
	Toolkit::printf("\n") if($EXTRA_NEWLINE eq TRUE);
	my $prompt;
	if($Toolkit::FEEDBACK_ON eq TRUE) { $prompt = $COMMAND_PROMPT; }
	else { $prompt = ''; }

	# get and process a line of input
	my $raw_string = &Term::Complete($prompt, @valid_tokens);
	my @args       = split($TOKEN_DELIMITER, $raw_string);
	my $token      = shift(@args);

	# handle null tokens
	unless(defined $token)
	{
	    Toolkit::printd("Ignoring null input.\n");
	    redo LOOP;
	}

	# handle invalid tokens
	unless(exists $commands{$token})
	{
	    Toolkit::printd("Token '$token' not recognized.\n");
	    Toolkit::printf("Command not recognized.  Type \"help\" for usage or \"quit\" to exit.\n");
	    redo LOOP;
	}
	Toolkit::printd("Token '$token' is valid.\n");

	# handle valid tokens (try to load extended token information)
	my $handler         = $commands{$token}{HANDLER   };
	my $help_msg        = $commands{$token}{HELP_MSG  };
	my $min_args        = $commands{$token}{MIN_ARGS  };
	my $max_args        = $commands{$token}{MAX_ARGS  };
	my $valid_args_list = $commands{$token}{VALID_ARGS};

	# check the argument count, if defined
	if(defined($min_args) && (@args < $min_args || @args > $max_args))
	{
	    my $error = 'Too many';
	    if(@args < $min_args) { $error = 'Too few'; }

	    my $arguments = "$min_args argument";
	    if($min_args > 1)          { $arguments .= 's'; }
	    if($min_args ne $max_args) { $arguments  = "between $min_args and $max_args arguments"; }

	    Toolkit::printf("$token: $error arguments recieved, expected $arguments. Try 'help $token' for assistance.\n");

	    redo LOOP;
	}
	Toolkit::printd("Argument count verified.\n");

	# check individual arguments, if defined
	if(defined($valid_args_list))
	{
	    my @valid_args = split($TOKEN_DELIMITER, $valid_args_list);
	    foreach my $candidate(@args)
	    {
		my $verified = FALSE;
		foreach my $valid(@valid_args)
		{
		    $verified = TRUE if($candidate eq $valid);
		    Toolkit::printd("Verifying argument: '$candidate'=='$valid'\n");
		}
		unless($verified eq TRUE)
		{
		    Toolkit::printf("$token: Argument '$candidate' is not valid, expected one of: " .
				    join(', ', @valid_args) . ".\n");
		    redo LOOP;
		}
	    }
	}
	Toolkit::printd("Individual arguments verified, passing to $handler()...\n");

      JUMP:
	{
	    no strict 'refs';

	    # pass the input to the handler
	    my $result = &{$handler}($token, @args);
	    Toolkit::printf("$token: $result") if (defined($result));
	}

	redo LOOP;
    }
}







# ====================[ TOKEN HANDLERS ]====================

#
# NOTE: Token handlers are expected to return a string for 
#       user feedback.  To override this behavior, use a naked
#       return statement.
#



#
# PARAMETER_HANDLER - Set the value of a variable.
#
#  args:    tokenized input array
#  returns: feedback
#
sub parameter_handler()
{
    no strict 'refs';

    my $token  = $_[0];
    my $value  = $_[1];
    my $var    = $commands{$token}{PARAMETER_VAR};
    my $report = $commands{$token}{STATUS_MSG};

    ${$var} = $value if(defined($value));

    # read the variable, update the message, print, and return
    my $state = ${$var};
    $report   =~ s/VALUE/$state/;
    return $report . "\n";
}

#
# TOGGLE_HANDLER - Toggle a variable on or off.
#
#  args:    tokenized input array
#  returns: feedback
#
sub toggle_handler()
{
    no strict 'refs';

    my $token  = $_[0];
    my $value  = $_[1];
    my $var    = $commands{$token}{TOGGLE_VAR};
    my $report = $commands{$token}{STATUS_MSG};

    if(defined($value))
    {
	if($value eq 'on')     { ${$var} = TRUE;  }
	elsif($value eq 'off') { ${$var} = FALSE; }
	else { Toolkit::crash('E_INVALID_ARGUMENT', $value); }
    }
    
    # read the variable, update the message, print, and return
    my $state  = ${$var};
    my $status = 'disabled';
    if($state eq TRUE) { $status = 'enabled'; }
    $report    =~ s/VALUE/$status/;

    return $report . "\n";
}



# ---------------[ Main program handlers ]---------------

sub ga_handler()
{
    # TODO: do something with this return value
    my $status = GA::run();
    return;
}

sub help_handler()
{
    my $token = $_[1];
    if(defined($token)) 
    {
	if($token eq 'all')
	{
	    # TODO: show the manual
	    Toolkit::printf("$token: show all (TODO)\n");
	}
	elsif(exists($commands{$token}{HELP_MSG}))
	{
	    Toolkit::printf("$token: $commands{$token}{HELP_MSG}\n");
	}
	else
	{
	    Toolkit::printf("$token: No help available.\n");
	}
    }
    else
    {
	Toolkit::printf("help: On which command? Press TAB twice for the list of commands.\n");
    }
    return;
}

sub quit_handler()
{
    Toolkit::quit();
}



# --------------------[ Hardware handlers ]--------------------

#
# NOTE: These handlers are reponsible for safely initializing
#  the hardware.  Changing the driver mode handles most of the
#  the configuration.  For the most part, the EAC is blindly
#  saved to the Driver.
#
# FIXME: How to handle bad hardware modes (see crash statements)
#

sub driver_handler()
{
    my $driver = $_[1];
    my $report;

    if(defined($driver))
    {
	my $status = Driver::init_driver($driver);

	if($status eq $Driver::OK)
	{
	    $report = "Driver '$Driver::driver' ready.\n";
	    Toolkit::printd("Driver mode updated, resetting interface...\n");
	    interface::init_interface();	
	}
	else
	{
	    Toolkit::crash('E_BAD_HARDWARE_MODE', "status = $status");
	}
    }
    else
    {
	$report = "Current driver is '$Driver::driver'.\n";
    }
    return $report;
}

sub connect_handler()
{
    my $status = Driver::connect_to_device($_[1]);
    my $report;

    if($status eq $Driver::OK)
    {
	$report = "Connected to '$Driver::eac'.\n"; 
    }
    elsif($status eq $Driver::NA)
    {
	$report = "N/A for driver '$Driver::driver'.\n";
    }
    else 
    { 
	Toolkit::crash('E_BAD_HARDWARE_MODE', "status = $status");
    }
    return $report;
}

sub disconnect_handler()
{
    my $eac    = $Driver::eac;
    my $status =  Driver::disconnect_from_device();
    my $report;

    if($status eq $Driver::OK)
    {
	$report = "Disconnected from '$eac'.\n";
    }
    elsif($status eq $Driver::NA)
    {
	$report = "N/A for driver '$Driver::driver'.\n";
    }

    elsif($status eq $Driver::NA)
    {
	$report = "Not currently connected.\n";
    }
    else
    {
	Toolkit::crash('E_BAD_HARDWARE_MODE', "status = $status");
    }
    return $report;
}



# --------------------[ Hardware interaction handlers ]--------------------

sub reset_handler()
{
    Driver::reset();
    return "Simulator reset.\n";
}

sub source_handler()
{
    my $index = $_[1];
    my $value = $_[2];

    # TODO: sanity check input
    Driver::write_source($index, $value);
    Driver::read_source(1)
}

