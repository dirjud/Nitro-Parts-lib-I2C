// Author: Lane Brooks
// Date: May 23, 2008
// Description: This implemenents an 8 bit address, 16 bit data i2c slave.
//
//  The 'open_drain_mode' input should be set to 1 to ensure I2C bus
//  compatibility.  Setting it to 0 causes this slave device to drive
//  the bus high rather than letting the pullup.  This breaks I2C
//  compatibility but makes for higher rate communication when a
//  master and slave talk peer-to-peer and are the only devices on the
//  bus.  Running in non-open_drain_mode is experiemental and has
//  known bus contention.

module i2c_slave
  #(parameter NUM_ADDR_BYTES=1,
    parameter NUM_DATA_BYTES=2,
    parameter REG_ADDR_WIDTH=8*NUM_ADDR_BYTES,
    parameter REG_DATA_WIDTH=8*NUM_DATA_BYTES)
   (
    input clk,
    input reset_n,
    input [6:0] chip_addr,
    input [REG_DATA_WIDTH-1:0] datai,
    input open_drain_mode,
    output reg we,
    output reg [REG_DATA_WIDTH-1:0] datao,
    output reg [REG_ADDR_WIDTH-1:0] reg_addr,
    output reg done,
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
   reg       scl_s, sda_s, scl_ss, sda_ss, sda_reg, oeb_reg;
   reg [7:0]  sr;
   reg [1:0]  reg_byte_count;
   reg [1:0]  addr_byte_count;
   reg        rw_bit;
   reg [REG_DATA_WIDTH-1:0] sr_send;
   reg        nack;
   reg [6:0]  chip_addr_reg;
   
   assign scl_oeb = 1;
   assign scl_out = 0;
   assign sda_oeb = oeb_reg;
   assign sda_out = sda_reg;
   
   function set_sda_reg;
      input   out1;
      begin
         set_sda_reg = (open_drain_mode) ? 0 : out1;
      end
   endfunction
   function set_oeb_reg;
      input   oeb;
      input   out1;
      begin
         set_oeb_reg = (open_drain_mode) ? out1 : oeb;
      end
   endfunction
      
   
   always @(posedge clk) begin
      scl_s <= scl_in;
      scl_ss <= scl_s;
      sda_s <= sda_in;
      sda_ss <= sda_s;
      chip_addr_reg <= chip_addr;
   end

   wire [7:0] word = { sr[6:0], sda_s };
   /* verilator lint_off WIDTH */
   wire [REG_DATA_WIDTH-1:0] word_expanded = word;
   /* verilator lint_on WIDTH */
   

   wire       scl_rising  =  scl_s && !scl_ss;
   wire       scl_falling = !scl_s &&  scl_ss;
   wire       sda_rising  =  sda_s && !sda_ss;
   wire       sda_falling = !sda_s &&  sda_ss;
   

   wire [REG_ADDR_WIDTH+8-1:0] shifted_reg_addr = { reg_addr, word };
   
   
`ifdef SYNC_RESET
   always @(posedge clk) begin
`else
   always @(posedge clk or negedge reset_n) begin
`endif      
      if(!reset_n) begin
         sda_reg <= 1;
         oeb_reg <= 1;
         reg_byte_count <= 0;
	 addr_byte_count <= 0;
         sr <= 8'h01;
         state <= STATE_WAIT;
         datao <= 0;
         reg_addr <= 0;
         we   <= 0;
         rw_bit <= 0;
         sr_send <= 0;
         nack <= 0;
         done <= 0;
         busy <= 0;
      end else begin
         if(scl_ss && sda_falling) begin // start code
            reg_byte_count <= 0;
            addr_byte_count <= 0;
            sr <= 8'h01;
            state <= STATE_SHIFT;
            sda_reg <= set_sda_reg(1);
            oeb_reg <= set_oeb_reg(1, 1);
            we <= 0;
            busy <= 1;
            done <= 0;
         end else if(scl_ss && sda_rising) begin // stop code
            state <= STATE_WAIT;
            sda_reg <= set_sda_reg(1);
            oeb_reg <= set_oeb_reg(1, 1);
            we <= 0;
            if(busy) done <= 1;
         end else begin
            if(state == STATE_WAIT) begin
               done <= 0;
               we <= 0;
               reg_byte_count <= 0;
               addr_byte_count <= 0;
               sr <= 8'h01; // preload sr with LSB 1.  When that 1 reaches the MSB of the shift register, we know we are done.
               sda_reg <= set_sda_reg(1);
               oeb_reg <= set_oeb_reg(1, 1);
               busy <= 0;
            end else if(state == STATE_SHIFT) begin
               sda_reg <= set_sda_reg(1);
               oeb_reg <= set_oeb_reg(1, 1);
               if(scl_rising) begin
                  sr <= word;
                  if(sr[7]) begin
		     if(addr_byte_count <= NUM_ADDR_BYTES) begin
			addr_byte_count <= addr_byte_count + 1;

			if(addr_byte_count == 0) begin // 1st byte (i2c addr)
                           if(word[7:1] != chip_addr_reg) begin 
                              state <= STATE_WAIT; // this transfer is not for us
                              done <= 1;
                           end else begin
                              rw_bit <= word[0];
                              sr_send <= datai; 
                              state <= STATE_ACK;
                           end
			end else begin // remaining addr bytes (reg addr)
                           state <= STATE_ACK;
                           reg_addr <= shifted_reg_addr[REG_ADDR_WIDTH-1:0];
			end
                     end else begin 
			// LSB of transfer count is used to track which
			// byte of the 16 bit word is being collected.
			// MSB of transfer count is only 0 at the begining
			// of the packet to signal the address is being
			// collected.  After the address has been received,
			// then it is all data after that.
			datao <= (datao << 8) | word_expanded;
			
			/* verilator lint_off WIDTH */
                        if(reg_byte_count == NUM_DATA_BYTES-1) begin // Least significant byte
			   /* verilator lint_on WIDTH */
                           state <= STATE_WRITE;
                           we <= 1;
			   /* verilator lint_off WIDTH */
			   reg_byte_count <= reg_byte_count + 1 - NUM_DATA_BYTES;
			   /* verilator lint_on WIDTH */
                        end else begin              // Most significant byte
                           state <= STATE_ACK;
			   reg_byte_count <= reg_byte_count + 1;
                        end                     
                     end
                  end
               end
            end else if(state == STATE_WRITE) begin
               // Stay here one clock cycle before moving to ACK to
               // give 'we' a single clock cycle high.
               state <= STATE_ACK;
               reg_addr  <= reg_addr + 1; // advance addr for the case of seq writes
               we    <= 0;
               sda_reg <= set_sda_reg(1);
               oeb_reg <= set_oeb_reg(1, 1);
            end else if(state == STATE_ACK) begin
               we <= 0;
               // when scl falls, drive sda low to ack the received byte
               if(!scl_ss) begin
                  sda_reg <= set_sda_reg(0);
                  oeb_reg <= set_oeb_reg(0, 0);
                  state <= STATE_ACK2;
                  if(rw_bit && (reg_byte_count == 0)) begin
		     sr_send <= datai;
		  end
               end             
            end else if(state == STATE_ACK2) begin
               sr <= 8'h01;
               we <= 0;
               // on the falling edge go back to shifting in data
               if(scl_falling) begin
                  if(rw_bit) begin // when master is reading, go to STATE_SEND
                     state <= STATE_SEND;
                     sda_reg <= set_sda_reg(sr_send[REG_DATA_WIDTH-1]);
                     oeb_reg <= set_oeb_reg(0, sr_send[REG_DATA_WIDTH-1]);
                     sr_send <= sr_send << 1;
                  end else begin // when master writing, receive in STATE_SHIFT
                     state <= STATE_SHIFT;
                     sda_reg <= set_sda_reg(1);
                     oeb_reg <= set_oeb_reg(1, 1);
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
                     done <= 1;
                     sda_reg <= set_sda_reg(1);
                     oeb_reg <= set_oeb_reg(1, 1);
                  end else begin
                     state <= STATE_SEND; // we received an ack, so more data requested
                     sda_reg <= set_sda_reg(sr_send[REG_DATA_WIDTH-1]);
                     oeb_reg <= set_oeb_reg(0, sr_send[REG_DATA_WIDTH-1]);
                     sr_send <= sr_send << 1;
                  end
               end
            end else if(state == STATE_SEND) begin
               if(scl_falling) begin
                  sr <= word;
                  if(sr[7]) begin
                     reg_byte_count <= reg_byte_count + 1;
                     sda_reg <= set_sda_reg(1);
                     oeb_reg <= set_oeb_reg(1, 1);
                     state <= STATE_CHECK_ACK;

		     /* verilator lint_off WIDTH */
                     if(reg_byte_count == NUM_DATA_BYTES-1) begin
			/* verilator lint_on WIDTH */
                        reg_addr <= reg_addr + 1; // advance the internal address so that the next address data is available after this transfer.
			reg_byte_count <= 0;
                     end
                     

                  end else begin
                     sda_reg <= set_sda_reg(sr_send[REG_DATA_WIDTH-1]);
                     oeb_reg <= set_oeb_reg(0, sr_send[REG_DATA_WIDTH-1]);
                     sr_send <= sr_send << 1;
                  end
               end
            end
         end
      end
   end 
endmodule // i2c_slave
