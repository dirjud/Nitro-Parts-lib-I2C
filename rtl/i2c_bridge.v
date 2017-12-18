
module i2c_bridge
  #(parameter NUM_CLK_CYCLES_TO_SWITCH=10)
  (
   input clk,
   input resetb,
   input enable,
   inout sda_master,
   inout scl_master,
   inout sda_slave,
   inout scl_slave
   );

   reg [1:0] state;
   localparam STATE_IDLE = 0, STATE_MASTER = 1, STATE_SLAVE = 2;

   reg 	     oe_slave, oe_master, sda_slave_in, sda_master_in, scl_master_in;
   reg [3:0] cnt;
   
   always @(posedge clk or negedge resetb) begin
      if(!resetb) begin
	 state <= STATE_IDLE;
	 oe_master <= 0;
	 oe_slave <= 0;
	 cnt <= 0;
	 sda_slave_in <= 0;
	 sda_master_in <= 0;
	 scl_master_in <= 0;
      end else begin
	 sda_slave_in <= sda_slave;
	 sda_master_in <= sda_master;
	 scl_master_in <= scl_master;
	 if(!enable) begin
	    state <= STATE_IDLE;
	    oe_master <= 0;
	    oe_slave <= 0;
	    cnt <= 0;
	 end if(state == STATE_IDLE) begin
	    oe_master <= 0;
	    oe_slave  <= 0;
	    cnt <= 0;
	    if(sda_master_in == 0) begin
	       state <= STATE_MASTER;
	    end else if(sda_slave_in == 0) begin
	       state <= STATE_SLAVE;
	    end
	    
	 end if(state == STATE_MASTER) begin
	    oe_master <= 0;
	    if(sda_master_in == 1) begin
	       cnt <= cnt + 1;
	       oe_slave <= 0;
	       if(sda_slave_in == 1 || cnt >= NUM_CLK_CYCLES_TO_SWITCH) begin // wait for slave to go high
		  state <= STATE_IDLE;
	       end
	    end else begin
	       oe_slave  <= 1;
	    end
	    
	 end if(state == STATE_SLAVE) begin
	    oe_slave  <= 0;
	    if(sda_slave_in == 1) begin
	       cnt <= cnt + 1;
	       oe_master <= 0;
	       if(sda_master_in == 1 || cnt >= NUM_CLK_CYCLES_TO_SWITCH) begin
		  state <= STATE_IDLE;
	       end
	    end else begin
	       oe_master <= 1;

	    end
	 end 
      end
   end

   assign scl_slave  = (scl_master_in == 0) ? 0 : 1'bz;
   assign sda_slave  = (oe_slave  && sda_master_in == 0) ? 0 : 1'bz;
   assign sda_master = (oe_master && sda_slave_in  == 0) ? 0 : 1'bz;
  
endmodule
