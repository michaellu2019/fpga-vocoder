module fwd_fft(
  input wire clk_in,              // 100MHz system clock
  input wire rst_in,                // 1 to reset to initial state
  input wire ready_in,             // 1 when data is available
  input wire signed[BIT_DEPTH-1:0] input_data,
  output logic [10:0] read_addr,
  output logic [9:0] write_addr,        
  output logic signed [BIT_DEPTH-1:0] data_out
);        

    localparam WINDOW_SIZE = 1024;
    localparam WINDOW_COUNT = 3;
    localparam MAX_ADDR = (WINDOW_COUNT+1)*WINDOW_SIZE/2;
    parameter BIT_DEPTH = 16; 

    logic [9:0] fft_data_counter;
    logic fft_ready, fft_valid, fft_last;
    logic [BIT_DEPTH-1:0] fft_data;
    logic fft_out_ready, fft_out_valid, fft_out_last;
    logic [2*BIT_DEPTH-1:0] fft_out_data;

    //FFT module:
    //CONFIGURATION:
    //1 channel
    //transform length: 1024
    //target clock frequency: 100 MHz
    //target Data throughput: 50 Msps
    //Auto-select architecture
    //IMPLEMENTATION:
    //Fixed Point, Scaled, Truncation
    //MAKE SURE TO SET NATURAL ORDER FOR OUTPUT ORDERING
    //Input Data Width, Phase Factor Width: Both 12 bits
    //Result uses 12 DSP48 Slices and 6 Block RAMs (under Impl Details)
    xfft_0 my_fft ( .aclk(clk_in), .s_axis_data_tdata(fft_data), 
                    .s_axis_data_tvalid(fft_valid),
                    .s_axis_data_tlast(fft_last), .s_axis_data_tready(fft_ready),
                    .s_axis_config_tdata(0), 
                    .s_axis_config_tvalid(0),
                    .s_axis_config_tready(),
                    .m_axis_data_tdata(fft_out_data), .m_axis_data_tvalid(fft_out_valid),
                    .m_axis_data_tlast(fft_out_last), .m_axis_data_tready(1));
    /*
    // for visualization 

    logic sqsum_valid, sqsum_last, sqsum_ready;
    logic [2*BIT_DEPTH-1:0] sqsum_data;
    
    logic fifo_valid, fifo_last, fifo_ready;
    logic [2*BIT_DEPTH-1:0] fifo_data;

    logic sqrt_valid, sqrt_last;
    logic [BIT_DEPTH-1:0] sqrt_data;

    //custom module (was written with a Vivado AXI-Streaming Wizard so format looks inhuman
    //this is because it was a template I customized.
    square_and_sum_v1_0 mysq(.s00_axis_aclk(clk_in), .s00_axis_aresetn(1'b1),
                            .s00_axis_tready(fft_out_ready),
                            .s00_axis_tdata(fft_out_data),.s00_axis_tlast(fft_out_last),
                            .s00_axis_tvalid(fft_out_valid),.m00_axis_aclk(clk_in),
                            .m00_axis_aresetn(1'b1),. m00_axis_tvalid(sqsum_valid),
                            .m00_axis_tdata(sqsum_data),.m00_axis_tlast(sqsum_last),
                            .m00_axis_tready(sqsum_ready));
    
    //Didn't really need this fifo but put it in for because I felt like it and for practice:
    //This is an AXI4-Stream Data FIFO
    //FIFO Depth: 1024
    //No packet mode, no async clock, 2 sycn stages for clock domain crossing
    //no aclken conversion
    //TDATA Width: 4 bytes
    //Enable TSTRB: No...isn't needed
    //Enable TKEEP: No...isn't needed
    //Enable TLAST: Yes...use this for frame alignment
    //TID Width, TDEST Width, and TUSER width: all 0
    axis_data_fifo_0 myfifo (.s_axis_aclk(clk_in), .s_axis_aresetn(1'b1),
                             .s_axis_tvalid(sqsum_valid), .s_axis_tready(sqsum_ready),
                             .s_axis_tdata(sqsum_data), .s_axis_tlast(sqsum_last),
                             .m_axis_tvalid(fifo_valid), .m_axis_tdata(fifo_data),
                             .m_axis_tready(fifo_ready), .m_axis_tlast(fifo_last));    
    //AXI4-STREAMING Square Root Calculator:
    //CONFIGUATION OPTIONS:
    // Functional Selection: Square Root
    //Architec Config: Parallel (can't change anyways)
    //Pipelining: Max
    //Data Format: UnsignedInteger
    //Phase Format: Radians, the way God intended.
    //Input Width: 24
    //Output Width: 12
    //Round Mode: Truncate
    //0 on the others, and no scale compensation
    //AXI4 STREAM OPTIONS:
    //Has TLAST!!! need to propagate that
    //Don't need a TUSER
    //Flow Control: Blocking
    //optimize Goal: Performance
    //leave other things unchecked.
    cordic_0 mysqrt (.aclk(clk_in), .s_axis_cartesian_tdata(fifo_data),
                     .s_axis_cartesian_tvalid(fifo_valid), .s_axis_cartesian_tlast(fifo_last),
                     .s_axis_cartesian_tready(fifo_ready),.m_axis_dout_tdata(sqrt_data),
                     .m_axis_dout_tvalid(sqrt_valid), .m_axis_dout_tlast(sqrt_last)); 
    */

    always_ff @(posedge clk_in)begin
        if (rst_in) begin
            read_addr <= 0;
            fft_data_counter <= 0;
        end else if (ready_in) begin
            if (fft_ready)begin
                fft_data_counter <= fft_data_counter +1;
                fft_last <= fft_data_counter==WINDOW_SIZE-1;
                fft_valid <= 1'b1;
                fft_data <= input_data; // {~scaled_adc_data[15],scaled_adc_data[14:0]}; //set the FFT DATA here!
                read_addr <= fft_last ? read_addr - WINDOW_SIZE/2 -1 : read_addr + 1;
            end
        end else begin
            fft_data <= 0;
            fft_last <= 0;
            fft_valid <= 0;
        end

        if (rst_in) begin
            write_addr <= 0;
        end else if (fft_out_valid) begin
            write_addr <= fft_out_last ? WINDOW_SIZE-1 : write_addr + 1;
            data_out <= fft_out_data[BIT_DEPTH-1:0];
        end
    end
                       
