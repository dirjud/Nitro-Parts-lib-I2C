module tb();
   wire SDA, SCL;

   reg clk, reset_n;
   wire [11:0] clk_divider = 206;
   
   reg [6:0]   master_chip_addr;
   reg [7:0]   master_reg_addr;
   reg [15:0]  master_datai;
   reg 	       master_we;
   reg 	       master_re;
   wire [3:0] master_status;
   wire       master_done;
   wire       master_busy;
   wire [15:0] master_datao;
   wire master_sda_out;
   wire master_sda_oeb;
   wire master_scl_out;
   wire master_scl_oeb;
   
   reg [6:0] slave_chip_addr;
   reg [15:0] slave_datai;
   wire	      slave_we;
   wire [15:0] slave_datao;
   wire [7:0]  slave_reg_addr;
   wire        slave_sda_in;
   wire        slave_scl_in;
   wire        slave_sda_out;
   wire        slave_sda_oeb;
   wire        slave_scl_out;
   wire        slave_scl_oeb;
   wire        slave_busy;
   wire        slave_done;
   reg 	       write_mode;
   reg 	       open_drain_mode;
   
   i2c_master
     #(.NUM_ADDR_BYTES(1),
       .NUM_DATA_BYTES(2))
     i2c_master
     (.clk		(clk),
      .reset_n		(reset_n),
      .clk_divider	(clk_divider),
      .chip_addr	(master_chip_addr),
      .reg_addr		(master_reg_addr),
      .datai		(master_datai),
      .open_drain_mode  (open_drain_mode),
      .we		(master_we),
      .write_mode       (write_mode),
      .re		(master_re),
      .status		(master_status),
      .done		(master_done),
      .busy		(master_busy),
      .datao		(master_datao),

      .sda_in		(SDA),
      .scl_in		(SCL),
      .sda_out		(master_sda_out),
      .sda_oeb		(master_sda_oeb),
      .scl_out		(master_scl_out),
      .scl_oeb		(master_scl_oeb)
      );
   
   i2c_slave 
     #(.NUM_ADDR_BYTES(1),
       .NUM_DATA_BYTES(2))
     i2c_slave
     (.clk		(clk),
      .reset_n		(reset_n),
      .chip_addr	(slave_chip_addr),
      .reg_addr		(slave_reg_addr),
      .datai		(slave_datai),
      .open_drain_mode  (open_drain_mode),
      .we		(slave_we),
      .datao		(slave_datao),
      .done             (slave_done),
      .busy             (slave_busy),
      
      .sda_in		(SDA),
      .scl_in		(SCL),
      .sda_out		(slave_sda_out),
      .sda_oeb		(slave_sda_oeb),
      .scl_out		(slave_scl_out),
      .scl_oeb		(slave_scl_oeb)
      );

   assign SDA = master_sda_oeb ? 1'bz : master_sda_out;
   assign SDA = slave_sda_oeb  ? 1'bz : slave_sda_out ;
   assign SCL = master_scl_oeb ? 1'bz : master_scl_out;
   assign SCL = slave_scl_oeb  ? 1'bz : slave_scl_out ;

   pullup(SDA);
   pullup(SCL);
   
   reg [15:0]  slave_data[0:255];
   
   parameter CHIP_ADDR = 7'h70;
   
   
   initial begin
      clk =  0;
      reset_n = 0;
      open_drain_mode = 1;
      slave_chip_addr = CHIP_ADDR;
      master_chip_addr = 0;
      master_reg_addr = 0;
      master_datai = 0;
      master_we = 0;
      master_re = 0;
      write_mode = 0;
      
      
      $dumpfile("i2c_test.vcd");
      $dumpvars(0, tb);
      
	
      #40 reset_n = 1;

      $display("Testing open drain mode=1");
      test_rw(CHIP_ADDR, 8'h55, 16'hAAC3);

      $display("Testing Multi-word write");
      write_mode = 1;
      #6000 write_i2c(CHIP_ADDR, 8'h54, 16'h5555);
      #6000 write_i2c(CHIP_ADDR, 8'h54, 16'hA050);
      write_mode = 0;
      #6000 read_i2c(CHIP_ADDR, 8'h55);
      if(master_datao == 16'hA050)
	$display(" PASSED multi-word write.");
      else
	$display(" FAILED multi-word write.");
      
      
      $display("Testing open drain mode=0");
      #6000 open_drain_mode = 0;
      #6000 test_rw(CHIP_ADDR, 8'hAA, 16'h5569);
      #6000 test_rw(CHIP_ADDR, 8'hAA, 16'h0000);
      #6000 test_rw(CHIP_ADDR, 8'hAA, 16'hFFFF);
      
      #40 $finish;
   end
   

   always #1 clk = !clk;

   always @(posedge clk) begin
      if(slave_we) begin
	 slave_data[slave_reg_addr] <= slave_datao;
	 $display("Writing to slave reg 0x%x data=0x%x", slave_reg_addr, slave_datao);
      end
      slave_datai <= slave_data[slave_reg_addr];
   end

   task test_rw;
      input [6:0] chip_addr;
      input [7:0] reg_addr;
      input [15:0] data;
      begin
	 write_i2c(chip_addr, reg_addr, data);
	 read_i2c(chip_addr, reg_addr);
	 if(master_datao == data)
	   $display("PASSED wrote=read=0x%x", data);
	 else
	   $display("FAILED wrote=0x%x read=0x%x", data, master_datao);
      end
   endtask
   
   
   task write_i2c;
      input [6:0] chip_addr;
      input [7:0] reg_addr;
      input [15:0] data;
      begin
	 @(posedge clk) begin
	    master_chip_addr <= chip_addr;
	    master_reg_addr  <= reg_addr;
	    master_datai     <= data;
	    master_we        <= 1;
	 end
	 @(posedge clk) master_we <= 0;
	 @(posedge clk);
	 
	 while(master_busy) begin
	    @(posedge clk);
	 end
      end
   endtask

   task read_i2c;
      input [6:0] chip_addr;
      input [7:0] reg_addr;
      begin
	 @(posedge clk) begin
	    master_chip_addr <= chip_addr;
	    master_reg_addr  <= reg_addr;
	    master_re        <= 1;
	 end
	 @(posedge clk) master_re <= 0;
	 @(posedge clk);
	 
	 while(master_busy) begin
	    @(posedge clk);
	 end
      end
   endtask

   

endmodule
