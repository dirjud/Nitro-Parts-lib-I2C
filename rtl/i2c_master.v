// Author: Lane Brooks
// Date: May 23, 2008
// Description: A simple I2C master
//
// A typical READ or WRITE sequence begins by the master sending a
// start bit. After the start bit, the master sends the slave device's
// 7-bit address and a bit to specify if the request is a READ or a
// WRITE, where a 0 indicates a WRITE and a 1 indicates a READ. The
// slave device acknowledges its address by sending an acknowledge bit
// back to the master.
//
// If the request is a WRITE, the master then transfers the register
// address to which a WRITE should take place. The slave sends an
// acknowledge bit to indicate that the register address has been
// received. The master then transfers the data bytes, with the slave
// sending an acknowledge bit after each 8 bits. The master stops
// writing by sending a start or stop bit.
//
// If you want to continue to write data bytes beyond the initial
// address, hold the 'write_mode' input high and the next 'we' signal
// will continue without sending a start or bit and will continue
// to write bytes until it drops. Same is true for 'read_mode'.
//
// A typical READ sequence is executed as follows. First the master
// sends the write-mode slave address and 8-bit register address, just
// as in the WRITE request. The master then sends a start bit and the
// read-mode slave address. The master then clocks out the register
// data 8 bits at a time. The master sends an acknowledge bit after
// each 8-bit transfer. The register address is
// automatically-incremented after every 16 bits is trans- ferred. The
// data transfer is stopped when the master sends a no-acknowledge
// bit.
//
// If the i2c is command based and not a RAM-style address/data
// protocol, then set the NUM_ADDR_BYTES to 0. This will let you you
// do raw reads without first doing the write of an address.  When
// setting NUM_ADDR_BYTES to 0, you will also need to override the
// REG_ADDR_WIDTH parameter and set it to something like 1 and pass in
// a dummy bit for the 'reg_addr' port.
//
// This module returns a status register which is a 4 bit number
// indicating the ack status of each byte in the transaction Under a
// successful write where all 4 bytes are ACK'd correctly, the status
// register will read 4'b0000 (0x0).  Each bit corresponds to each ACK
// state.  Any bit that is not zero is a transfer that was not ack'd.
//
//  The 'open_drain_mode' input should be set to 1 to ensure I2C bus
//  compatibility.  Setting it to 0 causes this master device to drive
//  the bus high rather than lettering the pullup.  This breaks I2C
//  compatibility but makes for higher rate communication when a
//  master and slave talk peer-to-peer and are the only devices on the
//  bus.  Running in non-open_drain_mode is experiemental and has
//  known bus contention.


module i2c_master
  #(parameter NUM_ADDR_BYTES=1,
    parameter NUM_DATA_BYTES=2,
    parameter REG_ADDR_WIDTH=8*NUM_ADDR_BYTES)
   (
    input clk,
    input reset_n,
    input [11:0] clk_divider, // sets the 1/4 scl period

    input [6:0] chip_addr,
    /* verilator lint_off LITENDIAN */
    input [REG_ADDR_WIDTH-1:0] reg_addr,
    /* verilator lint_on LITENDIAN */
    input [8*NUM_DATA_BYTES-1:0] datai,
    input open_drain_mode,
    input we,
    input write_mode,
    input re,
    input read_mode,
    output reg [NUM_ADDR_BYTES+NUM_DATA_BYTES:0] status,
    output reg done,
    output reg busy,
    
    output reg [8*NUM_DATA_BYTES-1:0] datao,
    input sda_in,
    output sda_out,
    output sda_oeb,
    input scl_in,
    output scl_out,
    output scl_oeb
    );

   localparam STATE_WAIT                 = 0, 
              STATE_START_BIT_FOR_WRITE  = 1, 
              STATE_SHIFT_OUT            = 2,
              STATE_RCV_ACK              = 3,
              STATE_STOP_BIT             = 4,
              STATE_START_BIT_FOR_READ   = 5,
              STATE_SHIFT_IN             = 6,
              STATE_SEND_ACK             = 7,
              STATE_SEND_NACK            = 8,
              STATE_STOP_BIT2            = 9;
   


   localparam SR_WIDTH = 8 + 8*NUM_ADDR_BYTES + 8*NUM_DATA_BYTES;
   localparam STATUS_WIDTH = NUM_ADDR_BYTES+NUM_DATA_BYTES+1;
   reg [SR_WIDTH-1:0] sr;
   reg [1:0]  scl_count;
   reg [3:0]  state;
   reg [11:0] clk_count;
   reg [5:0]  sr_count;
   reg     sda_reg, oeb_reg, sda_s, scl_s;
   reg        isWrite, readPass;
   reg 	      continuing;
   

   
   wire [2:0] byte_count = sr_count[5:3];