endmodule 

module inv_fft(
  input wire clk_in,              // 100MHz system clock
  input wire rst_in,                // 1 to reset to initial state
  input wire ready_in,             // 1 when data is available
  input wire signed[BIT_DEPTH-1:0] input_data,
  output logic [9:0] read_addr, write_addr,        
  output logic signed [BIT_DEPTH-1:0] data_out
);        

    localparam WINDOW_SIZE = 1024;
    localparam WINDOW_COUNT = 1;
    localparam MAX_ADDR = (WINDOW_COUNT+1)*WINDOW_SIZE/2;
    parameter BIT_DEPTH = 16; 

    logic [9:0] fft_data_counter;
    logic fft_ready, fft_valid, fft_last;
    logic [BIT_DEPTH-1:0] fft_data;
    logic fft_out_ready, fft_out_valid, fft_out_last;
    logic [2*BIT_DEPTH-1:0] fft_out_data;

    //FFT module:
    //CONFIGURATION:
    //transform length: 1024
    //target clock frequency: 100 MHz
    //target Data throughput: 50 Msps
    //Auto-select architecture
    //IMPLEMENTATION:
    //Fixed Point, Scaled, Truncation
    //MAKE SURE TO SET NATURAL ORDER FOR OUTPUT ORDERING
    //Input Data Width, Phase Factor Width: Both 12 bits
    //Result uses 12 DSP48 Slices and 6 Block RAMs (under Impl Details)
    xfft_0 my_fft ( .aclk(clk_in), .s_axis_data_tdata(fft_data), 
                    .s_axis_data_tvalid(fft_valid),
                    .s_axis_data_tlast(fft_last), .s_axis_data_tready(fft_ready),
                    .s_axis_config_tdata(0), 
                    .s_axis_config_tvalid(1),
                    .s_axis_config_tready(),
                    .m_axis_data_tdata(fft_out_data), .m_axis_data_tvalid(fft_out_valid),
                    .m_axis_data_tlast(fft_out_last), .m_axis_data_tready(1));                     
    
    always_ff @(posedge clk_in)begin
        if (rst_in) begin
            read_addr <= 0;
            fft_data_counter <= 0;
        end else if (ready_in) begin
            if (fft_ready) begin
                fft_data_counter <= fft_data_counter + 1;
                fft_last <= fft_data_counter == WINDOW_SIZE-1;
                fft_valid <= 1'b1;
                fft_data <= input_data;
                read_addr <= fft_last ? 0 : read_addr + 1;
            end
        end else begin
            fft_data <= 0;
            fft_last <= 0;
            fft_valid <= 0;
        end

        if (rst_in) begin
            write_addr <= 0;
        end else if (fft_out_valid) begin
            write_addr <= fft_out_last ? WINDOW_SIZE-1 : write_addr + 1'b1;
            data_out <= fft_out_data[BIT_DEPTH-1:0];
        end
    end
                            
endmodule