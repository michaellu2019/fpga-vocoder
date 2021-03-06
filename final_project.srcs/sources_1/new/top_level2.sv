//2020, jodalyst.
//meant for Fall 2020 6.111
//Based in part off of Labs 03 and 05A from that term
//Discussed in Fall 2020  Lecture 10: https://6111.io/F20/lectures/lecture10 

module top_level_2(   input clk_100mhz,
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
    parameter BIT_DEPTH = 16;    
    parameter SAMPLE_COUNT = 2082;//gets approximately (will generate audio at approx 48 kHz sample rate.
    logic [15:0] sample_counter;
    logic sample_trigger;
    logic adc_ready;
    logic [BIT_DEPTH-1:0] recorder_data, playback_data, vol_out; 
    
    //parameter SAMPLE_COUNT = 4164; //2082;//gets approximately (will generate audio at approx 48 kHz sample rate.
    
    logic [11:0] adc_data, sampled_adc_data;
    logic sample_trigger;
    logic adc_ready;       
    logic pwm_val; //pwm signal (HI/LO)
    logic [BIT_DEPTH-1:0] scaled_adc_data;
    logic [BIT_DEPTH-1:0] scaled_signed_adc_data;
    
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
    
    
    clk_wiz_0 myvga (.clk_in1(clk_100mhz), .clk_out1(pixel_clk));
    
    logic [BIT_DEPTH-1:0] data_to_input_aud_bram;
    logic [BIT_DEPTH-1:0] data_from_input_aud_bram;
    logic [10:0] write_addr1, read_addr1;
    assign data_to_input_aud_bram = recorder_data;

    // Simple Dual Port BRAM (Port A for writing, Port B for reading)
    // read depth = 1024*2
    // bit depth = 16
    blk_mem_gen_0 input_audio_bram (
        .clka(clk_100mhz),    // input wire clka
        .ena(1),      // input wire ena
        .wea(1),      // input wire [0 : 0] wea <-- PORT A ONLY FOR WRITING
        .addra(write_addr1),  // input wire [10 : 0] addra
        .dina(data_to_input_aud_bram),    // input wire [11 : 0] dina
        .clkb(clk_100mhz),    // input wire clkb
        .enb(1),      // input wire enb
        .addrb(read_addr1),  // input wire [10 : 0] addrb
        .doutb(data_from_input_aud_bram)  // output wire [11 : 0] doutb
    ); 
    
    logic [7:0] data_to_input_aud_bram2;
    logic [7:0] data_from_input_aud_bram2;
    logic [10:0] write_addr11, read_addr11;
    assign write_addr11 = write_addr1;
    assign data_to_input_aud_bram2 = recorder_data[BIT_DEPTH-1: BIT_DEPTH-1-7];

    // Simple Dual Port BRAM (Port A for writing, Port B for reading)
    // read depth = 1024*2
    // bit depth = 8
    blk_mem_gen_0 input_audio_bram2 (
        .clka(clk_100mhz),    // input wire clka
        .ena(1),      // input wire ena
        .wea(1),      // input wire [0 : 0] wea <-- PORT A ONLY FOR WRITING
        .addra(write_addr11),  // input wire [10 : 0] addra
        .dina(data_to_input_aud_bram2),    // input wire [11 : 0] dina
        .clkb(clk_100mhz),    // input wire clkb
        .enb(1),      // input wire enb
        .addrb(read_addr11),  // input wire [10 : 0] addrb
        .doutb(data_from_input_aud_bram2)  // output wire [11 : 0] doutb
    );  
    
    logic [BIT_DEPTH-1:0] data_to_fwd_fft_bram;
    assign data_to_fwd_fft_bram = fft_out_data[BIT_DEPTH-1:0];
    logic [BIT_DEPTH-1:0] data_from_fwd_fft_bram;
    logic [9:0] write_addr2, read_addr2;

    // Simple Dual Port BRAM (Port A for writing, Port B for reading)
    // read depth = 1024
    // bit depth = 16
    blk_mem_gen_1 fwd_fft_bram (
        .clka(clk_100mhz),    // input wire clka
        .ena(1),      // input wire ena
        .wea(1),      // input wire [0 : 0] wea <-- PORT A ONLY FOR WRITING
        .addra(write_addr2),  // input wire [10 : 0] addra
        .dina(data_to_fwd_fft_bram),    // input wire [11 : 0] dina
        .clkb(clk_100mhz),    // input wire clkb
        .enb(1),      // input wire enb
        .addrb(read_addr2),  // input wire [10 : 0] addrb
        .doutb(data_from_fwd_fft_bram)  // output wire [11 : 0] doutb
    ); 
    
    logic [BIT_DEPTH-1:0] data_to_inv_fft_bram;
    logic [BIT_DEPTH-1:0] data_from_inv_fft_bram;
    assign data_to_inv_fft_bram = inv_fft_out_data[BIT_DEPTH-1:0];
    logic [9:0] write_addr4, read_addr4;

    // Simple Dual Port BRAM (Port A for writing, Port B for reading)
    // read depth = 1024
    // bit depth = 16
    blk_mem_gen_1 inv_fft_bram (
        .clka(clk_100mhz),    // input wire clka
        .ena(1),      // input wire ena
        .wea(1),      // input wire [0 : 0] wea <-- PORT A ONLY FOR WRITING
        .addra(write_addr4),  // input wire [10 : 0] addra
        .dina(data_to_inv_fft_bram),    // input wire [11 : 0] dina
        .clkb(clk_100mhz),    // input wire clkb
        .enb(1),      // input wire enb
        .addrb(read_addr4),  // input wire [10 : 0] addrb
        .doutb(data_from_inv_fft_bram)  // output wire [11 : 0] doutb
    );  
    
    assign aud_sd = 1;
    assign led = sw; //just to look pretty 
    assign sample_trigger = (sample_counter == SAMPLE_COUNT);
    
    logic   fft_ready, fft_valid, fft_last;
    logic [BIT_DEPTH-1:0] fft_data;
    logic [9:0] fft_data_counter;
    logic fft_out_ready, fft_out_valid, fft_out_last;
    logic [2*BIT_DEPTH-1:0] fft_out_data;
    
    logic   fft_ready2, fft_valid2, fft_last2;
    logic [8-1:0] fft_data2;
    logic [9:0] fft_data_counter2;
    logic fft_out_ready, fft_out_valid2, fft_out_last2;
    logic [2*8-1:0] fft_out_data2;
    
    logic inv_fft_valid, inv_fft_last, inv_fft_ready;
    logic [BIT_DEPTH-1:0] inv_fft_data;
    logic [9:0] inv_fft_data_counter;
    logic inv_fft_out_valid, inv_fft_out_last;
    logic [2*BIT_DEPTH-1:0] inv_fft_out_data;

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
                fft_data <= data_from_input_aud_bram; //set the FFT DATA here!
                read_addr1 <= fft_last ? read_addr1 - 512 -1 : read_addr1 + 1;
            end
            if (fft_ready2) begin
                fft_data_counter2 <= fft_data_counter2 + 1;
                fft_last2 <= fft_data_counter2==1023;
                fft_valid2 <= 1'b1;
                fft_data2 <= data_from_input_aud_bram2; //set the FFT DATA here!
                read_addr11 <= fft_last2 ? read_addr11 - 512 -1 : read_addr11 + 1;
            end
            if (inv_fft_ready) begin
                inv_fft_data_counter <= inv_fft_data_counter + 1;
                inv_fft_last <= inv_fft_data_counter == 1023;
                inv_fft_valid <= 1'b1;
                inv_fft_data <= data_from_fwd_fft_bram;
                read_addr2 <= inv_fft_last ? 0 : read_addr2 + 1;
            end
            //https://en.wikipedia.org/wiki/Offset_binary
        end else begin
            fft_data <= 0;
            fft_last <= 0;
            fft_valid <= 0;
            fft_data2 <= 0;
            fft_last2 <= 0;
            fft_valid2 <= 0;
            inv_fft_data <= 0;
            inv_fft_last <= 0;
            inv_fft_valid <= 0;
        end
    end

    //ADC uncomment when activating!
    xadc_wiz_0 my_adc ( .dclk_in(clk_100mhz), .daddr_in(8'h13), //read from 0x13 for a
                        .vauxn3(vauxn3),.vauxp3(vauxp3),
                        .vp_in(1),.vn_in(1),
                        .di_in(16'b0),
                        .do_out(adc_data),.drdy_out(adc_ready),
                        .den_in(1), .dwe_in(0));
 
    recorder myrec( .clk_in(clk_100mhz),.rst_in(btnd),
                    .ready_in(sample_trigger),.filter_in(sw[0]),
                    .mic_in(scaled_signed_adc_data),
                    .fft_start(fft_start),
                    .write_addr(write_addr1),
                    .data_out(recorder_data)); 
    
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
    xfft_0 fwd_fft (.aclk(clk_100mhz), .s_axis_data_tdata(fft_data), 
                    .s_axis_data_tvalid(fft_valid),
                    .s_axis_data_tlast(fft_last), .s_axis_data_tready(fft_ready),
                    .s_axis_config_tdata(0), 
                     .s_axis_config_tvalid(0),
                     .s_axis_config_tready(),
                    .m_axis_data_tdata(fft_out_data), .m_axis_data_tvalid(fft_out_valid),
                    .m_axis_data_tlast(fft_out_last), .m_axis_data_tready(fft_out_ready));
                    
    freq_detection_fft fwd_fft2 (.aclk(clk_100mhz), .s_axis_data_tdata(fft_data2), 
                    .s_axis_data_tvalid(fft_valid2),
                    .s_axis_data_tlast(fft_last2), .s_axis_data_tready(fft_ready2),
                    .s_axis_config_tdata(0), 
                     .s_axis_config_tvalid(0),
                     .s_axis_config_tready(),
                    .m_axis_data_tdata(fft_out_data2), .m_axis_data_tvalid(fft_out_valid2),
                    .m_axis_data_tlast(fft_out_last2), .m_axis_data_tready(1));
                            
    
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
    //Output Width: 16
    //Round Mode: Truncate
    //0 on the others, and no scale compensation
    //AXI4 STREAM OPTIONS:
    //Has TLAST!!! need to propagate that
    //Don't need a TUSER
    //Flow Control: Blocking
    //optimize Goal: Performance
    //leave other things unchecked.
    cordic_0 mysqrt (.aclk(clk_100mhz), .s_axis_cartesian_tdata(fifo_data),
                     .s_axis_cartesian_tvalid(fifo_valid), .s_axis_cartesian_tlast(fifo_last),
                     .s_axis_cartesian_tready(fifo_ready),.m_axis_dout_tdata(sqrt_data),
                     .m_axis_dout_tvalid(sqrt_valid), .m_axis_dout_tlast(sqrt_last));
                 
    xfft_0 inv_fft (.aclk(clk_100mhz), .s_axis_data_tdata(inv_fft_data), 
                    .s_axis_data_tvalid(inv_fft_valid),
                    .s_axis_data_tlast(inv_fft_last), .s_axis_data_tready(inv_fft_ready),
                    .s_axis_config_tdata(fft_config_data), 
                    .s_axis_config_tvalid(1),
                    .s_axis_config_tready(),
                    .m_axis_data_tdata(inv_fft_out_data), .m_axis_data_tvalid(inv_fft_out_valid),
                    .m_axis_data_tlast(inv_fft_out_last), .m_axis_data_tready(1));
             
    playback player(    .clk_in(clk_100mhz), .rst_in(btnd),
                        .ready_in(sample_trigger),.filter_in(sw[1]),
                        .read_addr(read_addr4),
                        .input_data(data_from_inv_fft_bram),
                        .data_out(playback_data));  
                                                                                                          
    volume_control vc (.vol_in(sw[15:13]),
                       .signal_in(playback_data[BIT_DEPTH-1: BIT_DEPTH-1-16+1]), .signal_out(vol_out));

    pwm (.clk_in(clk_100mhz), .rst_in(btnd), .level_in({~vol_out[11],vol_out[10:0]}), .pwm_out(pwm_val));
    assign aud_pwm = pwm_val?1'bZ:1'b0;
      
    logic [9:0] addr_count;
    logic [9:0] draw_addr;
    logic [31:0] amp_out;
    logic [10:0] hcount;
    logic [9:0] vcount;
    logic       vsync;
    logic       hsync;
    logic       blanking;
    logic [11:0] rgb;
    
    always_ff @(posedge clk_100mhz)begin
        if (fft_out_valid) begin
            if (fft_out_last) begin
                write_addr2 <= 'd1023;
            end else begin
                write_addr2 <= write_addr2 + 1'b1;
            end
        end
        if (sqrt_valid)begin
            if (sqrt_last)begin
                addr_count <= 'd1023; 
            end else begin
                addr_count <= addr_count + 1'b1;
            end
        end
        if (inv_fft_out_valid)begin
            if (inv_fft_out_last)begin
                write_addr4 <= 'd1023;
            end else begin
                write_addr4 <= write_addr4 + 1'b1;
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
    value_bram mvb (.addra(addr_count+3), .clka(clk_100mhz), .dina({16'b0,sqrt_data[BIT_DEPTH-1:0]}),
                    .douta(), .ena(1'b1), .wea(sqrt_valid),.dinb(0),
                    .addrb(draw_addr), .clkb(pixel_clk), .doutb(amp_out),
                    .web(1'b0), .enb(1'b1));     
                    
                    
    //draw bargraphs from amp_out extracted (scale with switches)                
    always_ff @(posedge pixel_clk)begin
//        if (!blanking)begin //time to draw!
//            rgb <= 12'b0011_0000_0000;
//        end
        draw_addr <= hcount/2;
        if ((amp_out>>sw[5:2])>=768-vcount)begin
            rgb <= sw[15:4];
        end else begin
            rgb <= 12'b0000_0000_0000;
        end

    end                     
    xvga myyvga (.vclock_in(pixel_clk),.hcount_out(hcount),  
                .vcount_out(vcount),.vsync_out(vsync), .hsync_out(hsync),
                 .blank_out(blanking));               
                        
    assign vga_r = ~blanking ? rgb[11:8]: 0;
    assign vga_g = ~blanking ? rgb[7:4] : 0;
    assign vga_b = ~blanking ? rgb[3:0] : 0;
    
    assign vga_hs = ~hsync;
    assign vga_vs = ~vsync;

    assign aud_pwm = pwm_val?1'bZ:1'b0; 
    
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

module xvga(input vclock_in,
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
