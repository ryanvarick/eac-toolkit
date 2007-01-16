
our $TYPE = $Driver::UEAC;


use constant NUM_ROWS  => 5;
use constant NUM_COLOS => 5;

















return 1;






# # --------------- Virtual serial port connections  ---------------

# #
# # NOTE: While there are two models of the EAC (foam and silicon),
# #  uEACs, are, as far as I know, all the same.  And while both
# #  versions of the EAC use the same network communication routines,
# #  the uEAC will eventually operate over both USB, and through a
# #  network proxy.  I suspect the latter versions will make use of
# #  the socket functions above.
# #

# #
# # OPEN_SERIAL_PORT - Maintains a virtual serial connection to a uEAC.
# #
# sub open_serial_port() {
#
#    if($TEST_MODE eq $TRUE) { return; }
#
#     # Open the serial port, if necessary
#     if($serial_port_open eq $FALSE) {
# 	$SerialPort = new Device::SerialPort($eac,1) or
# 	    &crash("open_serial_port(): Cannot open serial port: $!.\n");
# 	$SerialPort->databits(8);
# 	$SerialPort->parity("none");
# 	$SerialPort->stopbits(1);
# 	$SerialPort->baudrate(19200);
# 	$SerialPort->handshake("none");
# 	&printc("open_serial_port(): Serial port opened.\n");
# 	$serial_port_open = $TRUE;
#     }
#     else {
# 	&printc("open_serial_port(): Serial port already open.\n");
#     }
# }

# #
# # CLOSE_SERIAL_PORT - Closes the open serial port connection, if one exists.
# #
# sub close_serial_port() {
#     if($serial_port_open eq $TRUE) {
# 	$SerialPort->close() or 
# 	    &crash("close_serial_port(): Cannot close serial port connection.\n");
# 	$serial_port_open = $FALSE;
# 	&printc("open_serial_port(): Serial port closed.\n");
#     }
#     else {
# 	&printc("open_serial_port(): There is no serial port to close.\n");
#     }
# }