//   assign scl = (scl_count[1]) ? 1'bz : 0;
   assign sda_out = sda_reg;
   assign sda_oeb = oeb_reg;
   assign scl_out = set_out_reg(scl_count[1]);
   assign scl_oeb = set_oeb_reg(0, scl_count[1]);

   function set_out_reg;
      input   out1;
      begin
         set_out_reg = (open_drain_mode) ? 0 : out1;
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
      sda_s <= sda_in;
      scl_s <= scl_in;
   end
   reg read_done;
   
   always @(posedge clk or negedge reset_n) begin
      if(!reset_n) begin
         sda_reg <= 1;
         oeb_reg <= 1;
         scl_count <= 2'b10;
         clk_count <= 0;
         state <= STATE_WAIT;
         sr_count <= 0;
         sr <= -1;
         status <= 0;
         isWrite <= 1;
         readPass <= 0;
         datao <= 0;
         done <= 0;
         busy <= 0;
	 continuing <= 0;
	 read_done <= 0;
         
      end else begin
         if(state == STATE_WAIT) begin
            done <= 0;

	    if (!write_mode && !read_mode) begin
	       continuing <= 0;
	       if(continuing) begin // send stop bit
                  sda_reg <= set_out_reg(0);
                  oeb_reg <= set_oeb_reg(0, 0);
	       end else begin
		  sda_reg <= set_out_reg(1);
		  oeb_reg <= set_oeb_reg(1, 1);
		  clk_count <= 0;
	       end
	    end
	    
	    if(continuing) begin
               // latch data into shift register
               if(read_mode) begin
                 scl_count <= 2'b01;
               end else begin
                 scl_count <= 2'b00;
               end
               sr <= { datai, { SR_WIDTH-8*NUM_DATA_BYTES { 1'b0 }}};
	    end else begin
	       scl_count <= 2'b10;
               /* verilator lint_off WIDTH */
	       if(NUM_ADDR_BYTES == 0) begin
		  sr <= { chip_addr, 1'b0, datai };  // latch data into shift register
               end else begin
		  sr <= { chip_addr, 1'b0, reg_addr, datai };  // latch data into shift register
               end
	       /* verilator lint_on WIDTH */
	    end
	       
            sr_count  <= 0;

	    if(we) begin
	       if (continuing) begin
		  state   <= STATE_SHIFT_OUT;
	       end else begin
		  state   <= STATE_START_BIT_FOR_WRITE;
	       end
               status  <= 0;  // reset status
               isWrite <= 1;
               busy    <= 1;
            end else if(re) begin
               if(continuing) begin
                  state   <= STATE_SHIFT_IN; //don't write addr but continuing reading
               end else if(NUM_ADDR_BYTES == 0) begin
                  state   <= STATE_START_BIT_FOR_READ; //don't write addr if no address bytes
               end else begin
                  state   <= STATE_START_BIT_FOR_WRITE; //1st we write the addr
               end
               status  <= 0;  // reset status
               isWrite <= 0;
               readPass<= 0;
               busy    <= 1;
            end else begin
	       if (!write_mode && !read_mode) begin
	          continuing <= 0;
	          if(continuing) begin // send stop bit
                     state <= STATE_STOP_BIT;
                     busy <= 1;
                  end else begin
                     busy <= 0;
                  end
               end else begin
                  busy <= 0;
               end
            end
                    
         end else begin
            if(clk_count == clk_divider) begin // advance state on slow i2c clk
               clk_count <= 0;
               if(state == STATE_START_BIT_FOR_WRITE ||
                  state == STATE_STOP_BIT2) begin
                  // in these states, we don't want the clock to go low
                  scl_count[1] <= 1;
                  scl_count[0] <= ~scl_count[0];
               end else begin
                  scl_count <= scl_count + 1;
               end
               
               if(state == STATE_START_BIT_FOR_WRITE) begin
                  if(sda_s && scl_s && scl_count == 2) begin
                     sda_reg <= set_out_reg(0);
                     oeb_reg <= set_oeb_reg(0, 0);
                     state <= STATE_SHIFT_OUT;
                  end
               end else if(state == STATE_START_BIT_FOR_READ) begin
                  if(scl_count == 2'b10) begin
                     sda_reg <= set_out_reg(0);
                     oeb_reg <= set_oeb_reg(0, 0);
                     state <= STATE_SHIFT_OUT;
                     sr <= { chip_addr, 1'b1, {8*(NUM_ADDR_BYTES+NUM_DATA_BYTES){1'b0}}};
                     sr_count <= 0;
                     readPass <= 1;
                  end

               end else if(state == STATE_SHIFT_OUT) begin                
                    if(scl_count == 2'b00) begin
                     if((sr_count[2:0]) == 0 && (|sr_count)) begin
                        state <= STATE_RCV_ACK;
                        sda_reg <= set_out_reg(1);
                        oeb_reg <= set_oeb_reg(1, 1);
                     end else begin
                        sr_count <= sr_count + 1;
                        sda_reg  <= set_out_reg(sr[SR_WIDTH-1]);
                        oeb_reg  <= set_oeb_reg(0, sr[SR_WIDTH-1]);
                        sr <= { sr[SR_WIDTH-2:0], 1'b1 };
                     end
                  end
                  
               end else if(state == STATE_RCV_ACK) begin
                  if(scl_count == 2'b00) begin
                     if(isWrite && ((byte_count == NUM_DATA_BYTES + NUM_ADDR_BYTES + 1 && continuing==0) || (byte_count == NUM_DATA_BYTES && continuing == 1))) begin // done writing all bytes
			if(write_mode) begin
			   continuing <= 1;
			   state <= STATE_WAIT;
			   done <= 1;
			end else begin
                           state <= STATE_STOP_BIT;
                           sda_reg <= set_out_reg(0); // send stop bit
                           oeb_reg <= set_oeb_reg(0, 0);
			end
                     end else if(!isWrite && !readPass && (byte_count == NUM_ADDR_BYTES+1)) begin
                        state <= STATE_START_BIT_FOR_READ;
                     end else if(!isWrite && readPass) begin
                        state <= STATE_SHIFT_IN;
                     end else begin
                        state <= STATE_SHIFT_OUT;
                        sda_reg <= set_out_reg(   sr[SR_WIDTH-1]);
                        oeb_reg <= set_oeb_reg(0, sr[SR_WIDTH-1]);
                        sr <= { sr[SR_WIDTH-2:0], 1'b1 };
                        sr_count <= sr_count + 1;
                     end
                  end else if(scl_count == 2'b10) begin
		     if(scl_s) begin
			status <= { status[STATUS_WIDTH-2:0], sda_s }; // sample the ack bit
		     end
                  end

               end else if(state == STATE_STOP_BIT) begin
                  if(scl_count == 2'b10) begin
                     sda_reg <= set_out_reg(1);
                     oeb_reg <= set_oeb_reg(1, 1);
                  end else if(scl_count == 2'b00) begin
                     sda_reg <= set_out_reg(0); // resend stop bit (usually won't get here unless we have to keep clocking to flush the data the slave is sending)
                     oeb_reg <= set_oeb_reg(0, 0);
                  end

               end else if(state == STATE_SHIFT_IN) begin
                  if(scl_count == 2'b01) begin
                     datao <= { datao[8*NUM_DATA_BYTES-2:0], sda_s };
                     sr_count <= sr_count + 1;
                     sda_reg <= set_out_reg(1);
                     oeb_reg <= set_oeb_reg(1, 1);
                  end else if(scl_count == 2'b00) begin
                     if((sr_count == 8*(NUM_DATA_BYTES+1)) || (continuing && (sr_count == 8*NUM_DATA_BYTES))) begin
                        read_done <= 1;
                        if(read_mode) begin
                           state <= STATE_SEND_ACK; // send ACK of MSByte(s)
                           sda_reg <= set_out_reg(0);
                           oeb_reg <= set_oeb_reg(0, 0);
                           continuing <= 1;
                           
                        end else begin
                           state <= STATE_SEND_NACK; // terminate read after LSByte
                           sda_reg <= set_out_reg(1);
                           oeb_reg <= set_oeb_reg(1, 1);
                        end
                     end else if(sr_count[2:0] == 0) begin
                        read_done <= 0;
                        state <= STATE_SEND_ACK; // send ACK of MSByte(s)
                        sda_reg <= set_out_reg(0);
                        oeb_reg <= set_oeb_reg(0, 0);
                     end
                  end
               
               end else if(state == STATE_SEND_ACK) begin
                  if(scl_count == 2'b01) begin
                     status<= { status[STATUS_WIDTH-2:0], sda_s };// sample the ack bit
                  end else if(scl_count == 2'b00) begin
                     sda_reg <= set_out_reg(1);
                     oeb_reg <= set_oeb_reg(1, 1);
                     if(read_done) begin
                        done <= 1;
                        state <= STATE_WAIT;
                     end else begin
                        state <= STATE_SHIFT_IN;
                     end
                  end

               end else if(state == STATE_SEND_NACK) begin
                  if(scl_count == 2'b00) begin
                     sda_reg <= set_out_reg(0);
                     oeb_reg <= set_oeb_reg(0, 0);
                     state <= STATE_STOP_BIT;
                  end else begin
                     sda_reg <= set_out_reg(1);
                     oeb_reg <= set_oeb_reg(1, 1);
                  end
                  
               end

            end else begin
	       if(scl_count[1] == 1 && scl_s == 0 && clk_count != 0) begin // scl stretch if someone is holding the scl line down
		  
	       end else begin
		  clk_count <= clk_count + 1;
	       end
               if(scl_count == 2'b11 && clk_count == clk_divider-1) begin
                  if(state == STATE_STOP_BIT2 && sda_s) begin
                     state <= STATE_WAIT;
                     if(busy) begin
                        done  <= 1;
                     end
                  end else if(state == STATE_STOP_BIT) begin
                     // wait for sda to high to ensure stop bit worked
                     if(sda_s) begin
                        state <= STATE_STOP_BIT2;
                        scl_count <= 2'b10;
                     end
                  end
               end
            end
         end 
      end
   end
   
endmodule
