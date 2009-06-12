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
    input [REG_ADDR_WIDTH-1:0] reg_addr,
    input [8*NUM_DATA_BYTES-1:0] datai,
    input open_drain_mode,
    input we,
    input re,
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

   parameter STATE_WAIT                 = 0, 
             STATE_START_BIT_FOR_WRITE  = 1, 
             STATE_SHIFT_OUT            = 2,
             STATE_RCV_ACK              =3,
             STATE_STOP_BIT             =4,
             STATE_START_BIT_FOR_READ   =5,
             STATE_SHIFT_IN             =6,
             STATE_SEND_ACK             =7,
             STATE_SEND_NACK            =8;


   parameter SR_WIDTH = 8 + 8*NUM_ADDR_BYTES + 8*NUM_DATA_BYTES;
   parameter STATUS_WIDTH = NUM_ADDR_BYTES+NUM_DATA_BYTES+1;
   reg [SR_WIDTH-1:0] sr;
   reg [1:0]  scl_count;
   reg [3:0]  state;
   reg [11:0] clk_count;
   reg [5:0]  sr_count;
   reg     sda_reg, oeb_reg, sda_s;
   reg        isWrite, readPass;


   
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
   end
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

      end else begin
         if(state == STATE_WAIT) begin
            done <= 0;
            sda_reg <= set_out_reg(1);
            oeb_reg <= set_oeb_reg(1, 1);
            clk_count <= 0;
            scl_count <= 2'b10;
            sr_count  <= 0;
            /* verilator lint_off WIDTH */
            if(NUM_ADDR_BYTES == 0) begin
               sr <= { chip_addr, 1'b0, datai };  // latch data into shift register
            end else begin
               sr <= { chip_addr, 1'b0, reg_addr, datai };  // latch data into shift register
            end
            /* verilator lint_on WIDTH */

            if(we) begin
               state   <= STATE_START_BIT_FOR_WRITE;
               status  <= 0;  // reset status
               isWrite <= 1;
               busy    <= 1;
            end else if(re) begin
               if(NUM_ADDR_BYTES == 0) begin
                  state   <= STATE_START_BIT_FOR_READ; //1st we write the addr
               end else begin
                  state   <= STATE_START_BIT_FOR_WRITE; //1st we write the addr
               end
               status  <= 0;  // reset status
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
                  sda_reg <= set_out_reg(0);
                  oeb_reg <= set_oeb_reg(0, 0);
                  state <= STATE_SHIFT_OUT;
                  
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
                     if(isWrite && (byte_count == NUM_DATA_BYTES + NUM_ADDR_BYTES + 1)) begin // done writing all bytes
                        state <= STATE_STOP_BIT;
                        sda_reg <= set_out_reg(0); // send stop bit
                        oeb_reg <= set_oeb_reg(0, 0);
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
                  end else if(scl_count == 2'b01) begin
                     status <= { status[STATUS_WIDTH-2:0], sda_s }; // sample the ack bit
                  end

               end else if(state == STATE_STOP_BIT) begin
                  if(scl_count == 2'b10) begin
                     sda_reg <= set_out_reg(1);
                     oeb_reg <= set_oeb_reg(1, 1);
                     state <= STATE_WAIT;
                     done  <= 1;
                  end

               end else if(state == STATE_SHIFT_IN) begin
                  if(scl_count == 2'b01) begin
                     datao <= { datao[8*NUM_DATA_BYTES-2:0], sda_s };
                     sr_count <= sr_count + 1;
                     sda_reg <= set_out_reg(1);
                     oeb_reg <= set_oeb_reg(1, 1);
                  end else if(scl_count == 2'b00) begin
                     if(sr_count == 8*(NUM_DATA_BYTES+1)) begin
                        state <= STATE_SEND_NACK; // terminate read after LSByte
                        sda_reg <= set_out_reg(1);
                        oeb_reg <= set_oeb_reg(1, 1);
                     end else if(sr_count[2:0] == 0) begin
                        state <= STATE_SEND_ACK; // send ACK of MSByte
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
                     state <= STATE_SHIFT_IN;
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
               clk_count <= clk_count + 1;
            end
         end 
      end
   end
   
endmodule