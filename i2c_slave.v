// Author: Lane Brooks
// Date: May 23, 2008
// Description: This implemenents an 8 bit address, 16 bit data i2c slave.

module i2c_slave
   (
    input clk,
    input reset_n,
    input [6:0] chip_addr,
    input [15:0] datai,
    output reg we,
    output reg [15:0] datao,
    output reg [7:0] reg_addr,
    output reg busy,
    input sda_in,
    output sda_out,
    output sda_oeb,
    input scl_in,
    output scl_out,
    output scl_oeb
    );

   parameter STATE_WAIT=0,
	     STATE_SHIFT=1,
	     STATE_ACK=2, 
	     STATE_ACK2=3,
	     STATE_WRITE=4,
	     STATE_CHECK_ACK=5,
	     STATE_SEND=6;
   
   reg [2:0] state;
   reg 	  scl_s, sda_s, scl_ss, sda_ss, sda_reg;
   reg [7:0]  sr;
   reg [1:0]  transfer_count;
   reg 	      rw_bit;
   reg [15:0] sr_send;
   reg 	      nack;
   reg [6:0]  chip_addr_reg;
   
//   assign sda = (sda_reg) ? 1'bz : 1'b0;
   assign sda_oeb = sda_reg;
   assign sda_out = 0;

   assign scl_oeb = 1;
   assign scl_out = 0;
   
 
   always @(posedge clk) begin
      scl_s <= scl_in;
      scl_ss <= scl_s;
      sda_s <= sda_in;
      sda_ss <= sda_s;
      chip_addr_reg <= chip_addr;
   end

   wire [7:0] word = { sr[6:0], sda_s };

   wire       scl_rising  =  scl_s && !scl_ss;
   wire       scl_falling = !scl_s &&  scl_ss;
   wire       sda_rising  =  sda_s && !sda_ss;
   wire       sda_falling = !sda_s &&  sda_ss;
   
   
   always @(posedge clk or negedge reset_n) begin
      if(!reset_n) begin
	 sda_reg <= 1;
	 transfer_count <= 0;
	 sr <= 8'h01;
	 state <= STATE_WAIT;
	 datao <= 0;
	 reg_addr <= 0;
	 we   <= 0;
	 rw_bit <= 0;
	 sr_send <= 0;
	 nack <= 0;
	 busy <= 0;
      end else begin
	 if(scl_ss && sda_falling) begin // start code
	    transfer_count <= 0;
	    sr <= 8'h01;
	    state <= STATE_SHIFT;
	    sda_reg <= 1;
	    we <= 0;
	    busy <= 1;
	 end else if(scl_ss && sda_rising) begin // stop code
	    state <= STATE_WAIT;
	    sda_reg <= 1;
	    we <= 0;
	 end else begin
	    if(state <= STATE_WAIT) begin
	       we <= 0;
	       transfer_count <= 0;
	       sr <= 8'h01; // preload sr with LSB 1.  When that 1 reaches the MSB of the shift register, we know we are done.
	       sda_reg <= 1;
	       busy <= 0;
	    end else if(state <= STATE_SHIFT) begin
	       sda_reg <= 1;
	       if(scl_rising) begin
		  sr <= word;
		  if(sr[7]) begin
		     // LSB of transfer count is used to track which
		     // byte of the 16 bit word is being collected.
		     // MSB of transfer count is only 0 at the begining
		     // of the packet to signal the address is being
		     // collected.  After the address has been received,
		     // then it is all data after that.
		     transfer_count[0] <= !transfer_count[0];
		     if(transfer_count[0]) begin
			transfer_count[1] <= 1;
		     end

		     if(transfer_count == 0) begin // 1st byte (i2c addr)
			if(word[7:1] != chip_addr_reg) begin 
			   state <= STATE_WAIT; // this transfer is not for us
			end else begin
			   rw_bit <= word[0];
			   sr_send <= datai;
			   state <= STATE_ACK;
			end
		     end else if(transfer_count == 1) begin//2nd byte (reg addr)
			state <= STATE_ACK;
			reg_addr <= word;
		     end else begin
			if(transfer_count[0]) begin // Least significant byte
			   datao[7:0] <= word;
			   state <= STATE_WRITE;
			   we <= 1;
			end else begin              // Most significant byte
			   datao[15:8] <= word;
			   state <= STATE_ACK;
			end			
		     end
		  end
	       end
	    end else if(state == STATE_WRITE) begin
	       // Stay here one clock cycle before moving to ACK to
	       // give we a single clock cycle high.
	       state <= STATE_ACK;
	       reg_addr  <= reg_addr + 1; // advance addr for the case of seq writes
	       we    <= 0;
	       sda_reg <= 1;
	    end else if(state == STATE_ACK) begin
	       we <= 0;
	       // when scl falls, drive sda low to ack the received byte
	       if(!scl_ss) begin
		  sda_reg <= 0;
		  state <= STATE_ACK2;
	       end	       
	    end else if(state == STATE_ACK2) begin
	       sr <= 8'h01;
	       we <= 0;
	       // on the falling edge go back to shifting in data
	       if(scl_falling) begin
		  if(rw_bit) begin // when master is reading, go to STATE_SEND
		     state <= STATE_SEND;
		     sda_reg <= sr_send[15];
		     sr_send <= sr_send << 1;
		  end else begin // when master writing, receive in STATE_SHIFT
		     state <= STATE_SHIFT;
		     sda_reg <= 1;
		  end
	       end
	    end else if(state == STATE_CHECK_ACK) begin
	       sr <= 8'h01;
	       if(scl_rising) begin
		  nack <= sda_s;
	       end 
	       if(scl_falling) begin
		  if(nack) begin
		     state <= STATE_WAIT; // we received a nack, so we are done
		     sda_reg <= 1;
		  end else begin
		     state <= STATE_SEND; // we received an ack, so more data requested
		     sda_reg <= sr_send[15];
		     sr_send <= sr_send << 1;
		  end
	       end
	    end else if(state == STATE_SEND) begin
	       if(scl_falling) begin
		  sr <= word;
		  if(sr[7]) begin
		     transfer_count[0] <= !transfer_count[0];
		     sda_reg <= 1'b1;
		     state <= STATE_CHECK_ACK;

		     if(transfer_count[0]) begin
			reg_addr <= reg_addr + 1; // advance the internal address in between MSB and LSB byte so that the next address data is available after the LSB transfer.
		     end else begin
			sr_send <= datai;
		     end
		     

		  end else begin
		     sda_reg <= sr_send[15];
		     sr_send <= sr_send << 1;
		  end
	       end
	    end
	 end
      end
   end 
endmodule // i2c_slave
