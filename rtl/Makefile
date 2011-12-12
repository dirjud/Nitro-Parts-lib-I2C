# Type 'make' to run the sim and then view the results by running the
# command 'gtkwave gray_count.lxt'
#
# This runs the simulation using icarus verilog.  'yum install iverilog'
#

SOURCES=tb.v i2c_master.v i2c_slave.v

tb: $(SOURCES)
	iverilog -o tb $(SOURCES)
	vvp tb 

clean:
	-rm -rf *~ *.vcd tb
