// Author: Lane Brooks
// Date: May 23, 2008
// Description: A simple I2C master that read/writes to the micron 5mp part.
//
// From the Micron Datasheet:
// A typical READ or WRITE sequence begins by the master sending a
// start bit. After the start bit, the master sends the slave device's
// 8-bit address. The last bit of the address determines if the
// request is a READ or a WRITE, where a 0 indicates a WRITE and a
// 1 indicates a READ. The slave device acknowledges its address by
// sending an acknowledge bit back to the master.  
//
// If the request is a WRITE, the master then transfers the 8-bit
// register address to which a WRITE should take place. The slave
// sends an acknowledge bit to indicate that the register address has
// been received. The master then transfers the data 8 bits at a time,
// with the slave sending an acknowledge bit after each 8 bits. The
// MT9P031 uses 16-bit data for its internal registers, thus requiring
// two 8-bit transfers to write to one register.  After 16 bits are
// transferred, the register address is automatically incremented, so
// that the next 16 bits are written to the next register address. The
// master stops writing by sending a start or stop bit.
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
// This module returns a status register which is a 5 bit number
// indicating the ack status of each byte written to the micron part.
// Under a successful write where all 4 bytes are ACK'd correctly, the
// status register will read 5'b10000 (0x10).  The MSB is always one
// and the four LSBs correspond to each ACK state.

module i2c_master
   (
    input clk,
    input reset_n,
    input [11:0] clk_divider, // sets the 1/4 scl period

    input [6:0] chip_addr,
    input [7:0] reg_addr,
    input [15:0] datai,
    input we,
    input re,
    output reg [4:0] status,
    output reg done,
    output reg busy,
    
    output reg [15:0] datao,
    input sda_in,
    output sda_out,
    output sda_oeb,
    input scl_in,
    output scl_out,
    output scl_oeb
    );

   parameter STATE_WAIT = 0, 
	     STATE_START_BIT_FOR_WRITE = 1, 
	     STATE_SHIFT_OUT = 2,
	     STATE_RCV_ACK=3,
	     STATE_STOP_BIT=4,
	     STATE_START_BIT_FOR_READ=5,
	     STATE_SHIFT_IN=6,
	     STATE_SEND_ACK=7,
	     STATE_SEND_NACK=8;
   
   reg sda_reg;
   reg [31:0] sr;
   reg [1:0]  scl_count;
   reg [3:0]  state;
   reg [11:0] clk_count;
   reg [5:0]  sr_count;
   reg 	      sda_s;
   reg 	      isWrite, readPass;

   wire [2:0] byte_count = sr_count[5:3];
//   assign scl = (scl_count[1]) ? 1'bz : 0;
   assign scl_oeb = scl_count[1];
   assign scl_out = 0;

//   assign sda = (sda_reg) ? 1'bz : 0;
   assign sda_oeb = sda_reg;
   assign sda_out = 0;
   
   
   always @(posedge clk) begin
      sda_s <= sda_in;
   end
   always @(posedge clk or negedge reset_n) begin
      if(!reset_n) begin
	 sda_reg <= 1;
	 scl_count <= 2'b10;
	 clk_count <= 0;
	 state <= STATE_WAIT;
	 sr_count <= 0;
	 sr <= -1;
	 status <= 5'b10000;
	 isWrite <= 1;
	 readPass <= 0;
	 datao <= 0;
	 done <= 0;
	 busy <= 0;

      end else begin
	 if(state == STATE_WAIT) begin
	    done <= 0;
	    sda_reg <= 1;
	    clk_count <= 0;
	    scl_count <= 2'b10;
	    sr_count  <= 0;
	    sr <= { chip_addr, 1'b0, reg_addr, datai };  // latch data into shift register
	    if(we) begin
	       state   <= STATE_START_BIT_FOR_WRITE;
	       status  <= 5'b00001;  // reset status
	       isWrite <= 1;
	       busy    <= 1;
	    end else if(re) begin 
	       state   <= STATE_START_BIT_FOR_WRITE; //1st we write the addr
	       status  <= 5'b00001;  // reset status
	       isWrite <= 0;
	       readPass<= 0;
	       busy    <= 1;
	    end else begin
	       busy    <= 0;
	    end
	    	    
	 end else begin
	    if(clk_count == clk_divider) begin // advance state on slow i2c clk
	       clk_count <= 0;
	       scl_count <= scl_count + 1;

	       if(state == STATE_START_BIT_FOR_WRITE) begin
		  sda_reg <= 0;
		  state <= STATE_SHIFT_OUT;
		  
	       end else if(state == STATE_START_BIT_FOR_READ) begin
		  if(scl_count == 2'b10) begin
		     sda_reg <= 1'b0;
		     state <= STATE_SHIFT_OUT;
		     sr <= { chip_addr, 1'b1, reg_addr, datai };
		     sr_count <= 0;
		     readPass <= 1;
		  end

	       end else if(state == STATE_SHIFT_OUT) begin		  
		  if(scl_count == 2'b00) begin
		     if((sr_count[2:0]) == 0 && (|sr_count)) begin
			state <= STATE_RCV_ACK;
			sda_reg <= 1'b1;
		     end else begin
			sr_count <= sr_count + 1;
			sda_reg  <= sr[31];
			sr <= { sr[30:0], 1'b1 };
		     end
		  end
		  
	       end else if(state == STATE_RCV_ACK) begin
		  if(scl_count == 2'b00) begin
		     if(isWrite && (byte_count == 4)) begin // done writing all 4 bytes
			state <= STATE_STOP_BIT;
			sda_reg <= 1'b0; // send stop bit
		     end else if(!isWrite && !readPass && (byte_count == 2)) begin
			state <= STATE_START_BIT_FOR_READ;
		     end else if(!isWrite && readPass) begin
			state <= STATE_SHIFT_IN;
		     end else begin
			state <= STATE_SHIFT_OUT;
			sda_reg <= sr[31];
			sr <= { sr[30:0], 1'b1 };
			sr_count <= sr_count + 1;
		     end
		  end else if(scl_count == 2'b01) begin
		     status <= { status[3:0], sda_s }; // sample the ack bit
		  end

	       end else if(state == STATE_STOP_BIT) begin
		  if(scl_count == 2'b10) begin
		     sda_reg <= 1'b1;
		     state <= STATE_WAIT;
		     done  <= 1;
		  end

	       end else if(state == STATE_SHIFT_IN) begin
		  if(scl_count == 2'b01) begin
		     datao <= { datao[14:0], sda_s };
		     sr_count <= sr_count + 1;
		     sda_reg <= 1'b1;
		  end else if(scl_count == 2'b00) begin
		     if(sr_count == 24) begin
			state <= STATE_SEND_NACK; // terminate read after LSByte
			sda_reg <= 1;
		     end else if(sr_count == 16) begin
			state <= STATE_SEND_ACK; // send ACK of MSByte
			sda_reg <= 0;
		     end
		  end
	       
	       end else if(state == STATE_SEND_ACK) begin
		  if(scl_count == 2'b01) begin
		     status<= { status[3:0], sda_s }; // sample the ack bit
		  end else if(scl_count == 2'b00) begin
		     sda_reg <= 1;
		     state <= STATE_SHIFT_IN;
		  end

	       end else if(state == STATE_SEND_NACK) begin
		  if(scl_count == 2'b00) begin
		     sda_reg <= 0;
		     state <= STATE_STOP_BIT;
		  end else begin
		     sda_reg <= 1;
		  end
	       end

	    end else begin
	       clk_count <= clk_count + 1;
	    end
	 end 
      end
   end
   
endmodule