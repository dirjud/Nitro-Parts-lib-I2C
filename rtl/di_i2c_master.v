// Author: Lane Brooks
// Date: Dec. 2, 2012
// Description: This is the glue logic to hook an i2c_master directly up
//  to DI.

module di_i2c_master
  #(parameter NUM_ADDR_BYTES =2,
    parameter NUM_DATA_BYTES =1)
  (input ifclk,
   input 			     resetb,
   input [6:0] 			     i2c_chip_addr, // physical address of i2c device
   input [15:0] 		     i2c_term_addr, // terminal address, often same as i2c_chip_addr
   input [11:0] 		     i2c_clk_divider, // controls how fast to run the i2c bus

   // di control signals
   input [15:0] 		     di_term_addr,
   input [31:0] 		     di_reg_addr,
   input 			     di_read_mode,
   input 			     di_read_req,
   input 			     di_write_mode,
   input 			     di_write,
   input [NUM_DATA_BYTES*8-1:0]	     di_reg_datai,
   output 			     di_read_rdy,
   output [NUM_DATA_BYTES*8-1:0] di_reg_datao,
   output  			     di_write_rdy,
   output [15:0] 		     di_transfer_status,
   output  			     di_I2C_en,

   // physcial i2c pins
   inout 			     sda,
   inout 			     scl
   );

   wire sda_oeb, scl_oeb, sda_out, scl_out;
   wire sda_in = sda;
   assign sda = (sda_oeb == 0) ? sda_out : 1'bz;
   wire scl_in = scl;
   assign scl = (scl_oeb == 0) ? scl_out : 1'bz;

   di_i2c_master_base
     #(
       .NUM_ADDR_BYTES(NUM_ADDR_BYTES),
       .NUM_DATA_BYTES(NUM_DATA_BYTES)
      )
   di_i2c_master_base (
   .ifclk (ifclk),
   .resetb (resetb),
   .i2c_chip_addr(i2c_chip_addr),
   .i2c_term_addr(i2c_term_addr),
   .i2c_clk_divider(i2c_clk_divider),
   // di control signals
   .di_term_addr (di_term_addr),
   .di_reg_addr (di_reg_addr),
   .di_read_mode (di_read_mode),
   .di_read_req (di_read_req),
   .di_write_mode (di_write_mode),
   .di_write (di_write),
   .di_reg_datai (di_reg_datai),
   .di_read_rdy (di_read_rdy),
   .di_reg_datao (di_reg_datao),
   .di_write_rdy (di_write_rdy),
   .di_transfer_status (di_transfer_status),
   .di_I2C_en (di_I2C_en),

   .sda_in(sda_in),
   .sda_out(sda_out),
   .sda_oeb(sda_oeb),

   .scl_in(scl_in),
   .scl_out(scl_out),
   .scl_oeb(scl_oeb)
   );

endmodule
