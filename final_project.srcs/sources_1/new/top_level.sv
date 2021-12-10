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
    
    logic rst_in;
    assign rst_in = btnd;
    assign aud_sd = 1;
    assign led = sw; //just to look pretty
    
    typedef enum {READ_WAIT_INIT_1, READ_WAIT_INIT_2, ACTION_TO_SLAVE, WAITING_FOR_SLAVE, DONE} MemState;
    parameter FFT_REAL_BIT_WIDTH = 16;
    parameter INPUT_WINDOW_SIZE = 512;
    parameter WINDOW_NUM = 4;
    parameter FFT_DEPTH = INPUT_WINDOW_SIZE*WINDOW_NUM;
    parameter ADDRESS_BIT_WIDTH = $clog2(FFT_DEPTH);

    // Pixel Clock @ 65MHz
    logic pixel_clk;
    vga_clk myvga (.clk_in1(clk_100mhz), .clk_out1(pixel_clk));


    /* 100MHz to 48kHz Downsampling */
    parameter SAMPLE_COUNT = 2082;
    logic [15:0] sample_counter;
    logic sample_trigger;
    assign sample_trigger = (sample_counter == SAMPLE_COUNT);

    always_ff @(posedge clk_100mhz) begin
        if (sample_counter == SAMPLE_COUNT) sample_counter <= 16'b0;
        else sample_counter <= sample_counter + 16'b1;
    end
    

    /* 48kHz ADC signal */
    logic [11:0] adc_data;
    logic adc_ready;
    logic [FFT_REAL_BIT_WIDTH-1:0] scaled_adc_data;
    logic [FFT_REAL_BIT_WIDTH-1:0] scaled_signed_adc_data;

    always_ff @( posedge clk_100mhz ) begin
        if (sample_trigger) begin 
            scaled_adc_data <= 16*adc_data; // 12 to 16 bit width ADC signal
            scaled_signed_adc_data <= {~scaled_adc_data[15],scaled_adc_data[14:0]}; //convert to signed. incoming data is offset binary
        end
    end

    xadc_wiz_0 my_adc ( .dclk_in(clk_100mhz), .daddr_in(8'h13), //read from 0x13 for a
                        .vauxn3(vauxn3),.vauxp3(vauxp3),
                        .vp_in(1),.vn_in(1),
                        .di_in(16'b0),
                        .do_out(adc_data),.drdy_out(adc_ready),
                        .den_in(1), .dwe_in(0));


    /* Pre-Processing ADC Input (Downsampling to 8kHz + Anti-Aliasing Filter) */
    logic recorder_valid_out, recorder_last_out;
    logic [FFT_REAL_BIT_WIDTH-1:0] recorder_data;
 
    recorder myrec( .clk_in(clk_100mhz),.rst_in(rst_in),
                    .ready_in(sample_trigger),.filter_in(sw[11]),
                    .mic_in(scaled_signed_adc_data),
                    .write_addr(input_aud_bram_addr_in),
                    .recorder_last(recorder_last_out),
                    .recorder_valid(recorder_valid_out),
                    .data_out(recorder_data)); 

    // 16 bit Input Audio BRAM
    logic [FFT_REAL_BIT_WIDTH-1:0] input_aud_bram_data_in;
    logic [FFT_REAL_BIT_WIDTH-1:0] input_aud_bram_data_out;
    logic [ADDRESS_BIT_WIDTH-1:0] input_aud_bram_addr_in, input_aud_bram_addr_out;
    assign input_aud_bram_data_in = recorder_data;

    //BRAM Generator (v. 8.4)
    //BASIC:
    //Interface Type: Native
    //Memory Type: Simple Dual Port RAM
    //leave ECC as is
    //leave Write enable as is (unchecked Byte Write Enabe)
    //Algorithm Options: Minimum Area (not too important anyways)
    //PORT A OPTIONS:
    //Write Width: 16
    //Read Width: 16
    //Write Depth: 2048
    //Read Depth: 2048
    //Operating Mode; Write First (not too important here)
    //Enable Port Type: Always Enabled
    //Keep Primitives Output Register checked
    //leave other stuff unchecked
    //PORT B OPTIONS:
    //Should mimic Port A (and should auto-inheret most anyways)
    bram_16bit input_audio_bram (
        .clka(clk_100mhz),    // input wire clka
        .wea(1),      // input wire [0 : 0] wea <-- PORT A ONLY FOR WRITING
        .addra(input_aud_bram_addr_in),  // input wire [10 : 0] addra
        .dina(input_aud_bram_data_in),    // input wire [11 : 0] dina
        .clkb(clk_100mhz),    // input wire clkb
        .addrb(input_aud_bram_addr_out),  // input wire [10 : 0] addrb
        .doutb(input_aud_bram_data_out)  // output wire [11 : 0] doutb
    ); 


    /* Forward FFT */
    MemState input_aud_bram_state;
    logic [ADDRESS_BIT_WIDTH-1:0] input_aud_bram_data_counter;
    logic input_aud_bram_valid_out, input_aud_bram_last_out;

    always_ff @( posedge clk_100mhz ) begin 
        if (rst_in) begin
            input_aud_bram_addr_out <= {ADDRESS_BIT_WIDTH{1'b0}};
        end else if (recorder_last_out && recorder_valid_out) begin
            input_aud_bram_data_counter <= {ADDRESS_BIT_WIDTH{1'b0}};
            input_aud_bram_state <= READ_WAIT_INIT_1;
            input_aud_bram_last_out <= 1'b0;
            input_aud_bram_valid_out <= 1'b0;
        end else begin
            case (input_aud_bram_state) 
                READ_WAIT_INIT_1: begin
                    input_aud_bram_state <= READ_WAIT_INIT_2;
                end
                READ_WAIT_INIT_2: begin
                    input_aud_bram_state <= ACTION_TO_SLAVE;
                    input_aud_bram_data_counter <= input_aud_bram_data_counter + 1'b1;
                    input_aud_bram_addr_out <= input_aud_bram_addr_out + 'b1;
                end
                ACTION_TO_SLAVE: begin
                    input_aud_bram_valid_out <= 1'b1;
                    if (input_aud_bram_data_counter == 0) begin
                        input_aud_bram_last_out <= 1'b1;
                        input_aud_bram_state <= DONE;
                    end else begin 
                        input_aud_bram_state <= WAITING_FOR_SLAVE;
                    end
                end
                WAITING_FOR_SLAVE: begin
                    if (fwd_fft_ready_in == 1'b1) begin
                        input_aud_bram_valid_out <= 1'b0;
                        input_aud_bram_last_out <= 1'b0;
                        if (input_aud_bram_data_counter == FFT_DEPTH-1) begin 
                            input_aud_bram_addr_out <= input_aud_bram_addr_out + INPUT_WINDOW_SIZE - 1;
                            input_aud_bram_data_counter <= {ADDRESS_BIT_WIDTH{1'b0}}; 
                        end else begin  
                            input_aud_bram_addr_out <= input_aud_bram_addr_out + 1'b1;
                            input_aud_bram_data_counter <= input_aud_bram_data_counter + 'b1;   
                        end
                        input_aud_bram_state <= ACTION_TO_SLAVE;
                    end else begin
                        input_aud_bram_state <= WAITING_FOR_SLAVE;
                    end  
                end
                DONE: begin
                    input_aud_bram_state <= DONE;
                    input_aud_bram_last_out <= 1'b0;
                    input_aud_bram_valid_out <= 1'b0;
                end
                default: input_aud_bram_state <= READ_WAIT_INIT_1;
            endcase
        end
    end

    // Hann Window to improve FFT precision (smooth out windows at ends)
    logic [ADDRESS_BIT_WIDTH-1:0] hann_addr;
    logic [10:0] hann_coeff;
    logic [11+FFT_REAL_BIT_WIDTH-1:0] hann_data_product;
    assign hann_data_product = hann_coeff * input_aud_bram_data_out;
    assign hann_addr = input_aud_bram_data_counter;

    hann_rom hann_coeff_rom (   .clka(clk_100mhz),    // input wire clka
                                .addra(hann_addr),  // input wire [9 : 0] addra
                                .douta(hann_coeff)  // output wire [10 : 0] douta
    );

    // Forward FFT
    logic fwd_fft_ready_in;
    logic fwd_fft_valid_out, fwd_fft_last_out;
    logic [2*FFT_REAL_BIT_WIDTH-1:0] fwd_fft_data_out;
    
    //FFT module:
    //CONFIGURATION:
    //1 channel
    //transform length: 2048
    //target clock frequency: 100 MHz
    //target Data throughput: 50 Msps
    //Auto-select architecture
    //IMPLEMENTATION:
    //Fixed Point, Scaled, Truncation
    //MAKE SURE TO SET NATURAL ORDER FOR OUTPUT ORDERING
    //Input Data Width, Phase Factor Width: Both 16 bits
    xfft_0 fwd_fft (.aclk(clk_100mhz), .s_axis_data_tdata(sw[10] ? {1'b0,hann_data_product[11+FFT_REAL_BIT_WIDTH-1:11+1]} : input_aud_bram_data_out), 
                    .s_axis_data_tvalid(input_aud_bram_valid_out),
                    .s_axis_data_tlast(input_aud_bram_last_out), .s_axis_data_tready(fwd_fft_ready_in),
                    .s_axis_config_tdata(0), 
                     .s_axis_config_tvalid(0),
                     .s_axis_config_tready(),
                    .m_axis_data_tdata(fwd_fft_data_out), .m_axis_data_tvalid(fwd_fft_valid_out),
                    .m_axis_data_tlast(fwd_fft_last_out), .m_axis_data_tready(sqsum_ready_in));


    /* Branch to Raw FFT Visualizer Display */
    logic sqsum_ready_in;
    logic sqsum_valid_out, sqsum_last_out;
    logic [2*FFT_REAL_BIT_WIDTH-1:0] sqsum_data_out;

    square_and_sum_v1_0 mysq(.s00_axis_aclk(clk_100mhz), .s00_axis_aresetn(1'b1),
                            .s00_axis_tready(sqsum_ready_in),
                            .s00_axis_tdata(fwd_fft_data_out),.s00_axis_tlast(fwd_fft_last_out),
                            .s00_axis_tvalid(fwd_fft_valid_out),.m00_axis_aclk(clk_100mhz),
                            .m00_axis_aresetn(1'b1),. m00_axis_tvalid(sqsum_valid_out),
                            .m00_axis_tdata(sqsum_data_out),.m00_axis_tlast(sqsum_last_out),
                            .m00_axis_tready(fifo_ready_in));

    logic fifo_ready_in;
    logic fifo_valid_out, fifo_last_out;
    logic [2*FFT_REAL_BIT_WIDTH-1:0] fifo_data_out;

    //This is an AXI4-Stream Data FIFO
    //FIFO Depth: 2048
    //No packet mode, no async clock, 2 sycn stages for clock domain crossing
    //no aclken conversion
    //TDATA Width: 4 bytes
    //Enable TSTRB: No...isn't needed
    //Enable TKEEP: No...isn't needed
    //Enable TLAST: Yes...use this for frame alignment
    //TID Width, TDEST Width, and TUSER width: all 0
    axis_data_fifo_0 myfifo (.s_axis_aclk(clk_100mhz), .s_axis_aresetn(1'b1),
                             .s_axis_tvalid(sqsum_valid_out), .s_axis_tready(fifo_ready_in),
                             .s_axis_tdata(sqsum_data_out), .s_axis_tlast(sqsum_last_out),
                             .m_axis_tvalid(fifo_valid_out), .m_axis_tdata(fifo_data_out),
                             .m_axis_tready(sqrt_ready_in), .m_axis_tlast(fifo_last_out));

    logic sqrt_ready_in;
    logic sqrt_valid_out, sqrt_last_out;
    logic [23:0] sqrt_data_out;
    
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
    //Don't need a TUSER
    //Flow Control: Blocking
    //optimize Goal: Performance
    //leave other things unchecked.
    cordic_0 mysqrt (.aclk(clk_100mhz), .s_axis_cartesian_tdata(fifo_data_out),
                     .s_axis_cartesian_tvalid(fifo_valid_out), .s_axis_cartesian_tlast(fifo_last_out),
                     .s_axis_cartesian_tready(sqrt_ready_in),.m_axis_dout_tdata(sqrt_data_out),
                     .m_axis_dout_tvalid(sqrt_valid_out), .m_axis_dout_tlast(sqrt_last_out));
    

    /* Branch to HPS Frequency Detection */
    localparam HPS_NUMBER_OF_TERMS = 3;
    localparam HPS_ADDRESS_MAX = FFT_DEPTH/2/HPS_NUMBER_OF_TERMS-1;
    
    logic [ADDRESS_BIT_WIDTH-1:0] fftk_addr;
    logic [2*FFT_REAL_BIT_WIDTH-1:0] fftk_ampl;
    logic [2*FFT_REAL_BIT_WIDTH-1:0] fft2k_ampl;
    logic [2*FFT_REAL_BIT_WIDTH-1:0] fft3k_ampl;    

    //BRAM Generator (v. 8.4)
    //BASIC:
    //Interface Type: Native
    //Memory Type: Simple Dual Port RAM
    //leave ECC as is
    //leave Write enable as is (unchecked Byte Write Enabe)
    //Algorithm Options: Minimum Area (not too important anyways)
    //PORT A OPTIONS:
    //Write Width: 32
    //Read Width: 32
    //Write Depth: 2048
    //Read Depth: 2048
    //Operating Mode; Write First (not too important here)
    //Enable Port Type: Always Enabled
    //Keep Primitives Output Register checked
    //leave other stuff unchecked
    //PORT B OPTIONS:
    //Should mimic Port A (and should auto-inheret most anyways)
    bram_32bit fftk (
        .clka(clk_100mhz),    // input wire clka
        .wea(sqrt_valid_out),      // input wire [0 : 0] wea <-- PORT A ONLY FOR WRITING
        .addra(addr_count),  // input wire [10 : 0] addra
        .dina({8'b0,sqrt_data_out}),    // input wire [11 : 0] dina
        .clkb(pixel_clk),    // input wire clkb
        .addrb(fftk_addr),  // input wire [10 : 0] addrb
        .doutb(fftk_ampl)  // output wire [11 : 0] doutb
    );

    bram_32bit fft2k (
        .clka(clk_100mhz),    // input wire clka
        .wea(sqrt_valid_out),      // input wire [0 : 0] wea <-- PORT A ONLY FOR WRITING
        .addra(addr_count),  // input wire [10 : 0] addra
        .dina({8'b0,sqrt_data_out}),    // input wire [11 : 0] dina
        .clkb(pixel_clk),    // input wire clkb
        .addrb(fftk_addr*2),  // input wire [10 : 0] addrb
        .doutb(fft2k_ampl)  // output wire [11 : 0] doutb
    );

    bram_32bit fft3k (
        .clka(clk_100mhz),    // input wire clka
        .wea(sqrt_valid_out),      // input wire [0 : 0] wea <-- PORT A ONLY FOR WRITING
        .addra(addr_count),  // input wire [10 : 0] addra
        .dina({8'b0,sqrt_data_out}),    // input wire [11 : 0] dina
        .clkb(pixel_clk),    // input wire clkb
        .addrb(fftk_addr*3),  // input wire [10 : 0] addrb
        .doutb(fft3k_ampl)  // output wire [11 : 0] doutb
    );    
    
    logic [2*FFT_REAL_BIT_WIDTH*HPS_NUMBER_OF_TERMS-1:0] hps_s_data;
    logic hps_s_ready;
    logic hps_s_last, hps_s_valid;
    logic hps_m_valid;
    logic [ADDRESS_BIT_WIDTH-1:0] hps_m_data;
    
    freq_detect_v3_0 #(.FFT_WINDOW_SIZE(FFT_DEPTH), .FFT_SAMPLE_SIZE(2*FFT_REAL_BIT_WIDTH)) 
        my_freq_detect(.clk(pixel_clk), .resetn(1'b1),
                            .s00_axis_tready(hps_s_ready),
                            .s00_axis_tdata(hps_s_data),.s00_axis_tlast(hps_s_last),
                            .s00_axis_tvalid(hps_s_valid),
                            .m00_axis_tvalid(hps_m_valid),
                            .m00_axis_tdata(hps_m_data),
                            .m00_axis_tready());
                            
    MemState hps_mem_state;
    logic [ADDRESS_BIT_WIDTH-1:0] nat_freq;
    
    always_ff @(posedge pixel_clk) begin
        if (rst_in == 1'b1) begin
            nat_freq <= {ADDRESS_BIT_WIDTH{1'b0}};
            hps_mem_state <= DONE;
            hps_s_last <= 1'b0;
            hps_s_valid <= 1'b0; 
        end else if (sqrt_last_out && sqrt_valid_out) begin // kinda reset
            fftk_addr <= {ADDRESS_BIT_WIDTH{1'b0}};
            hps_mem_state <= READ_WAIT_INIT_1;
            hps_s_data <= {2*FFT_REAL_BIT_WIDTH*HPS_NUMBER_OF_TERMS{1'b0}};
            hps_s_last <= 1'b0;
            hps_s_valid <= 1'b0;
        end else begin
            case (hps_mem_state) 
                READ_WAIT_INIT_1: begin
                    hps_mem_state <= READ_WAIT_INIT_2;
                end
                READ_WAIT_INIT_2: begin
                    hps_mem_state <= ACTION_TO_SLAVE;
                    fftk_addr <= fftk_addr + 'b1;
                end
                ACTION_TO_SLAVE: begin
                    if (fftk_addr == 1) hps_s_data <= {2*FFT_REAL_BIT_WIDTH*HPS_NUMBER_OF_TERMS{1'b0}};
                    else hps_s_data <= {fftk_ampl, fft2k_ampl, fft3k_ampl}; // TODO: change back after testing
                    hps_s_valid <= 1'b1;
                    if (fftk_addr == 0) begin
                        hps_s_last <=1'b1;
                        hps_mem_state <= DONE;
                    end else begin
                        hps_mem_state <= WAITING_FOR_SLAVE;
                    end
               end
                WAITING_FOR_SLAVE: begin
                    if (hps_s_ready == 1'b1) begin
                        hps_s_valid <= 1'b0;
                        hps_s_last <= 1'b0;
                        if (fftk_addr == HPS_ADDRESS_MAX) begin
                            fftk_addr <={ADDRESS_BIT_WIDTH{1'b0}};
                        end else begin
                            fftk_addr <= fftk_addr + 'b1;
                        end
                        hps_mem_state <= ACTION_TO_SLAVE;
                    end else begin
                        hps_mem_state <= WAITING_FOR_SLAVE;
                    end      
                end
                DONE: begin
                    hps_mem_state <= DONE;
                    hps_s_last <=1'b0;
                    hps_s_valid <= 1'b0;
                end
                default: hps_mem_state <= READ_WAIT_INIT_1;
            endcase 
            if (hps_m_valid == 1'b1) begin
                nat_freq <= hps_m_data;
            end
        end
    end
    /* Branch HPS Frequency Detection Code Above */

    logic [ADDRESS_BIT_WIDTH-1:0] addr_count;
    logic [ADDRESS_BIT_WIDTH-1:0] draw_addr;
    logic [2*FFT_REAL_BIT_WIDTH-1:0] raw_amp_out;

    always_ff @( posedge clk_100mhz ) begin 
        if (rst_in) addr_count <= 0;
        else if (sqrt_valid_out) addr_count <= sqrt_last_out ? 'd0 : addr_count + 1;
    end

    bram_32bit mvb_raw (
        .clka(clk_100mhz),    // input wire clka
        .wea(sqrt_valid_out),      // input wire [0 : 0] wea <-- PORT A ONLY FOR WRITING
        .addra(addr_count),  // input wire [10 : 0] addra
        .dina({8'b0,sqrt_data_out}),    // input wire [11 : 0] dina
        .clkb(pixel_clk),    // input wire clkb
        .addrb(draw_addr),  // input wire [10 : 0] addrb
        .doutb(raw_amp_out)  // output wire [11 : 0] doutb
    ); 
    /* Branch Raw FFT Visualizer Display Code Above */

    always_ff @(posedge clk_100mhz)begin
        if (rst_in) begin
            fwd_fft_bram_addr_in <= 0;
        end else if (fwd_fft_valid_out) begin
            fwd_fft_bram_addr_in <= fwd_fft_last_out ? FFT_DEPTH-1 : fwd_fft_bram_addr_in + 1'b1;
            fwd_fft_bram_data_in <= fwd_fft_data_out;
        end
    end

    // 16 bit Forward FFT BRAM (for frequency shifting)
    logic [2*FFT_REAL_BIT_WIDTH-1:0] fwd_fft_bram_data_in;
    logic [2*FFT_REAL_BIT_WIDTH-1:0] fwd_fft_bram_data_out;
    logic [ADDRESS_BIT_WIDTH-1:0] fwd_fft_bram_addr_in, fwd_fft_bram_addr_out;
    
    bram_32bit fwd_fft_bram (
        .clka(clk_100mhz),    // input wire clka
        .wea(1),      // input wire [0 : 0] wea <-- PORT A ONLY FOR WRITING
        .addra(fwd_fft_bram_addr_in),  // input wire [10 : 0] addra
        .dina(fwd_fft_bram_data_in),    // input wire [11 : 0] dina
        .clkb(clk_100mhz),    // input wire clkb
        .addrb(fwd_fft_bram_addr_out),  // input wire [10 : 0] addrb
        .doutb(fwd_fft_bram_data_out)  // output wire [11 : 0] doutb
    ); 


    /* Frequency Shifting */
    logic [ADDRESS_BIT_WIDTH*2-1:0] coeff_increase;
    logic [ADDRESS_BIT_WIDTH*2-1:0] coeff_decrease;
    always_comb begin
        case(sw[9:6]) 
            'd0: begin
                // coeff_increase = 1/1.7
                coeff_increase[ADDRESS_BIT_WIDTH*2-1:ADDRESS_BIT_WIDTH] = 'd0;
                coeff_increase[ADDRESS_BIT_WIDTH-1:0] = FFT_DEPTH/1.7;
                coeff_decrease[ADDRESS_BIT_WIDTH*2-1:ADDRESS_BIT_WIDTH] = 'd1;
                coeff_decrease[ADDRESS_BIT_WIDTH-1:0] = FFT_DEPTH*0.7;
            end
            
            'd1: begin
                // coeff_increase = 1/1.5
                coeff_increase[ADDRESS_BIT_WIDTH*2-1:ADDRESS_BIT_WIDTH] = 'd0;
                coeff_increase[ADDRESS_BIT_WIDTH-1:0] = FFT_DEPTH/1.5;
                coeff_decrease[ADDRESS_BIT_WIDTH*2-1:ADDRESS_BIT_WIDTH] = 'd1;
                coeff_decrease[ADDRESS_BIT_WIDTH-1:0] = FFT_DEPTH*0.5;
            end
            
            'd2: begin
                // coeff_increase = 1/1.2
                coeff_increase[ADDRESS_BIT_WIDTH*2-1:ADDRESS_BIT_WIDTH] = 'd0;
                coeff_increase[ADDRESS_BIT_WIDTH-1:0] = FFT_DEPTH/1.2;
                coeff_decrease[ADDRESS_BIT_WIDTH*2-1:ADDRESS_BIT_WIDTH] = 'd1;
                coeff_decrease[ADDRESS_BIT_WIDTH-1:0] = FFT_DEPTH*0.2;
            end
            
            'd3: begin
                // coeff_increase = 1/1
                coeff_increase[ADDRESS_BIT_WIDTH*2-1:ADDRESS_BIT_WIDTH] = 'd1;
                coeff_increase[ADDRESS_BIT_WIDTH-1:0] = 0;
                coeff_decrease[ADDRESS_BIT_WIDTH*2-1:ADDRESS_BIT_WIDTH] = 'd1;
                coeff_decrease[ADDRESS_BIT_WIDTH-1:0] = 0;
            end
            
            'd4: begin
                // coeff_increase = 1.2
                coeff_increase[ADDRESS_BIT_WIDTH*2-1:ADDRESS_BIT_WIDTH] = 'd1;
                coeff_increase[ADDRESS_BIT_WIDTH-1:0] = FFT_DEPTH*0.2;
                coeff_decrease[ADDRESS_BIT_WIDTH*2-1:ADDRESS_BIT_WIDTH] = 'd0;
                coeff_decrease[ADDRESS_BIT_WIDTH-1:0] = FFT_DEPTH/1.2;
            end
            
            'd5: begin
                // coeff_increase = 1.5
                coeff_increase[ADDRESS_BIT_WIDTH*2-1:ADDRESS_BIT_WIDTH] = 'd1;
                coeff_increase[ADDRESS_BIT_WIDTH-1:0] = FFT_DEPTH*0.5;
                coeff_decrease[ADDRESS_BIT_WIDTH*2-1:ADDRESS_BIT_WIDTH] = 'd0;
                coeff_decrease[ADDRESS_BIT_WIDTH-1:0] = FFT_DEPTH/1.5;
            end
            
            'd6: begin
                // coeff_increase = 2
                coeff_increase[ADDRESS_BIT_WIDTH*2-1:ADDRESS_BIT_WIDTH] = 'd2;
                coeff_increase[ADDRESS_BIT_WIDTH-1:0] = FFT_DEPTH*0;
                coeff_decrease[ADDRESS_BIT_WIDTH*2-1:ADDRESS_BIT_WIDTH] = 'd0;
                coeff_decrease[ADDRESS_BIT_WIDTH-1:0] = FFT_DEPTH/2;
            end
            
            default: begin
                // coeff_increase = 1/1
                coeff_increase[ADDRESS_BIT_WIDTH*2-1:ADDRESS_BIT_WIDTH] = 'd1;
                coeff_increase[ADDRESS_BIT_WIDTH-1:0] = 0;
                coeff_decrease[ADDRESS_BIT_WIDTH*2-1:ADDRESS_BIT_WIDTH] = 'd1;
                coeff_decrease[ADDRESS_BIT_WIDTH-1:0] = 0;
            end
        endcase
    end
    logic write_en, shift_done;
       
    freq_shift #(.FFT_WINDOW_SIZE(FFT_DEPTH), .FFT_SAMPLE_SIZE(2*FFT_REAL_BIT_WIDTH)) 
        my_freq_shift(.clk_in(clk_100mhz), .reset_in(rst_in),
                      .trigger_in(fwd_fft_last_out & fwd_fft_valid_out), .coeff_increase_in(coeff_increase), .coeff_decrease_in(coeff_decrease),
                      .read_data_in(fwd_fft_bram_data_out), .read_addr_out(fwd_fft_bram_addr_out),
                      .write_data_out(shifted_fft_bram_data_in), .write_addr_out(shifted_fft_bram_addr_in), .write_en_out(write_en),
                      .shift_done_out(shift_done)
                      );

    // Shifted FFT BRAM
    logic [2*FFT_REAL_BIT_WIDTH-1:0] shifted_fft_bram_data_in;
    logic [2*FFT_REAL_BIT_WIDTH-1:0] shifted_fft_bram_data_out;
    logic [ADDRESS_BIT_WIDTH-1:0] shifted_fft_bram_addr_in, shifted_fft_bram_addr_out;
    
    bram_32bit shifted_fft_bram (
        .clka(clk_100mhz),    // input wire clka
        .wea(write_en),      // input wire [0 : 0] wea <-- PORT A ONLY FOR WRITING
        .addra(shifted_fft_bram_addr_in),  // input wire [10 : 0] addra
        .dina(shifted_fft_bram_data_in),    // input wire [11 : 0] dina
        .clkb(clk_100mhz),    // input wire clkb
        .addrb(shifted_fft_bram_addr_out),  // input wire [10 : 0] addrb
        .doutb(shifted_fft_bram_data_out)  // output wire [11 : 0] doutb
    );


    /* Branch to Shifted FFT Visualizer Display */   
    logic [2*FFT_REAL_BIT_WIDTH-1:0] viz_shifted_fft_bram_data_in;
    logic [2*FFT_REAL_BIT_WIDTH-1:0] viz_shifted_fft_bram_data_out;
    logic [ADDRESS_BIT_WIDTH-1:0] viz_shifted_fft_bram_addr_in;
    logic [ADDRESS_BIT_WIDTH-1:0] viz_shifted_fft_bram_addr_out;
    
    assign viz_shifted_fft_bram_data_in = shifted_fft_bram_data_in;
    assign viz_shifted_fft_bram_addr_in = shifted_fft_bram_addr_in;
    
    bram_32bit viz_shifted_fft_bram (
        .clka(clk_100mhz),    // input wire clka
        .wea(write_en),      // input wire [0 : 0] wea <-- PORT A ONLY FOR WRITING
        .addra(viz_shifted_fft_bram_addr_in),  // input wire [10 : 0] addra
        .dina(viz_shifted_fft_bram_data_in),    // input wire [11 : 0] dina
        .clkb(clk_100mhz),    // input wire clkb
        .addrb(viz_shifted_fft_bram_addr_out),  // input wire [10 : 0] addrb
        .doutb(viz_shifted_fft_bram_data_out)  // output wire [11 : 0] doutb
    );
    
    MemState viz_shifted_fft_bram_state;
    logic [2*FFT_REAL_BIT_WIDTH-1:0] viz_shifted_sqsum_data_in;
    logic viz_shifted_fft_bram_last_out, viz_shifted_fft_bram_valid_out;              
    
    always_ff @(posedge clk_100mhz) begin
        if (shift_done) begin
            viz_shifted_fft_bram_addr_out <= {ADDRESS_BIT_WIDTH{1'b0}};
            viz_shifted_fft_bram_state <= READ_WAIT_INIT_1;
            viz_shifted_sqsum_data_in <= {2*FFT_REAL_BIT_WIDTH{1'b0}};
            viz_shifted_fft_bram_last_out <= 1'b0;
            viz_shifted_fft_bram_valid_out <= 1'b0;
        end else begin
            case (viz_shifted_fft_bram_state) 
                READ_WAIT_INIT_1: begin
                        viz_shifted_fft_bram_state <= READ_WAIT_INIT_2;
                end
                READ_WAIT_INIT_2: begin
                        viz_shifted_fft_bram_state <= ACTION_TO_SLAVE;
                        viz_shifted_fft_bram_addr_out <= viz_shifted_fft_bram_addr_out + 'b1;
                end
                ACTION_TO_SLAVE: begin
                    viz_shifted_sqsum_data_in <= viz_shifted_fft_bram_data_out;
                    viz_shifted_fft_bram_valid_out <= 1'b1;
                    if (viz_shifted_fft_bram_addr_out == 0) begin
                        viz_shifted_fft_bram_last_out <=1'b1;
                        viz_shifted_fft_bram_state <= DONE;
                    end else begin
                        viz_shifted_fft_bram_state <= WAITING_FOR_SLAVE;
                    end
                end
                WAITING_FOR_SLAVE: begin
                    if (viz_shifted_sqsum_ready_in == 1'b1) begin
                        viz_shifted_fft_bram_valid_out <= 1'b0;
                        if (viz_shifted_fft_bram_addr_out == FFT_DEPTH-1) begin
                            viz_shifted_fft_bram_addr_out <={ADDRESS_BIT_WIDTH{1'b0}};
                        end else begin
                            viz_shifted_fft_bram_addr_out <= viz_shifted_fft_bram_addr_out + 'b1;
                        end
                        viz_shifted_fft_bram_state <= ACTION_TO_SLAVE;
                    end else begin
                        viz_shifted_fft_bram_state <= WAITING_FOR_SLAVE;
                    end      
                end
                DONE: begin
                    viz_shifted_fft_bram_state <= DONE;
                    viz_shifted_fft_bram_last_out <=1'b0;
                    viz_shifted_fft_bram_valid_out <= 1'b0;
                end
                default: viz_shifted_fft_bram_state <= READ_WAIT_INIT_1;
            endcase 
        end
    end   

    logic viz_shifted_sqsum_ready_in;
    logic viz_shifted_sqsum_valid_out, viz_shifted_sqsum_last_out;
    logic [2*FFT_REAL_BIT_WIDTH-1:0] viz_shifted_sqsum_data_out;
                
    square_and_sum_v1_0 sq_shifted(.s00_axis_aclk(clk_100mhz), .s00_axis_aresetn(1'b1),
                            .s00_axis_tready(viz_shifted_sqsum_ready_in),
                            .s00_axis_tdata(viz_shifted_sqsum_data_in),.s00_axis_tlast(viz_shifted_fft_bram_last_out),
                            .s00_axis_tvalid(viz_shifted_fft_bram_valid_out),.m00_axis_aclk(clk_100mhz),
                            .m00_axis_aresetn(1'b1),. m00_axis_tvalid(viz_shifted_sqsum_valid_out),
                            .m00_axis_tdata(viz_shifted_sqsum_data_out),.m00_axis_tlast(viz_shifted_sqsum_last_out),
                            .m00_axis_tready(viz_shifted_fifo_ready_in));
       
    logic viz_shifted_fifo_ready_in;
    logic viz_shifted_fifo_valid_out, viz_shifted_fifo_last_out;
    logic [2*FFT_REAL_BIT_WIDTH-1:0] viz_shifted_fifo_data_out;
    
    axis_data_fifo_0 fifo_shifted (.s_axis_aclk(clk_100mhz), .s_axis_aresetn(1'b1),
                             .s_axis_tvalid(viz_shifted_sqsum_valid_out), .s_axis_tready(viz_shifted_fifo_ready_in),
                             .s_axis_tdata(viz_shifted_sqsum_data_out), .s_axis_tlast(viz_shifted_sqsum_last_out),
                             .m_axis_tvalid(viz_shifted_fifo_valid_out), .m_axis_tdata(viz_shifted_fifo_data_out),
                             .m_axis_tready(viz_shifted_sqrt_ready_in), .m_axis_tlast(viz_shifted_fifo_last_out));   
    
    logic viz_shifted_sqrt_ready_in;
    logic viz_shifted_sqrt_valid_out, viz_shifted_sqrt_last_out;
    logic [23:0] viz_shifted_sqrt_data_out;
    
    cordic_0 sqrt_shifted (.aclk(clk_100mhz), .s_axis_cartesian_tdata(viz_shifted_fifo_data_out),
                     .s_axis_cartesian_tvalid(viz_shifted_fifo_valid_out), .s_axis_cartesian_tlast(viz_shifted_fifo_last_out),
                     .s_axis_cartesian_tready(viz_shifted_sqrt_ready_in),.m_axis_dout_tdata(viz_shifted_sqrt_data_out),
                     .m_axis_dout_tvalid(viz_shifted_sqrt_valid_out), .m_axis_dout_tlast(viz_shifted_sqrt_last_out));

    logic [ADDRESS_BIT_WIDTH-1:0] shifted_addr_count;
    logic [ADDRESS_BIT_WIDTH-1:0] shifted_draw_addr;
    logic [2*FFT_REAL_BIT_WIDTH:0] shifted_amp_out;

    always_ff @(posedge clk_100mhz) begin
        if (rst_in) shifted_addr_count <= 0;
        else if (!rst_in && viz_shifted_sqrt_valid_out) shifted_addr_count <= viz_shifted_sqrt_last_out ? 'd0 : shifted_addr_count + 1;
    end

    bram_32bit mvb_shifted (
        .clka(clk_100mhz),    // input wire clka
        .wea(viz_shifted_sqrt_valid_out),      // input wire [0 : 0] wea <-- PORT A ONLY FOR WRITING
        .addra(shifted_addr_count),  // input wire [10 : 0] addra
        .dina({8'b0,viz_shifted_sqrt_data_out}),    // input wire [11 : 0] dina
        .clkb(pixel_clk),    // input wire clkb
        .addrb(shifted_draw_addr),  // input wire [10 : 0] addrb
        .doutb(shifted_amp_out)  // output wire [11 : 0] doutb
    );
    /* Branch Shifted FFT Visualizer Display Code Above*/


    /* Inverse FFT */
    MemState shifted_fft_bram_state;
    logic shifted_fft_bram_valid_out, shifted_fft_bram_last_out;

    always_ff @(posedge clk_100mhz) begin        
        if (shift_done) begin
            shifted_fft_bram_addr_out <= {ADDRESS_BIT_WIDTH{1'b0}};
            shifted_fft_bram_state <= READ_WAIT_INIT_1;
            shifted_fft_bram_last_out <= 1'b0;
            shifted_fft_bram_valid_out <= 1'b0;
        end else begin
            case (shifted_fft_bram_state) 
                READ_WAIT_INIT_1: begin
                    shifted_fft_bram_state <= READ_WAIT_INIT_2;
                end
                READ_WAIT_INIT_2: begin
                    shifted_fft_bram_state <= ACTION_TO_SLAVE;
                    shifted_fft_bram_addr_out <= shifted_fft_bram_addr_out + 'b1;
                end
                ACTION_TO_SLAVE: begin
                    shifted_fft_bram_valid_out <= 1'b1;
                    if (shifted_fft_bram_addr_out == 0) begin
                        shifted_fft_bram_last_out <= 1'b1;
                        shifted_fft_bram_state <= DONE;
                    end else begin 
                        shifted_fft_bram_state <= WAITING_FOR_SLAVE;
                    end
                end
                WAITING_FOR_SLAVE: begin
                    if (inv_fft_ready_in == 1'b1) begin
                        shifted_fft_bram_valid_out <= 1'b0;
                        shifted_fft_bram_last_out <= 1'b0;
                        if (shifted_fft_bram_addr_out == FFT_DEPTH-1) begin 
                            shifted_fft_bram_addr_out <={ADDRESS_BIT_WIDTH{1'b0}}; 
                        end else begin  
                            shifted_fft_bram_addr_out <= shifted_fft_bram_addr_out + 'b1;   
                        end
                        shifted_fft_bram_state <= ACTION_TO_SLAVE;
                    end else begin
                        shifted_fft_bram_state <= WAITING_FOR_SLAVE;
                    end
                end
                DONE: begin
                    shifted_fft_bram_state <= DONE;
                    shifted_fft_bram_last_out <= 1'b0;
                    shifted_fft_bram_valid_out <= 1'b0;
                end
                default: shifted_fft_bram_state <= READ_WAIT_INIT_1;
            endcase
        end
    end

    logic inv_fft_ready_in;
    logic inv_fft_valid_out, inv_fft_last_out;
    logic [2*FFT_REAL_BIT_WIDTH-1:0] inv_fft_data_out;

    xfft_0 inv_fft (.aclk(clk_100mhz), .s_axis_data_tdata(shifted_fft_bram_data_out), 
                    .s_axis_data_tvalid(shifted_fft_bram_valid_out),
                    .s_axis_data_tlast(shifted_fft_bram_last_out), .s_axis_data_tready(inv_fft_ready_in),
                    .s_axis_config_tdata(0), 
                    .s_axis_config_tvalid(1),
                    .s_axis_config_tready(),
                    .m_axis_data_tdata(inv_fft_data_out), .m_axis_data_tvalid(inv_fft_valid_out),
                    .m_axis_data_tlast(inv_fft_last_out), .m_axis_data_tready(1));
    
    // Inverse FFT BRAM
    logic [2*FFT_REAL_BIT_WIDTH-1:0] inv_fft_bram_data_in;
    logic [2*FFT_REAL_BIT_WIDTH-1:0] inv_fft_bram_data_out;
    logic [ADDRESS_BIT_WIDTH-1:0] inv_fft_bram_addr_in, inv_fft_bram_addr_out;

    bram_32bit inv_fft_bram (
        .clka(clk_100mhz),    // input wire clka
        .wea(1),      // input wire [0 : 0] wea <-- PORT A ONLY FOR WRITING
        .addra(inv_fft_bram_addr_in),  // input wire [10 : 0] addra
        .dina(inv_fft_bram_data_in),    // input wire [11 : 0] dina
        .clkb(clk_100mhz),    // input wire clkb
        .addrb(inv_fft_bram_addr_out),  // input wire [10 : 0] addrb
        .doutb(inv_fft_bram_data_out)  // output wire [11 : 0] doutb
    );

    always_ff @(posedge clk_100mhz)begin
        if (rst_in) begin
            inv_fft_bram_addr_in <= 0;
        end else if (inv_fft_valid_out) begin
            inv_fft_bram_addr_in <= inv_fft_last_out ? FFT_DEPTH-1 : inv_fft_bram_addr_in + 1'b1; 
            inv_fft_bram_data_in <= inv_fft_data_out;
            if (inv_fft_last_out) playback_start <= 1;
        end
        if (playback_start) playback_start <= !playback_start;
    end


    /* Post-Processing + Playback Shifted Audio Signal */
    logic playback_start;
    logic [FFT_REAL_BIT_WIDTH-1:0] playback_data;

    playback player(    .clk_in(clk_100mhz), .rst_in(rst_in),
                        .ready_in(sample_trigger),.filter_in(sw[12]),
                        .read_addr(inv_fft_bram_addr_out), 
                        .input_data(inv_fft_bram_data_out[FFT_REAL_BIT_WIDTH-1:0]),
                        .playback_start(playback_start),
                        .data_out(playback_data)); 

    logic [FFT_REAL_BIT_WIDTH-1:0] vol_out; 
                                                             
    volume_control vc (.vol_in(sw[15:13]),
                       .signal_in(playback_data[FFT_REAL_BIT_WIDTH-1:0]), .signal_out(vol_out));

    logic pwm_val; //pwm signal (HI/LO)

    pwm (.clk_in(clk_100mhz), .rst_in(rst_in), .level_in({~vol_out[11],vol_out[10:0]}), .pwm_out(pwm_val));
    assign aud_pwm = pwm_val?1'bZ:1'b0;
    

    /* Visualizer */
    logic [16:0] spectrogram_count;
    logic [16:0] spectrogram_draw_addr;
    logic spectrogram_wea;

    logic [15:0] spectrogram_raw_amp_in;
    logic [15:0] spectrogram_raw_amp_out;
    
    parameter SPECTROGRAM_TIME_RANGE = 256;
    parameter SPECTROGRAM_FREQUENCY_RANGE = 512;
    
    always_ff @(posedge clk_100mhz) begin
        if (rst_in) begin
            spectrogram_count <= 0;
            spectrogram_wea <= 0;
            spectrogram_raw_amp_in <= 0;
        end else if (!rst_in && sqrt_valid_out)begin
            spectrogram_wea <= addr_count < SPECTROGRAM_FREQUENCY_RANGE;
            if (!sqrt_last_out && addr_count < SPECTROGRAM_FREQUENCY_RANGE) begin
                spectrogram_raw_amp_in <= sqrt_data_out[23:8];
                spectrogram_count <= spectrogram_count + 1;
            end
        end
    end       
                    
    spectrogram_bram msb_raw (.addra(spectrogram_count), .clka(clk_100mhz), .dina(spectrogram_raw_amp_in),
                    .douta(), .ena(1'b1), .wea(spectrogram_wea),.dinb(0),
                    .addrb(spectrogram_draw_addr), .clkb(pixel_clk), .doutb(spectrogram_raw_amp_out),
                    .web(1'b0), .enb(1'b1));
                    
    visualizer #(   .ADDRESS_BIT_WIDTH(ADDRESS_BIT_WIDTH), 
                    .SPECTROGRAM_TIME_RANGE(SPECTROGRAM_TIME_RANGE),
                    .SPECTROGRAM_FREQUENCY_RANGE(SPECTROGRAM_FREQUENCY_RANGE))
        viz (.clk_in(pixel_clk), .rst_in(rst_in), 
                    .raw_amp_out(raw_amp_out), .shifted_amp_out(shifted_amp_out),  
                    .spectrogram_raw_amp_out(spectrogram_raw_amp_out), .nat_freq(nat_freq),
                    .amp_scale(sw[3:0]), .visualize_mode(sw[5:4]), .pwm_val(pwm_val), 
                    .draw_addr(draw_addr), .shifted_draw_addr(shifted_draw_addr), .spectrogram_draw_addr(spectrogram_draw_addr),
                    .vga_r(vga_r), .vga_b(vga_b), .vga_g(vga_g), .vga_hs(vga_hs), .vga_vs(vga_vs), 
                    .aud_pwm(aud_pwm));     
    
endmodule