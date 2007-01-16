package Term;
require 5.000;
require Exporter;

use strict;
use Term::ReadKey;

our @ISA = qw(Exporter);
our @EXPORT = qw(Complete);
our $VERSION = '1.5.0';

#
# updates = Ryan R. Varick
#
#  TODO:
#    - added left/right arrow support
#    - add space after succesful completion
#

#      @(#)complete.pl,v1.2            (me@anywhere.EBay.Sun.COM) 09/23/91

=head1 NAME

Term::Complete - Perl word completion module

=head1 SYNOPSIS

    $input = Complete('prompt_string', \@completion_list);
    $input = Complete('prompt_string', @completion_list);

=head1 DESCRIPTION

This routine provides word completion on the list of words in
the array (or array ref).

The tty driver is put into raw mode and restored using an operating
system specific command, in UNIX-like environments C<stty>.

The following command characters are defined:

=over 4

=item E<lt>tabE<gt>

Attempts word completion.
Cannot be changed.

=item ^D

Prints completion list.
Defined by I<$Term::Complete::complete>.

=item ^U

Erases the current input.
Defined by I<$Term::Complete::kill>.

=item E<lt>delE<gt>, E<lt>bsE<gt>

Erases one character.
Defined by I<$Term::Complete::erase1> and I<$Term::Complete::erase2>.

=back

=head1 DIAGNOSTICS

Bell sounds when word completion fails.

=head1 BUGS

The completion character E<lt>tabE<gt> cannot be changed.

=head1 AUTHOR

Wayne Thompson

=cut


our($break_handler, $complete, $kill, $erase1, $erase2, $tty_raw_noecho, $tty_restore, $stty, $tty_safe_restore);
our($tty_saved_state) = '';

# added for history
my @history;
my $history_ptr = -1;
my $history_top = -1;
my $aborted = 0;

CONFIG: {
    $break_handler = '';
    $complete = "\004";
    $kill     = "\025";
    $erase1   = "\177";
    $erase2   = "\010";
    foreach my $s (qw(/bin/stty /usr/bin/stty)) {
	if (-x $s) {
	    $tty_raw_noecho = "$s raw -echo";
	    $tty_restore    = "$s -raw echo";
	    $tty_safe_restore = $tty_restore;
	    $stty = $s;
	    last;
	}
    }
}

sub Complete {
    my($prompt, @cmp_lst, $cmp, $test, $l, @match);
    my ($return, $r) = ("", 0);

    $return = "";
    $r      = 0;
    $history_ptr = $history_top;

    $prompt = shift;
    if (ref $_[0] || $_[0] =~ /^\*/) {
	@cmp_lst = sort @{$_[0]};
    }
    else {
	@cmp_lst = sort(@_);
    }

    # Attempt to save the current stty state, to be restored later
    if (defined $stty && defined $tty_saved_state && $tty_saved_state eq '') {
	$tty_saved_state = qx($stty -g 2>/dev/null);
	if ($?) {
	    # stty -g not supported
	    $tty_saved_state = undef;
	}
	else {
	    $tty_saved_state =~ s/\s+$//g;
	    $tty_restore = qq($stty "$tty_saved_state" 2>/dev/null);
	}
    }
    system $tty_raw_noecho if defined $tty_raw_noecho;
    LOOP: {
        local $_;
	my $tab_count = 0;
        print($prompt, $return);
        while (($_ = getc(STDIN)) ne "\r") {

	    # TODO: Reset history pointer on loop
            CASE: {

                # (TAB) attempt completion
                $_ eq "\t" && do {

		    # 2 tabs = completion list
		    ++$tab_count eq 2 && do {
			print(join("\r\n", '', grep(/^\Q$return/, @cmp_lst)), "\r\n");
			print("\r\n");
			$tab_count = 0;
			redo LOOP;
		    };

                    @match = grep(/^\Q$return/, @cmp_lst);
                    unless ($#match < 0) {
                        $l = length($test = shift(@match));
                        foreach $cmp (@match) {
                            until (substr($cmp, 0, $l) eq substr($test, 0, $l)) {
                                $l--;
                            }
                        }
                        print("\a");
                        print($test = substr($test, $r, $l - $r));
                        $r = length($return .= $test);
                    }
                    last CASE;
                };

		# If we make it to this point, we can reset the TAB counter
		$tab_count = 0;

		# Trap control characters
		#  TODO: migrate this to "\000" format
		#  TODO: history size
		#  TODO: 67 = right
		#  TODO: 68 = left

# Does not work:
#		$_ eq "\066" && do {
#		    print "UP ARROW!!!";
#		};

		ord($_) == 27 && do {

		    my $code = ReadKey -1;

		    # trap raw escape
		    unless(defined $code) { last CASE; }

		    if(ord($code) == 91)
		    {
			my $action = ord(ReadKey -1);

			$action == 65 && $history_ptr > -1 && do {
			    $return = $history[$history_ptr--];

			    # clear and replace input buffer
			    for(my $i = 0; $i < $r; $i++) { print "\b \b"; }
			    print $return;

			    $r = length($return);
			};

 			$action == 66 && $history_ptr < $history_top && do {

			    # take us back to a blank line at history_top
			    #  TODO: Save current buffer before replacement [?]
			    if(++$history_ptr == $history_top) { $return = ''; }
			    else { $return = $history[$history_ptr + 1]; }

 			    for(my $i = 0; $i < $r; $i++) { print "\b \b"; }
 			    print $return;

 			    $r = length($return);
 			};
		    }
		    last CASE;
		};

		# (^C)
		$_ eq "\003" && do {
		    $aborted = 1; # set the kill flag
		    last LOOP;
		};

                # (^U) kill
                $_ eq $kill && do {
                    if ($r) {
                        $r	= 0;
			$return	= "";
                        print("\r\n");
                        redo LOOP;
                    }
                    last CASE;
                };

                # (DEL) || (BS) erase
                ($_ eq $erase1 || $_ eq $erase2) && do {
                    if($r) {
                        print("\b \b");
                        chop($return);
                        $r--;
                    }
                    last CASE;
                };

                # printable char
                ord >= 32 && do {
                    $return .= $_;
                    $r++;
		    print;
                    last CASE;
                };

            } # // last case
        } # // end while

	# If we're outside the while-loop, we hit a "\r"
	$history_top++;
    }

    # system $tty_restore if defined $tty_restore;
    if (defined $tty_saved_state && defined $tty_restore && defined $tty_safe_restore)
    {
	system $tty_restore;
	if ($?) {
	    # tty_restore caused error
	    system $tty_safe_restore;
	}
    }
    print("\n");

    # check for user abort
    if($aborted eq 1)
    {
	die("Aborted.\n") if($break_handler eq '');
	no strict 'refs';
	&{$break_handler}();
    }

    # push command
    $history[$history_top] = $return;

    $return;
}

1;
