`default_nettype none    // catch typos!
`timescale 1ns / 100ps 

// test fir31 module
// input samples are read from fir31.samples
// output samples are written to fir31.output
module fir31_test();
  logic clk,reset,ready;	// fir31 signals
  logic signed [7:0] x;
  logic signed [17:0] y;
  logic [20:0] scount;    // keep track of which sample we're at
  logic [5:0] cycle;      // wait 64 clocks between samples
  integer fin,fout,code;

  initial begin
    // open input/output files
    fin = $fopen("fir31.input","r");
    fout = $fopen("fir31.output","w");
    if (fin == 0 || fout == 0) begin
      $display("can't open file...");
      $stop;
    end

    // initialize state, assert reset for one clock cycle
    scount = 0;
    clk = 0;
    cycle = 0;
    ready = 0;
    x = 0;
    reset = 1;
    #10
    reset = 0;
  end

  // clk has 50% duty cycle, 10ns period
  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (cycle == 6'd63) begin
      // assert ready next cycle, read next sample from file
      ready <= 1;
      code = $fscanf(fin,"%d",x);
      // if we reach the end of the input file, we're done
      if (code != 1) begin
        $fclose(fout);
        $stop;
      end
    end
    else begin
      ready <= 0;
    end

    if (ready) begin
      // starting with sample 32, record results in output file
      if (scount > 31) $fdisplay(fout,"%d",y);
      scount <= scount + 1;
    end

    cycle <= cycle+1;
  end

  fir31 dut(.clk_in(clk),.rst_in(reset),.ready_in(ready),
            .x_in(x),.y_out(y));

endmodule