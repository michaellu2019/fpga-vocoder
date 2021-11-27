//2020, jodalyst.
//meant for Fall 2020 6.111
//Based in part off of Labs 03 and 05A from that term
//Discussed in Fall 2020  Lecture 10: https://6111.io/F20/lectures/lecture10 

module top_level(   input clk_100mhz,
                    input [15:0] sw,
                    input btnc, btnu, btnd, btnr, btnl,
                    input vauxp3,
                    input vauxn3,
                    input vn_in,
                    input vp_in,
                    output logic[3:0] vga_r,
                    output logic[3:0] vga_b,
                    output logic[3:0] vga_g,
                    output logic vga_hs,
                    output logic vga_vs,
                    output logic [15:0] led,
                    output logic aud_pwm,
                    output logic aud_sd
    );  
    parameter SAMPLE_COUNT = 4164; //2082;//gets approximately (will generate audio at approx 48 kHz sample rate.
    
    logic rst_in;
    assign rst_in = btnd;
    
    logic [15:0] sample_counter;
    logic [11:0] adc_data;
    logic [11:0] sampled_adc_data;
    logic sample_trigger;
    logic adc_ready;
    logic enable;
    logic [7:0] recorder_data;             
    logic [7:0] vol_out;
    logic pwm_val; //pwm signal (HI/LO)
    logic [15:0] scaled_adc_data;
    logic [15:0] scaled_signed_adc_data;
    logic [15:0] fft_data;
    logic       fft_ready;
    logic       fft_valid;
    logic       fft_last;
    logic [9:0] fft_data_counter;
    
    logic fft_out_ready;
    logic fft_out_valid;
    logic fft_out_last;
    logic [31:0] fft_out_data;
    
    logic sqsum_valid;
    logic sqsum_last;
    logic sqsum_ready;
    logic [31:0] sqsum_data;
    
    logic fifo_valid;
    logic fifo_last;
    logic fifo_ready;
    logic [31:0] fifo_data;
    
    logic [23:0] sqrt_data;
    logic sqrt_valid;
    logic sqrt_last;
    
    logic pixel_clk;
    
    
    vga_clk myvga (.clk_in1(clk_100mhz), .clk_out1(pixel_clk));
    
    // FFT stuff
    assign aud_sd = 1;
    assign led = sw; //just to look pretty 
    assign sample_trigger = (sample_counter == SAMPLE_COUNT);

    always_ff @(posedge clk_100mhz)begin
        if (sample_counter == SAMPLE_COUNT)begin
            sample_counter <= 16'b0;
        end else begin
            sample_counter <= sample_counter + 16'b1;
        end
        if (sample_trigger) begin
            scaled_adc_data <= 16*adc_data;
            scaled_signed_adc_data <= {~scaled_adc_data[15],scaled_adc_data[14:0]};
            sampled_adc_data <= {~adc_data[11],adc_data[10:0]}; //convert to signed. incoming data is offset binary
            if (fft_ready)begin
                fft_data_counter <= fft_data_counter +1;
                fft_last <= fft_data_counter==1023;
                fft_valid <= 1'b1;
                fft_data <= {~scaled_adc_data[15],scaled_adc_data[14:0]}; //set the FFT DATA here!
            end
            //https://en.wikipedia.org/wiki/Offset_binary
        end else begin
            fft_data <= 0;
            fft_last <= 0;
            fft_valid <= 0;
        end
    end

    //ADC uncomment when activating!
    xadc_wiz_0 my_adc ( .dclk_in(clk_100mhz), .daddr_in(8'h13), //read from 0x13 for a
                        .vauxn3(vauxn3),.vauxp3(vauxp3),
                        .vp_in(1),.vn_in(1),
                        .di_in(16'b0),
                        .do_out(adc_data),.drdy_out(adc_ready),
                        .den_in(1), .dwe_in(0));
 
 
    //not really used in this demo, but left it in anyways to throw fewer warnings
    recorder myrec( .clk_in(clk_100mhz),.rst_in(btnd),
                    .record_in(btnc),.ready_in(sample_trigger),
                    .filter_in(sw[0]),.mic_in(sampled_adc_data[11:4]),
                    .data_out(recorder_data));   
    //not really used...                                                                                        
    volume_control vc (.vol_in(sw[15:13]),
                       .signal_in(recorder_data), .signal_out(vol_out));
    //not really used here...
    pwm (.clk_in(clk_100mhz), .rst_in(btnd), .level_in({~vol_out[7],vol_out[6:0]}), .pwm_out(pwm_val));
    
    
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
    //Input Data Width, Phase Factor Width: Both 16 bits
    //Result uses 12 DSP48 Slices and 6 Block RAMs (under Impl Details)
    xfft_0 my_fft (.aclk(clk_100mhz), .s_axis_data_tdata(fft_data), 
                    .s_axis_data_tvalid(fft_valid),
                    .s_axis_data_tlast(fft_last), .s_axis_data_tready(fft_ready),
                    .s_axis_config_tdata(0), 
                     .s_axis_config_tvalid(0),
                     .s_axis_config_tready(),
                    .m_axis_data_tdata(fft_out_data), .m_axis_data_tvalid(fft_out_valid),
                    .m_axis_data_tlast(fft_out_last), .m_axis_data_tready(fft_out_ready));
    
    //for debugging commented out, make this whatever size,detail you want:
    //ila_0 myila (.clk(clk_100mhz), .probe0(fifo_data), .probe1(sqrt_data), .probe2(sqsum_data), .probe3(fft_out_data));
    
    //custom module (was written with a Vivado AXI-Streaming Wizard so format looks inhuman
    //this is because it was a template I customized.
    square_and_sum_v1_0 mysq(.s00_axis_aclk(clk_100mhz), .s00_axis_aresetn(1'b1),
                            .s00_axis_tready(fft_out_ready),
                            .s00_axis_tdata(fft_out_data),.s00_axis_tlast(fft_out_last),
                            .s00_axis_tvalid(fft_out_valid),.m00_axis_aclk(clk_100mhz),
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
    axis_data_fifo_0 myfifo (.s_axis_aclk(clk_100mhz), .s_axis_aresetn(1'b1),
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
    //Input Width: 32
    //Output Width: 17
    //Round Mode: Truncate
    //0 on the others, and no scale compensation
    //AXI4 STREAM OPTIONS:
    //Has TLAST!!! need to propagate that
    //Don't need a TUSERband 
    //Flow Control: Blocking
    //optimize Goal: Performance
    //leave other things unchecked.
    cordic_0 mysqrt (.aclk(clk_100mhz), .s_axis_cartesian_tdata(fifo_data),
                     .s_axis_cartesian_tvalid(fifo_valid), .s_axis_cartesian_tlast(fifo_last),
                     .s_axis_cartesian_tready(fifo_ready),.m_axis_dout_tdata(sqrt_data),
                     .m_axis_dout_tvalid(sqrt_valid), .m_axis_dout_tlast(sqrt_last));
    
    logic [9:0] addr_count;
    logic [9:0] draw_addr;
    logic [17:0] spectrogram_count;
    logic [17:0] spectrogram_draw_addr;
    
    logic spectrogram_wea;
    logic [15:0] spectrogram_raw_amp_in;
    
    logic [31:0] raw_amp_out;
    logic [31:0] shifted_amp_out;
    logic [15:0] spectrogram_raw_amp_out;
    
    parameter SPECTROGRAM_WIDTH = 512;
    parameter SPECTROGRAM_HEIGHT = 512;
    
//    assign spectrogram_wea = sqrt_valid && addr_count <= 'd512;
    always_ff @(posedge clk_100mhz) begin
        if (rst_in) begin
            addr_count <= 0;
            spectrogram_count <= 0;
            spectrogram_wea <= 0;
            spectrogram_raw_amp_in <= 0;
        end else if (!rst_in && sqrt_valid)begin
            spectrogram_wea <= addr_count <= SPECTROGRAM_HEIGHT;
            if (sqrt_last) begin
                addr_count <= 'd1023; //allign
            end else begin
                addr_count <= addr_count + 1;
                
                if (addr_count <= SPECTROGRAM_HEIGHT) begin
                    spectrogram_raw_amp_in <= sqrt_data[23:8];
//                    spectrogram_raw_amp_in <= 16'd65000;
                    spectrogram_count <= spectrogram_count + 1;
                end
            end
        end
    end 
         
    //Two Port BRAM: The FFT pipeline files values inot this and the VGA side of things
    //reads the values out as needed!  Separate clocks on both sides so we don't need to
    //worry about clock domain crossing!! (at least not directly)
    //BRAM Generator (v. 8.4)
    //BASIC:
    //Interface Type: Native
    //Memory Type: True Dual Port RAM (leave common clock unticked...since using100 and 65 MHz)
    //leave ECC as is
    //leave Write enable as is (unchecked Byte Write Enabe)
    //Algorithm Options: Minimum Area (not too important anyways)
    //PORT A OPTIONS:
    //Write Width: 32
    //Read Width: 32
    //Write Depth: 1024
    //Read Depth: 1024
    //Operating Mode; Write First (not too important here)
    //Enable Port Type: Use ENA Pin
    //Keep Primitives Output Register checked
    //leave other stuff unchecked
    //PORT B OPTIONS:
    //Should mimic Port A (and should auto-inheret most anyways)
    //leave other tabs as is. the summary tab should report one 36K BRAM being used
    value_bram mvb_raw (.addra(addr_count+3), .clka(clk_100mhz), .dina({8'b0,sqrt_data}),
                    .douta(), .ena(1'b1), .wea(sqrt_valid),.dinb(0),
                    .addrb(draw_addr), .clkb(pixel_clk), .doutb(raw_amp_out),
                    .web(1'b0), .enb(1'b1));    
                    
    value_bram mvb_shifted (.addra(addr_count+3), .clka(clk_100mhz), .dina({8'b0,sqrt_data}),
                    .douta(), .ena(1'b1), .wea(sqrt_valid),.dinb(0),
                    .addrb(draw_addr), .clkb(pixel_clk), .doutb(shifted_amp_out),
                    .web(1'b0), .enb(1'b1));     
                    
    spectrogram_bram msb_raw (.addra(spectrogram_count+3), .clka(clk_100mhz), .dina(spectrogram_raw_amp_in),
                    .douta(), .ena(1'b1), .wea(spectrogram_wea),.dinb(0),
                    .addrb(spectrogram_draw_addr), .clkb(pixel_clk), .doutb(spectrogram_raw_amp_out),
                    .web(1'b0), .enb(1'b1));
                    
    visualizer viz (.clk_in(pixel_clk), .rst_in(btnd), 
                    .raw_amp_out(raw_amp_out), .shifted_amp_out(shifted_amp_out),  
                    .spectrogram_raw_amp_out(spectrogram_raw_amp_out),
                    .amp_scale(sw[3:0]), .visualize_mode(sw[15:14]), .pwm_val(pwm_val), 
                    .draw_addr(draw_addr), .spectrogram_draw_addr(spectrogram_draw_addr),
                    .vga_r(vga_r), .vga_b(vga_b), .vga_g(vga_g), .vga_hs(vga_hs), .vga_vs(vga_vs), 
                    .aud_pwm(aud_pwm));    
    
endmodule

///////////////////////////////////////////////////////////////////////////////
//
// Visualize frequency spectrum for audio data
//
///////////////////////////////////////////////////////////////////////////////

module visualizer(
    input wire clk_in,
    input wire rst_in,
    input wire [31:0] raw_amp_out,
    input wire [31:0] shifted_amp_out,
    input wire [16:0] spectrogram_raw_amp_out,
    input wire [3:0] amp_scale,
    input wire [1:0] visualize_mode,
    input wire pwm_val,
    output logic [9:0] draw_addr,
    output logic [17:0] spectrogram_draw_addr,
    output logic[3:0] vga_r,
    output logic[3:0] vga_b,
    output logic[3:0] vga_g,
    output logic vga_hs,
    output logic vga_vs,
    output logic aud_pwm
);
    parameter MAX_HCOUNT = 1024;
    parameter MAX_VCOUNT = 768;
    
    logic blanking;
    logic [10:0] hcount;
    logic [9:0] vcount;
    logic       vsync;
    logic       hsync;
    logic [11:0] rgb;
    
    parameter SPECTROGRAM_WIDTH = 512;
    parameter SPECTROGRAM_HEIGHT = 512;
    parameter SPECTROGRAM_AMP_SCALE = 10;
    
    // display amplitude vs. frequency for raw audio data (raw_amp_out) and shifted data (shifted_amp_out)         
    always_ff @(posedge clk_in)begin
        if (visualize_mode == 10'd0) begin
            draw_addr <= hcount >> 1;
            if (vcount < MAX_VCOUNT/2 && (raw_amp_out >> amp_scale) >= MAX_VCOUNT/2 - vcount) begin
                // draw top blue bar graph of unshifted frequencies
                rgb <= (raw_amp_out >> amp_scale) >= (MAX_VCOUNT/2 - vcount) << 6 ? 12'b1111_0000_0000 :
                       (raw_amp_out >> amp_scale) >= (MAX_VCOUNT/2 - vcount) << 5 ? 12'b1111_0111_0000 :
                       (raw_amp_out >> amp_scale) >= (MAX_VCOUNT/2 - vcount) << 4 ? 12'b1111_1111_0000 :
                       (raw_amp_out >> amp_scale) >= (MAX_VCOUNT/2 - vcount) << 3 ? 12'b0000_1111_0000 :
                       (raw_amp_out >> amp_scale) >= (MAX_VCOUNT/2 - vcount) << 2 ? 12'b0000_0000_1111 :
                       (raw_amp_out >> amp_scale) >= (MAX_VCOUNT/2 - vcount) << 1 ? 12'b0111_0000_1111 :
                       (raw_amp_out >> amp_scale) >= (MAX_VCOUNT/2 - vcount) << 0 ? 12'b1111_0000_1111 :
                       12'b000_0000_000;
//                rgb <= 12'b0000_0110_1100;
            end else if (vcount >= MAX_VCOUNT/2 && (shifted_amp_out >> amp_scale) >= MAX_VCOUNT - vcount) begin
                // draw bottom red bar graph of shifted frequencies
                rgb <= (shifted_amp_out >> amp_scale) >= (MAX_VCOUNT - vcount) << 6 ? 12'b1111_0000_0000 :
                       (shifted_amp_out >> amp_scale) >= (MAX_VCOUNT - vcount) << 5 ? 12'b1111_0111_0000 :
                       (shifted_amp_out >> amp_scale) >= (MAX_VCOUNT - vcount) << 4 ? 12'b1111_1111_0000 :
                       (shifted_amp_out >> amp_scale) >= (MAX_VCOUNT - vcount) << 3 ? 12'b0000_1111_0000 :
                       (shifted_amp_out >> amp_scale) >= (MAX_VCOUNT - vcount) << 2 ? 12'b0000_0000_1111 :
                       (shifted_amp_out >> amp_scale) >= (MAX_VCOUNT - vcount) << 1 ? 12'b0111_0000_1111 :
                       (shifted_amp_out >> amp_scale) >= (MAX_VCOUNT - vcount) << 0 ? 12'b1111_0000_1111 :
                       12'b000_0000_000;
//                rgb <= 12'b1100_0000_0110;
            end else begin
                rgb <= 12'b0000_0000_0000;
//                rgb <= 12'b1111_1111_1111;
            end
        end else if (visualize_mode == 10'd1) begin 
            spectrogram_draw_addr <= hcount * (SPECTROGRAM_WIDTH + 1) - vcount;
            if (hcount < SPECTROGRAM_WIDTH && vcount < SPECTROGRAM_HEIGHT) begin
                rgb <= (spectrogram_raw_amp_out << amp_scale) >= SPECTROGRAM_AMP_SCALE << 6 ? 12'b1111_0000_0000 :
                       (spectrogram_raw_amp_out << amp_scale) >= SPECTROGRAM_AMP_SCALE << 5 ? 12'b1111_0111_0000 :
                       (spectrogram_raw_amp_out << amp_scale) >= SPECTROGRAM_AMP_SCALE << 4 ? 12'b1111_1111_0000 :
                       (spectrogram_raw_amp_out << amp_scale) >= SPECTROGRAM_AMP_SCALE << 3 ? 12'b0000_1111_0000 :
                       (spectrogram_raw_amp_out << amp_scale) >= SPECTROGRAM_AMP_SCALE << 2 ? 12'b0000_0000_1111 :
                       (spectrogram_raw_amp_out << amp_scale) >= SPECTROGRAM_AMP_SCALE << 1 ? 12'b0111_0000_1111 :
                       (spectrogram_raw_amp_out << amp_scale) >= SPECTROGRAM_AMP_SCALE << 0 ? 12'b1111_0000_1111 :
                       12'b000_0000_000;
            end else begin
                rgb <= 12'b1111_1111_1111;
            end
            
//            draw_addr <= (MAX_VCOUNT - vcount) >> 1;
//            if ((raw_amp_out >> amp_scale) >= hcount) begin
//                // draw spectrogram
//                // use a counter to shift the graph output along the horizontal
////                rgb <= 12'b0000_0110_1100 << (raw_amp_out >> 30);
////                rgb <= {8'b0000_0010, 4'b0001 << (raw_amp_out >> 10'd27)};
//                rgb <= (raw_amp_out >> amp_scale >> 6) >= hcount ? 12'b1111_0000_0000 :
//                       (raw_amp_out >> amp_scale >> 5) >= hcount ? 12'b1111_0111_0000 :
//                       (raw_amp_out >> amp_scale >> 4) >= hcount ? 12'b1111_1111_0000 :
//                       (raw_amp_out >> amp_scale >> 3) >= hcount ? 12'b0000_1111_0000 :
//                       (raw_amp_out >> amp_scale >> 2) >= hcount ? 12'b0000_0000_1111 :
//                       (raw_amp_out >> amp_scale >> 1) >= hcount ? 12'b0111_0000_1111 :
//                       (raw_amp_out >> amp_scale >> 0) >= hcount ? 12'b1111_0000_1111 :
//                       12'b000_0110_000;
//            end else begin
////                rgb <= 12'b0000_0000_0000;
//                rgb <= 12'b1111_1111_1111;
//            end
        end
    end                 
        
    // VGA black magic
    xvga myyvga (.vclock_in(clk_in), .rst_in(rst_in), .visualize_mode(visualize_mode), .hcount_out(hcount),  
                 .vcount_out(vcount), .vsync_out(vsync), .hsync_out(hsync),
                 .blank_out(blanking));               
                        
    assign vga_r = ~blanking ? rgb[11:8]: 0;
    assign vga_g = ~blanking ? rgb[7:4] : 0;
    assign vga_b = ~blanking ? rgb[3:0] : 0;
    
    assign vga_hs = ~hsync;
    assign vga_vs = ~vsync;

    assign aud_pwm = pwm_val?1'bZ:1'b0; 
endmodule



///////////////////////////////////////////////////////////////////////////////
//
// Record/playback
//
///////////////////////////////////////////////////////////////////////////////


module recorder(
  input logic clk_in,              // 100MHz system clock
  input logic rst_in,               // 1 to reset to initial state
  input logic record_in,            // 0 for playback, 1 for record
  input logic ready_in,             // 1 when data is available
  input logic filter_in,            // 1 when using low-pass filter
  input logic signed [7:0] mic_in,         // 8-bit PCM data from mic
  output logic signed [7:0] data_out       // 8-bit PCM data to headphone
); 
    logic [7:0] tone_750;
    logic [7:0] tone_440;
    //generate a 750 Hz tone
    sine_generator  tone750hz (   .clk_in(clk_in), .rst_in(rst_in), 
                                 .step_in(ready_in), .amp_out(tone_750));
    //generate a 440 Hz tone
    sine_generator  #(.PHASE_INCR(32'd39370534)) tone440hz(.clk_in(clk_in), .rst_in(rst_in), 
                               .step_in(ready_in), .amp_out(tone_440));                          
    //logic [7:0] data_to_bram;
    //logic [7:0] data_from_bram;
    //logic [15:0] addr;
    //logic wea;
    //  blk_mem_gen_0(.addra(addr), .clka(clk_in), .dina(data_to_bram), .douta(data_from_bram), 
    //                .ena(1), .wea(bram_write));                                  
    
    always_ff @(posedge clk_in)begin
        data_out = filter_in?tone_440:tone_750; //send tone immediately to output
        data_out = mic_in;
    end                            
endmodule                              



///////////////////////////////////////////////////////////////////////////////
//
// 31-tap FIR filter, 8-bit signed data, 10-bit signed coefficients.
// ready is asserted whenever there is a new sample on the X input,
// the Y output should also be sampled at the same time.  Assumes at
// least 32 clocks between ready assertions.  Note that since the
// coefficients have been scaled by 2**10, so has the output (it's
// expanded from 8 bits to 18 bits).  To get an 8-bit result from the
// filter just divide by 2**10, ie, use Y[17:10].
//
///////////////////////////////////////////////////////////////////////////////

module fir31(
  input  clk_in,rst_in,ready_in,
  input signed [7:0] x_in,
  output logic signed [17:0] y_out
);
  // for now just pass data through
  always_ff @(posedge clk_in) begin
    if (ready_in) y_out <= {x_in,10'd0};
  end
endmodule





///////////////////////////////////////////////////////////////////////////////
//
// Coefficients for a 31-tap low-pass FIR filter with Wn=.125 (eg, 3kHz for a
// 48kHz sample rate).  Since we're doing integer arithmetic, we've scaled
// the coefficients by 2**10
// Matlab command: round(fir1(30,.125)*1024)
//
///////////////////////////////////////////////////////////////////////////////

module coeffs31(
  input  [4:0] index_in,
  output logic signed [9:0] coeff_out
);
  logic signed [9:0] coeff;
  assign coeff_out = coeff;
  // tools will turn this into a 31x10 ROM
  always_comb begin
    case (index_in)
      5'd0:  coeff = -10'sd1;
      5'd1:  coeff = -10'sd1;
      5'd2:  coeff = -10'sd3;
      5'd3:  coeff = -10'sd5;
      5'd4:  coeff = -10'sd6;
      5'd5:  coeff = -10'sd7;
      5'd6:  coeff = -10'sd5;
      5'd7:  coeff = 10'sd0;
      5'd8:  coeff = 10'sd10;
      5'd9:  coeff = 10'sd26;
      5'd10: coeff = 10'sd46;
      5'd11: coeff = 10'sd69;
      5'd12: coeff = 10'sd91;
      5'd13: coeff = 10'sd110;
      5'd14: coeff = 10'sd123;
      5'd15: coeff = 10'sd128;
      5'd16: coeff = 10'sd123;
      5'd17: coeff = 10'sd110;
      5'd18: coeff = 10'sd91;
      5'd19: coeff = 10'sd69;
      5'd20: coeff = 10'sd46;
      5'd21: coeff = 10'sd26;
      5'd22: coeff = 10'sd10;
      5'd23: coeff = 10'sd0;
      5'd24: coeff = -10'sd5;
      5'd25: coeff = -10'sd7;
      5'd26: coeff = -10'sd6;
      5'd27: coeff = -10'sd5;
      5'd28: coeff = -10'sd3;
      5'd29: coeff = -10'sd1;
      5'd30: coeff = -10'sd1;
      default: coeff = 10'hXXX;
    endcase
  end
endmodule

//Volume Control
module volume_control (input [2:0] vol_in, input signed [7:0] signal_in, output logic signed[7:0] signal_out);
    logic [2:0] shift;
    assign shift = 3'd7 - vol_in;
    assign signal_out = signal_in>>>shift;
endmodule

//PWM generator for audio generation!
module pwm (input clk_in, input rst_in, input [7:0] level_in, output logic pwm_out);
    logic [7:0] count;
    assign pwm_out = count<level_in;
    always_ff @(posedge clk_in)begin
        if (rst_in)begin
            count <= 8'b0;
        end else begin
            count <= count+8'b1;
        end
    end
endmodule




//Sine Wave Generator
module sine_generator ( input clk_in, input rst_in, //clock and reset
                        input step_in, //trigger a phase step (rate at which you run sine generator)
                        output logic [7:0] amp_out); //output phase   
    parameter PHASE_INCR = 32'b1000_0000_0000_0000_0000_0000_0000_0000>>5; //1/64th of 48 khz is 750 Hz
    logic [7:0] divider;
    logic [31:0] phase;
    logic [7:0] amp;
    assign amp_out = {~amp[7],amp[6:0]};
    sine_lut lut_1(.clk_in(clk_in), .phase_in(phase[31:26]), .amp_out(amp));
    
    always_ff @(posedge clk_in)begin
        if (rst_in)begin
            divider <= 8'b0;
            phase <= 32'b0;
        end else if (step_in)begin
            phase <= phase+PHASE_INCR;
        end
    end
endmodule

//6bit sine lookup, 8bit depth
module sine_lut(input[5:0] phase_in, input clk_in, output logic[7:0] amp_out);
  always_ff @(posedge clk_in)begin
    case(phase_in)
      6'd0: amp_out<=8'd128;
      6'd1: amp_out<=8'd140;
      6'd2: amp_out<=8'd152;
      6'd3: amp_out<=8'd165;
      6'd4: amp_out<=8'd176;
      6'd5: amp_out<=8'd188;
      6'd6: amp_out<=8'd198;
      6'd7: amp_out<=8'd208;
      6'd8: amp_out<=8'd218;
      6'd9: amp_out<=8'd226;
      6'd10: amp_out<=8'd234;
      6'd11: amp_out<=8'd240;
      6'd12: amp_out<=8'd245;
      6'd13: amp_out<=8'd250;
      6'd14: amp_out<=8'd253;
      6'd15: amp_out<=8'd254;
      6'd16: amp_out<=8'd255;
      6'd17: amp_out<=8'd254;
      6'd18: amp_out<=8'd253;
      6'd19: amp_out<=8'd250;
      6'd20: amp_out<=8'd245;
      6'd21: amp_out<=8'd240;
      6'd22: amp_out<=8'd234;
      6'd23: amp_out<=8'd226;
      6'd24: amp_out<=8'd218;
      6'd25: amp_out<=8'd208;
      6'd26: amp_out<=8'd198;
      6'd27: amp_out<=8'd188;
      6'd28: amp_out<=8'd176;
      6'd29: amp_out<=8'd165;
      6'd30: amp_out<=8'd152;
      6'd31: amp_out<=8'd140;
      6'd32: amp_out<=8'd128;
      6'd33: amp_out<=8'd115;
      6'd34: amp_out<=8'd103;
      6'd35: amp_out<=8'd90;
      6'd36: amp_out<=8'd79;
      6'd37: amp_out<=8'd67;
      6'd38: amp_out<=8'd57;
      6'd39: amp_out<=8'd47;
      6'd40: amp_out<=8'd37;
      6'd41: amp_out<=8'd29;
      6'd42: amp_out<=8'd21;
      6'd43: amp_out<=8'd15;
      6'd44: amp_out<=8'd10;
      6'd45: amp_out<=8'd5;
      6'd46: amp_out<=8'd2;
      6'd47: amp_out<=8'd1;
      6'd48: amp_out<=8'd0;
      6'd49: amp_out<=8'd1;
      6'd50: amp_out<=8'd2;
      6'd51: amp_out<=8'd5;
      6'd52: amp_out<=8'd10;
      6'd53: amp_out<=8'd15;
      6'd54: amp_out<=8'd21;
      6'd55: amp_out<=8'd29;
      6'd56: amp_out<=8'd37;
      6'd57: amp_out<=8'd47;
      6'd58: amp_out<=8'd57;
      6'd59: amp_out<=8'd67;
      6'd60: amp_out<=8'd79;
      6'd61: amp_out<=8'd90;
      6'd62: amp_out<=8'd103;
      6'd63: amp_out<=8'd115;
    endcase
  end
endmodule



module square_and_sum_v1_0 #
    (
        // Users to add parameters here

        // User parameters ends
        // Do not modify the parameters beyond this line


        // Parameters of Axi Slave Bus Interface S00_AXIS
        parameter integer C_S00_AXIS_TDATA_WIDTH    = 32,

        // Parameters of Axi Master Bus Interface M00_AXIS
        parameter integer C_M00_AXIS_TDATA_WIDTH    = 32,
        parameter integer C_M00_AXIS_START_COUNT    = 32
    )
    (
        // Users to add ports here

        // User ports ends
        // Do not modify the ports beyond this line


        // Ports of Axi Slave Bus Interface S00_AXIS
        input wire  s00_axis_aclk,
        input wire  s00_axis_aresetn,
        output wire  s00_axis_tready,
        input wire [C_S00_AXIS_TDATA_WIDTH-1 : 0] s00_axis_tdata,
        input wire  s00_axis_tlast,
        input wire  s00_axis_tvalid,

        // Ports of Axi Master Bus Interface M00_AXIS
        input wire  m00_axis_aclk,
        input wire  m00_axis_aresetn,
        output wire  m00_axis_tvalid,
        output wire [C_M00_AXIS_TDATA_WIDTH-1 : 0] m00_axis_tdata,
        output wire  m00_axis_tlast,
        input wire  m00_axis_tready
    );
    
    reg m00_axis_tvalid_reg_pre;
    reg m00_axis_tlast_reg_pre;
    reg m00_axis_tvalid_reg;
    reg m00_axis_tlast_reg;
    reg [C_M00_AXIS_TDATA_WIDTH-1 : 0] m00_axis_tdata_reg;
    
    reg s00_axis_tready_reg;
    reg signed [31:0] real_square;
    reg signed [31:0] imag_square;
    
    wire signed [15:0] real_in;
    wire signed [15:0] imag_in;
    assign real_in = s00_axis_tdata[31:16];
    assign imag_in = s00_axis_tdata[15:0];
    
    assign m00_axis_tvalid = m00_axis_tvalid_reg;
    assign m00_axis_tlast = m00_axis_tlast_reg;
    assign m00_axis_tdata = m00_axis_tdata_reg;
    assign s00_axis_tready = s00_axis_tready_reg;
    
    always @(posedge s00_axis_aclk)begin
        if (s00_axis_aresetn==0)begin
            s00_axis_tready_reg <= 0;
        end else begin
            s00_axis_tready_reg <= m00_axis_tready; //if what you're feeding data to is ready, then you're ready.
        end
    end
    
    always @(posedge m00_axis_aclk)begin
        if (m00_axis_aresetn==0)begin
            m00_axis_tvalid_reg <= 0;
            m00_axis_tlast_reg <= 0;
            m00_axis_tdata_reg <= 0;
        end else begin
            m00_axis_tvalid_reg_pre <= s00_axis_tvalid; //when new data is coming, you've got new data to put out
            m00_axis_tlast_reg_pre <= s00_axis_tlast; //
            real_square <= real_in*real_in;
            imag_square <= imag_in*imag_in;
            
            m00_axis_tvalid_reg <= m00_axis_tvalid_reg_pre; //when new data is coming, you've got new data to put out
            m00_axis_tlast_reg <= m00_axis_tlast_reg_pre; //
            m00_axis_tdata_reg <= real_square + imag_square;
        end
    end
endmodule



//////////////////////////////////////////////////////////////////////////////////
// Update: 8/8/2019 GH 
// Create Date: 10/02/2015 02:05:19 AM
// Module Name: xvga
//
// xvga: Generate VGA display signals (1024 x 768 @ 60Hz)
//
//                              ---- HORIZONTAL -----     ------VERTICAL -----
//                              Active                    Active
//                    Freq      Video   FP  Sync   BP      Video   FP  Sync  BP
//   640x480, 60Hz    25.175    640     16    96   48       480    11   2    31
//   800x600, 60Hz    40.000    800     40   128   88       600     1   4    23
//   1024x768, 60Hz   65.000    1024    24   136  160       768     3   6    29
//   1280x1024, 60Hz  108.00    1280    48   112  248       768     1   3    38
//   1280x720p 60Hz   75.25     1280    72    80  216       720     3   5    30
//   1920x1080 60Hz   148.5     1920    88    44  148      1080     4   5    36
//
// change the clock frequency, front porches, sync's, and back porches to create 
// other screen resolutions
////////////////////////////////////////////////////////////////////////////////

module xvga(input wire vclock_in,
            input wire rst_in,
            input wire [1:0] visualize_mode,
            output logic [10:0] hcount_out,    // pixel number on current line
            output logic [9:0] vcount_out,     // line number
            output logic vsync_out, hsync_out,
            output logic blank_out);

    parameter DISPLAY_WIDTH  = 1024;      // display width
    parameter DISPLAY_HEIGHT = 768;       // number of lines

    parameter  H_FP = 24;                 // horizontal front porch
    parameter  H_SYNC_PULSE = 136;        // horizontal sync
    parameter  H_BP = 160;                // horizontal back porch

    parameter  V_FP = 3;                  // vertical front porch
    parameter  V_SYNC_PULSE = 6;          // vertical sync 
    parameter  V_BP = 29;                 // vertical back porch

    // horizontal: 1344 pixels total
    // display 1024 pixels per line
    logic hblank,vblank;
    logic hsyncon,hsyncoff,hreset,hblankon;
    assign hblankon = (hcount_out == (DISPLAY_WIDTH -1));    
    assign hsyncon = (hcount_out == (DISPLAY_WIDTH + H_FP - 1));  //1047
    assign hsyncoff = (hcount_out == (DISPLAY_WIDTH + H_FP + H_SYNC_PULSE - 1));  // 1183
    assign hreset = (hcount_out == (DISPLAY_WIDTH + H_FP + H_SYNC_PULSE + H_BP - 1));  //1343

    // vertical: 806 lines total
    // display 768 lines
    logic vsyncon,vsyncoff,vreset,vblankon;
    assign vblankon = hreset & (vcount_out == (DISPLAY_HEIGHT - 1));   // 767 
    assign vsyncon = hreset & (vcount_out == (DISPLAY_HEIGHT + V_FP - 1));  // 771
    assign vsyncoff = hreset & (vcount_out == (DISPLAY_HEIGHT + V_FP + V_SYNC_PULSE - 1));  // 777
    assign vreset = hreset & (vcount_out == (DISPLAY_HEIGHT + V_FP + V_SYNC_PULSE + V_BP - 1)); // 805

    // sync and blanking
    logic next_hblank,next_vblank;
    assign next_hblank = hreset ? 0 : hblankon ? 1 : hblank;
    assign next_vblank = vreset ? 0 : vblankon ? 1 : vblank;
   
    always_ff @(posedge vclock_in) begin
        hcount_out <= hreset ? 0 : hcount_out + 1;
        hblank <= next_hblank;
        hsync_out <= hsyncon ? 0 : hsyncoff ? 1 : hsync_out;  // active low 

        vcount_out <= hreset ? (vreset ? 0 : vcount_out + 1) : vcount_out;
        vblank <= next_vblank;
        vsync_out <= vsyncon ? 0 : vsyncoff ? 1 : vsync_out;  // active low

        blank_out <= next_vblank | (next_hblank & ~hreset);
    end
endmodule
