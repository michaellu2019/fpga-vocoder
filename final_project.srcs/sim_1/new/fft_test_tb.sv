`default_nettype none    // catch typos!
`timescale 1ns / 100ps 

module fft_test_tb();

parameter NFFT_WINDOW_SIZE = 64;
  logic clk,reset,ready;
  logic signed [15:0] x;
  logic signed [15:0] y, z, data_from_input_aud_bram;
  logic [5:0] write_addr1, read_addr1,read_addr4;
  logic recorder_valid_out, recorder_last_out, playback_start;
  
  logic fft_ready, fft_valid, fft_last;
    logic [31:0] fft_data;
    logic [5:0] fft_data_counter;
    logic fft_out_ready, fft_out_valid, fft_out_last;
    logic [31:0] fft_out_data;
    
     logic inv_fft_valid, inv_fft_last, inv_fft_ready;
    logic [31:0] inv_fft_data;
    logic [5:0] inv_fft_data_counter;
    logic inv_fft_out_valid, inv_fft_out_last;
    logic [31:0] inv_fft_out_data;
    
    logic fft_uploading, inv_fft_uploading;
  
  logic [20:0] scount;    // keep track of which sample we're at
  logic [5:0] cycle;      // wait 64 clocks between samples
  integer fin,fout,code;

  initial begin
    // open input/output files
    //CHANGE THESE TO ACTUAL FILE NAMES!YOU MUST DO THIS
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
    read_addr1 = 0;
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
      read_addr1 <= read_addr1 + 1;
    end
    /*if (window_finish) begin
            fft_uploading <= 1;
        end
        if (fft_uploading) begin
            if (fft_ready) begin
                fft_data_counter <= fft_data_counter +1;
                fft_last <= fft_data_counter == NFFT_WINDOW_SIZE-1;
                fft_valid <= 1'b1;
                fft_data <= data_from_input_aud_bram; //set the FFT DATA here!
                read_addr1 <= fft_last ? 0 : read_addr1 + 1;
                if (fft_last) fft_uploading <= 0; 
            end else begin
                fft_data <= 0;
                fft_last <= 0;
                fft_valid <= 0;
            end
        end*/

    cycle <= cycle+1;
  end
  
    bram_16bit input_audio_bram (
        .clka(clk),    // input wire clka
        .wea(1),      // input wire [0 : 0] wea <-- PORT A ONLY FOR WRITING
        .addra(write_addr1),  // input wire [10 : 0] addra
        .dina(y),    // input wire [11 : 0] dina
        .clkb(clk),    // input wire clkb
        .addrb(read_addr1),  // input wire [10 : 0] addrb
        .doutb(data_from_input_aud_bram)  // output wire [11 : 0] doutb
    );

    recorder#(.WINDOW_SIZE(5'd16),.MAX_ADDR(7'd64),.ADDRESS_BIT_WIDTH(6)) myrec( .clk_in(clk),.rst_in(reset),
                    .ready_in(ready),.filter_in(1),
                    .mic_in(x),
                    .write_addr(write_addr1),
                    .recorder_last(recorder_last_out),
                    .recorder_valid(recorder_valid_out),
                    .data_out(y));
                    
    playback#(.WINDOW_SIZE(5'd16),.MAX_ADDR(7'd64),.ADDRESS_BIT_WIDTH(6)) player(    .clk_in(clk), .rst_in(reset),
                        .ready_in(ready),.filter_in(1),
                        .read_addr(read_addr4),
                        .input_data(data_from_input_aud_bram),
                        .playback_start(recorder_last_out),
                        .data_out(z));  
    /*                
    fft_test fwd_fft (.aclk(clk), .s_axis_data_tdata(fft_data), 
                    .s_axis_data_tvalid(fft_valid),
                    .s_axis_data_tlast(fft_last), .s_axis_data_tready(fft_ready),
                    .s_axis_config_tdata(0), 
                     .s_axis_config_tvalid(0),
                     .s_axis_config_tready(),
                    .m_axis_data_tdata(fft_out_data), .m_axis_data_tvalid(fft_out_valid),
                    .m_axis_data_tlast(fft_out_last), .m_axis_data_tready(1));
*/

endmodule