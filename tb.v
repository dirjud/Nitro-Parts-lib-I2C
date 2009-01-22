module tb();
   wire SDA, SCL;

   reg clk, reset_n;
   wire [11:0] clk_divider = 6;
   
   reg [6:0]   master_chip_addr;
   reg [7:0]   master_reg_addr;
   reg [15:0]  master_datai;
   reg 	       master_we;
   reg 	       master_re;
   wire [4:0] master_status;
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
   
   i2c_master i2c_master
     (.clk		(clk),
      .reset_n		(reset_n),
      .clk_divider	(clk_divider),
      .chip_addr	(master_chip_addr),
      .reg_addr		(master_reg_addr),
      .datai		(master_datai),
      .we		(master_we),
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
   
   i2c_slave i2c_slave
     (.clk		(clk),
      .reset_n		(reset_n),
      .chip_addr	(slave_chip_addr),
      .reg_addr		(slave_reg_addr),
      .datai		(slave_datai),
      .we		(slave_we),
      .datao		(slave_datao),
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
      slave_chip_addr = CHIP_ADDR;
      master_chip_addr = 0;
      master_reg_addr = 0;
      master_datai = 0;
      master_we = 0;
      master_re = 0;
      
      
      $dumpfile("i2c_test.vcd");
      $dumpvars(0, tb);
      
	
      #40 reset_n = 1;

      test_rw(CHIP_ADDR, 8'h55, 16'hAAC3);
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
	   $display("PASSED");
	 else
	   $display("FAILED");
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