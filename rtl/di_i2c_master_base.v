// Author: Lane Brooks
// Date: Dec. 2, 2012
// Description: This is the glue logic to hook an i2c_master directly up
//  to DI.

// Dennis: move master to master_base
//         add oeb outputs to allow higher level module to
//         control bZ status on lines.

module di_i2c_master_base
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
   output reg 			     di_read_rdy,
   output reg [NUM_DATA_BYTES*8-1:0] di_reg_datao,
   output reg 			     di_write_rdy,
   output reg [15:0] 		     di_transfer_status,
   output reg 			     di_I2C_en,

   // physcial i2c pins
   input 			     sda_in,
   output          sda_oeb,
   output          sda_out,

   input 			     scl_in,
   output          scl_oeb,
   output          scl_out
   );

   wire i2c_done, i2c_busy;
   reg [15:0] i2c_transfer_status;
   wire [NUM_ADDR_BYTES+NUM_DATA_BYTES:0] i2c_status;
   wire [NUM_DATA_BYTES*8-1:0] i2c_datao;
   reg        i2c_rdy;

   wire term_active = di_term_addr == i2c_term_addr;
   wire i2c_re        = di_read_req  && term_active;
   wire i2c_we        = di_write     && term_active;
   wire i2c_write_mode= di_write_mode&& term_active;
   wire i2c_read_mode = di_read_mode && term_active && (NUM_ADDR_BYTES == 0); // only do continuous reads if there is no address bytes

   always @(posedge ifclk or negedge resetb) begin
      if(!resetb) begin
         i2c_rdy      <= 0;
      end else begin
         if(di_read_req) begin
            i2c_rdy <= 0;
         end else if(i2c_done) begin
            i2c_rdy <= 1;
         end
      end
   end

   always @(*) begin
      if(term_active) begin
         di_reg_datao =  i2c_datao;
         di_read_rdy  =  i2c_rdy & !di_read_req;
         di_write_rdy = ~i2c_busy && !di_write;
         di_transfer_status = i2c_transfer_status;
	 di_I2C_en    = 1;
      end else begin
         di_reg_datao =  0;
         di_read_rdy  =  1;
         di_write_rdy =  1;
         di_transfer_status = 16'hBBBB;
	 di_I2C_en    = 0;
      end
   end

   ///////////////////////////////////////////////////////////////////////////
   always @(posedge ifclk or negedge resetb) begin
      if(!resetb) begin
         i2c_transfer_status <= 0;
      end else begin
         if(!di_read_mode && !di_write_mode) begin // clear status between read/write commands
            i2c_transfer_status <= 0;
         end else begin
            if(|i2c_status) begin
               i2c_transfer_status <= { {16-NUM_DATA_BYTES-NUM_ADDR_BYTES-1{1'b0}}, i2c_status };
            end
         end
      end
   end

   localparam REG_ADDR_WIDTH = NUM_ADDR_BYTES==0 ? 1 : 8*NUM_ADDR_BYTES;

   i2c_master
     #(.NUM_ADDR_BYTES(NUM_ADDR_BYTES),
       .NUM_DATA_BYTES(NUM_DATA_BYTES),
       .REG_ADDR_WIDTH(REG_ADDR_WIDTH))
     i2c_master
     (
      .status           (i2c_status),
      .datao            (i2c_datao),
      .sda_out          (sda_out),
      .sda_oeb          (sda_oeb),
      .scl_out          (scl_out),
      .scl_oeb          (scl_oeb),
      .clk              (ifclk),
      .reset_n          (resetb),
      .clk_divider      (i2c_clk_divider),
      .chip_addr        (i2c_chip_addr),
      .reg_addr         (di_reg_addr[REG_ADDR_WIDTH-1:0]),
      .datai            (di_reg_datai),
      .open_drain_mode  (1'b1),
      .done             (i2c_done),
      .busy             (i2c_busy),
      .we               (i2c_we),
      .write_mode       (i2c_write_mode),
      .re               (i2c_re),
      .read_mode        (i2c_read_mode),
      .sda_in           (sda_in),
      .scl_in           (scl_in));

endmodule
