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
    
    logic rst_in;
    assign rst_in = btnd;
    
    parameter BIT_DEPTH = 16;
    parameter INPUT_WINDOW_SIZE = 512;
    parameter WINDOW_NUM = 4;
    parameter NFFT_WINDOW_SIZE = INPUT_WINDOW_SIZE*WINDOW_NUM;
    parameter ADDRESS_BIT_WIDTH = $clog2(NFFT_WINDOW_SIZE);
    
    // Downsampling 
    parameter SAMPLE_COUNT = 2082;//gets approximately (will generate audio at approx 48 kHz sample rate.
    logic [15:0] sample_counter;
    logic sample_trigger;
    
    // ADC
    logic [11:0] adc_data;
    logic adc_ready;
    logic [BIT_DEPTH-1:0] scaled_adc_data;
    logic [BIT_DEPTH-1:0] scaled_signed_adc_data;
    
    logic recorder_valid_out, recorder_last_out;
    logic playback_start;
    logic [BIT_DEPTH-1:0] recorder_data, playback_data, vol_out; 
        
    logic pwm_val; //pwm signal (HI/LO)
    
    // Visualizer
    logic sqsum_valid, sqsum_last, sqsum_ready;
    logic [31:0] sqsum_data;
    
    logic fifo_valid, fifo_last, fifo_ready;
    logic [31:0] fifo_data;
    
    logic sqrt_valid, sqrt_last;
    logic [23:0] sqrt_data;
    
    assign aud_sd = 1;
    assign led = sw; //just to look pretty 
    assign sample_trigger = (sample_counter == SAMPLE_COUNT);
    
    // Forward FFT
    logic fft_ready, fft_valid, fft_last;
    logic [2*BIT_DEPTH-1:0] fft_data;
    logic [ADDRESS_BIT_WIDTH-1:0] fft_data_counter;
    logic fft_out_ready, fft_out_valid, fft_out_last;
    logic [2*BIT_DEPTH-1:0] fft_out_data;
    
    logic fft_ready1, fft_valid1, fft_last1;
    logic [15:0] fft_data1;
    logic [ADDRESS_BIT_WIDTH-1:0] fft_data_counter1;
    logic fft_out_ready1, fft_out_valid1, fft_out_last1;
    logic [15:0] fft_out_data1;
    
    // Inverse FFT
    logic inv_fft_valid, inv_fft_last, inv_fft_ready;
    logic [2*BIT_DEPTH-1:0] inv_fft_data;
    logic [ADDRESS_BIT_WIDTH-1:0] inv_fft_data_counter;
    logic inv_fft_out_valid, inv_fft_out_last;
    logic [2*BIT_DEPTH-1:0] inv_fft_out_data;
    
    // Hann Window
    logic [ADDRESS_BIT_WIDTH-1:0] hann_addr;
    logic [10:0] hann_coeff;
    logic [11+BIT_DEPTH-1:0] hann_data_product;
    assign hann_data_product = hann_coeff * data_from_input_aud_bram;
    
    logic pixel_clk;
    vga_clk myvga (.clk_in1(clk_100mhz), .clk_out1(pixel_clk));
    
    // Input Audio BRAM
    logic [BIT_DEPTH-1:0] data_to_input_aud_bram;
    logic [BIT_DEPTH-1:0] data_from_input_aud_bram;
    logic [ADDRESS_BIT_WIDTH-1:0] input_aud_bram_write_addr, input_aud_bram_read_addr;
    assign data_to_input_aud_bram = recorder_data;

    bram_16bit input_audio_bram (
        .clka(clk_100mhz),    // input wire clka
        .wea(1),      // input wire [0 : 0] wea <-- PORT A ONLY FOR WRITING
        .addra(input_aud_bram_write_addr),  // input wire [10 : 0] addra
        .dina(data_to_input_aud_bram),    // input wire [11 : 0] dina
        .clkb(clk_100mhz),    // input wire clkb
        .addrb(input_aud_bram_read_addr),  // input wire [10 : 0] addrb
        .doutb(data_from_input_aud_bram)  // output wire [11 : 0] doutb
    ); 
    
    logic [7:0] data_to_input_aud_bram1;
    logic [7:0] data_from_input_aud_bram1;
    logic [ADDRESS_BIT_WIDTH-1:0] input_aud_bram1_write_addr, input_aud_bram1_read_addr;
    assign input_aud_bram1_write_addr = input_aud_bram_write_addr;
    assign data_to_input_aud_bram1 = recorder_data[BIT_DEPTH-1: BIT_DEPTH-1-7];

    bram_8bit input_audio_bram1 (
        .clka(clk_100mhz),    // input wire clka
        .wea(1),      // input wire [0 : 0] wea <-- PORT A ONLY FOR WRITING
        .addra(input_aud_bram1_write_addr),  // input wire [10 : 0] addra
        .dina(data_to_input_aud_bram1),    // input wire [11 : 0] dina
        .clkb(clk_100mhz),    // input wire clkb
        .addrb(input_aud_bram1_read_addr),  // input wire [10 : 0] addrb
        .doutb(data_from_input_aud_bram1)  // output wire [11 : 0] doutb
    );  

    // Forward FFT BRAM
    logic [2*BIT_DEPTH-1:0] data_to_fwd_fft_bram;
    logic [2*BIT_DEPTH-1:0] data_from_fwd_fft_bram;
    logic [ADDRESS_BIT_WIDTH-1:0] fwd_fft_bram_write_addr, fwd_fft_bram_read_addr;
    
    bram_32bit fwd_fft_bram (
        .clka(clk_100mhz),    // input wire clka
        .wea(1),      // input wire [0 : 0] wea <-- PORT A ONLY FOR WRITING
        .addra(fwd_fft_bram_write_addr),  // input wire [10 : 0] addra
        .dina(data_to_fwd_fft_bram),    // input wire [11 : 0] dina
        .clkb(clk_100mhz),    // input wire clkb
        .addrb(fwd_fft_bram_read_addr),  // input wire [10 : 0] addrb
        .doutb(data_from_fwd_fft_bram)  // output wire [11 : 0] doutb
    ); 
    
    logic [15:0] data_to_fwd_fft_bram1, data_to_fwd_fft_bram2, data_to_fwd_fft_bram3, data_to_fwd_fft_bram4, data_to_fwd_fft_bram5, data_to_fwd_fft_bram6;
    logic [15:0] data_from_fwd_fft_bram1, data_from_fwd_fft_bram2, data_from_fwd_fft_bram3, data_from_fwd_fft_bram4, data_from_fwd_fft_bram5, data_from_fwd_fft_bram6;
    logic [ADDRESS_BIT_WIDTH-1:0] fft_bram1_addr_in, fft_bram2_addr_in, fft_bram3_addr_in, fft_bram4_addr_in, fft_bram5_addr_in, fft_bram6_addr_in;
    logic [ADDRESS_BIT_WIDTH-1:0] fft_bram1_addr_out, fft_bram2_addr_out, fft_bram3_addr_out, fft_bram4_addr_out, fft_bram5_addr_out, fft_bram6_addr_out;
    
   bram_16bit fwd_fft_bram1 (
        .clka(clk_100mhz),    // input wire clka
        .wea(1),      // input wire [0 : 0] wea <-- PORT A ONLY FOR WRITING
        .addra(fft_bram1_addr_in),  // input wire [10 : 0] addra
        .dina(data_to_fwd_fft_bram1),    // input wire [11 : 0] dina
        .clkb(clk_100mhz),    // input wire clkb
        .addrb(fft_bram1_addr_out),  // input wire [10 : 0] addrb
        .doutb(data_from_fwd_fft_bram1)  // output wire [11 : 0] doutb
    );

    bram_16bit fwd_fft_bram2 (
        .clka(clk_100mhz),    // input wire clka
        .wea(1),      // input wire [0 : 0] wea <-- PORT A ONLY FOR WRITING
        .addra(write_addr22),  // input wire [10 : 0] addra
        .dina(data_to_fwd_fft_bram2),    // input wire [11 : 0] dina
        .clkb(clk_100mhz),    // input wire clkb
        .addrb(read_addr22),  // input wire [10 : 0] addrb
        .doutb(data_from_fwd_fft_bram2)  // output wire [11 : 0] doutb
    );

    bram_16bit fwd_fft_bram3 (
        .clka(clk_100mhz),    // input wire clka
        .wea(1),      // input wire [0 : 0] wea <-- PORT A ONLY FOR WRITING
        .addra(write_addr23),  // input wire [10 : 0] addra
        .dina(data_to_fwd_fft_bram3),    // input wire [11 : 0] dina
        .clkb(clk_100mhz),    // input wire clkb
        .addrb(read_addr23),  // input wire [10 : 0] addrb
        .doutb(data_from_fwd_fft_bram3)  // output wire [11 : 0] doutb
    );

    bram_16bit fwd_fft_bram4 (
        .clka(clk_100mhz),    // input wire clka
        .wea(1),      // input wire [0 : 0] wea <-- PORT A ONLY FOR WRITING
        .addra(write_addr24),  // input wire [10 : 0] addra
        .dina(data_to_fwd_fft_bram4),    // input wire [11 : 0] dina
        .clkb(clk_100mhz),    // input wire clkb
        .addrb(read_addr24),  // input wire [10 : 0] addrb
        .doutb(data_from_fwd_fft_bram4)  // output wire [11 : 0] doutb
    );

    bram_16bit fwd_fft_bram5 (
        .clka(clk_100mhz),    // input wire clka
        .wea(1),      // input wire [0 : 0] wea <-- PORT A ONLY FOR WRITING
        .addra(write_addr25),  // input wire [10 : 0] addra
        .dina(data_to_fwd_fft_bram5),    // input wire [11 : 0] dina
        .clkb(clk_100mhz),    // input wire clkb
        .addrb(read_addr25),  // input wire [10 : 0] addrb
        .doutb(data_from_fwd_fft_bram5)  // output wire [11 : 0] doutb
    );
    
    bram_16bit fwd_fft_bram6 (
        .clka(clk_100mhz),    // input wire clka
        .wea(1),      // input wire [0 : 0] wea <-- PORT A ONLY FOR WRITING
        .addra(write_addr26),  // input wire [10 : 0] addra
        .dina(data_to_fwd_fft_bram6),    // input wire [11 : 0] dina
        .clkb(clk_100mhz),    // input wire clkb
        .addrb(read_addr26),  // input wire [10 : 0] addrb
        .doutb(data_from_fwd_fft_bram6)  // output wire [11 : 0] doutb
    );
    
    // Copy BRAM
    logic [2*BIT_DEPTH-1:0] data_to_copy1_bram;
    logic [2*BIT_DEPTH-1:0] data_from_copy1_bram;
    logic [ADDRESS_BIT_WIDTH-1:0] copy1_bram_write_addr, copy1_bram_read_addr;
    
    bram_32bit copy1 (
        .clka(clk_100mhz),    // input wire clka
        .wea(1),      // input wire [0 : 0] wea <-- PORT A ONLY FOR WRITING
        .addra(copy1_bram_write_addr),  // input wire [10 : 0] addra
        .dina(data_to_copy1_bram),    // input wire [11 : 0] dina
        .clkb(clk_100mhz),    // input wire clkb
        .addrb(copy1_bram_read_addr),  // input wire [10 : 0] addrb
        .doutb(data_from_copy1_bram)  // output wire [11 : 0] doutb
    );
    
    logic [2*BIT_DEPTH-1:0] data_to_copy2_bram;
    logic [2*BIT_DEPTH-1:0] data_from_copy2_bram;
    logic [ADDRESS_BIT_WIDTH-1:0] copy2_bram_write_addr, copy2_bram_read_addr;
    
    bram_32bit copy2 (
        .clka(clk_100mhz),    // input wire clka
        .wea(1),      // input wire [0 : 0] wea <-- PORT A ONLY FOR WRITING
        .addra(copy2_bram_write_addr),  // input wire [10 : 0] addra
        .dina(data_to_copy2_bram),    // input wire [11 : 0] dina
        .clkb(clk_100mhz),    // input wire clkb
        .addrb(copy2_bram_read_addr),  // input wire [10 : 0] addrb
        .doutb(data_from_copy2_bram)  // output wire [11 : 0] doutb
    );
    
    // Inverse FFT BRAM
    logic [2*BIT_DEPTH-1:0] data_to_inv_fft_bram;
    logic [2*BIT_DEPTH-1:0] data_from_inv_fft_bram;
    logic [ADDRESS_BIT_WIDTH-1:0] inv_fft_bram_write_addr, inv_fft_bram_read_addr;

    bram_32bit inv_fft_bram (
        .clka(clk_100mhz),    // input wire clka
        .wea(1),      // input wire [0 : 0] wea <-- PORT A ONLY FOR WRITING
        .addra(inv_fft_bram_write_addr),  // input wire [10 : 0] addra
        .dina(data_to_inv_fft_bram),    // input wire [11 : 0] dina
        .clkb(clk_100mhz),    // input wire clkb
        .addrb(inv_fft_bram_read_addr),  // input wire [10 : 0] addrb
        .doutb(data_from_inv_fft_bram)  // output wire [11 : 0] doutb
    );  
    
    assign hann_addr = fft_data_counter;
    
    logic [2:0] count, count1, inv_count;

    always_ff @(posedge clk_100mhz)begin
        if (rst_in) begin
            fwd_fft_bram_write_addr <= 0;
        end
        if (sample_counter == SAMPLE_COUNT) sample_counter <= 16'b0;
        else sample_counter <= sample_counter + 16'b1;
        
        if (sample_trigger) begin // 48kHz sampling rate
            scaled_adc_data <= 16*adc_data;
            scaled_signed_adc_data <= {~scaled_adc_data[15],scaled_adc_data[14:0]}; //convert to signed. incoming data is offset binary
        end
        if (fft_out_valid) begin
            fwd_fft_bram_write_addr <= fft_out_last ? NFFT_WINDOW_SIZE-1 : fwd_fft_bram_write_addr + 1'b1;
            data_to_fwd_fft_bram <= fft_out_data;
        end
        if (fft_out_valid1) begin
            fft_bram1_addr_in <= fft_out_last1 ? NFFT_WINDOW_SIZE-1 : fft_bram1_addr_in + 1'b1;
            fft_bram2_addr_in <= fft_out_last1 ? NFFT_WINDOW_SIZE-1 : fft_bram2_addr_in + 1'b1;
            fft_bram3_addr_in <= fft_out_last1 ? NFFT_WINDOW_SIZE-1 : fft_bram3_addr_in + 1'b1;
            fft_bram4_addr_in <= fft_out_last1 ? NFFT_WINDOW_SIZE-1 : fft_bram4_addr_in + 1'b1;
            fft_bram5_addr_in <= fft_out_last1 ? NFFT_WINDOW_SIZE-1 : fft_bram5_addr_in + 1'b1;
            fft_bram6_addr_in <= fft_out_last1 ? NFFT_WINDOW_SIZE-1 : fft_bram6_addr_in + 1'b1;
            data_to_fwd_fft_bram1 <= fft_out_data1;
            data_to_fwd_fft_bram2 <= fft_out_data1;
            data_to_fwd_fft_bram3 <= fft_out_data1;
            data_to_fwd_fft_bram4 <= fft_out_data1;
            data_to_fwd_fft_bram5 <= fft_out_data1;
            data_to_fwd_fft_bram6 <= fft_out_data1;
        end
        if (fwd_fft_bram_valid_out) begin
            copy1_bram_write_addr <= fwd_fft_bram_last_out ? NFFT_WINDOW_SIZE-1 : copy1_bram_write_addr + 1'b1;
            data_to_copy1_bram <= data_from_fwd_fft_bram;
        end
        if (copy1_bram_valid_out) begin
            copy2_bram_write_addr <= copy1_bram_last_out ? NFFT_WINDOW_SIZE-1 : copy2_bram_write_addr + 1'b1;
            data_to_copy2_bram <= data_from_copy1_bram;
        end
        if (inv_fft_out_valid) begin
            inv_fft_bram_write_addr <= inv_fft_out_last ? NFFT_WINDOW_SIZE-1 : inv_fft_bram_write_addr + 1'b1; 
            data_to_inv_fft_bram <= inv_fft_out_data;
            if (inv_fft_out_last) playback_start <= 1;
        end
        if (playback_start) playback_start <= !playback_start;
    end
    
    typedef enum {READ_WAIT_INIT_1, READ_WAIT_INIT_2, ACTION_TO_SLAVE, WAITING_FOR_SLAVE, DONE} MemState;
    MemState input_aud_bram_state;   
    MemState fwd_fft_bram_state;
    MemState copy1_bram_state;
    MemState copy2_bram_state;
   
    logic input_aud_bram_valid_out;
    logic input_aud_bram_last_out;
    logic fwd_fft_bram_valid_out;
    logic fwd_fft_bram_last_out;
    logic copy1_bram_valid_out;
    logic copy1_bram_last_out;
    logic copy2_bram_valid_out;
    logic copy2_bram_last_out;
    
    always_ff @(posedge clk_100mhz) begin
        if (rst_in) begin
            input_aud_bram_read_addr <= {ADDRESS_BIT_WIDTH{1'b0}};
        end
        if (recorder_last_out && recorder_valid_out) begin
            fft_data_counter <= {ADDRESS_BIT_WIDTH{1'b0}};
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
                    fft_data_counter <= fft_data_counter + 1'b1;
                    input_aud_bram_read_addr <= input_aud_bram_read_addr + 'b1;
                end
                ACTION_TO_SLAVE: begin
                    input_aud_bram_valid_out <= 1'b1;
                    if (fft_data_counter == 0) begin
                        input_aud_bram_last_out <= 1'b1;
                        input_aud_bram_state <= DONE;
                    end else begin 
                        input_aud_bram_state <= WAITING_FOR_SLAVE;
                    end
                end
                WAITING_FOR_SLAVE: begin
                    if (fft_ready == 1'b1) begin
                        input_aud_bram_valid_out <= 1'b0;
                        input_aud_bram_last_out <= 1'b0;
                        if (fft_data_counter == NFFT_WINDOW_SIZE-1) begin 
                            input_aud_bram_read_addr <= input_aud_bram_read_addr + INPUT_WINDOW_SIZE - 1;
                            fft_data_counter <={ADDRESS_BIT_WIDTH{1'b0}}; 
                        end else begin  
                            input_aud_bram_read_addr <= input_aud_bram_read_addr + 1'b1;
                            fft_data_counter <= fft_data_counter + 'b1;   
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
        
        if (fft_out_last && fft_out_valid) begin
            fwd_fft_bram_read_addr <= {ADDRESS_BIT_WIDTH{1'b0}};
            fwd_fft_bram_state <= READ_WAIT_INIT_1;
            fwd_fft_bram_last_out <= 1'b0;
            fwd_fft_bram_valid_out <= 1'b0;
        end else begin
            case (fwd_fft_bram_state) 
                READ_WAIT_INIT_1: begin
                    fwd_fft_bram_state <= READ_WAIT_INIT_2;
                end
                READ_WAIT_INIT_2: begin
                    fwd_fft_bram_state <= ACTION_TO_SLAVE;
                    fwd_fft_bram_read_addr <= fwd_fft_bram_read_addr + 'b1;
                end
                ACTION_TO_SLAVE: begin
                    fwd_fft_bram_valid_out <= 1'b1;
                    if (fwd_fft_bram_read_addr == 0) begin
                        fwd_fft_bram_last_out <= 1'b1;
                        fwd_fft_bram_state <= DONE;
                    end else begin 
                        fwd_fft_bram_state <= WAITING_FOR_SLAVE;
                    end
                end
                WAITING_FOR_SLAVE: begin
                    fwd_fft_bram_valid_out <= 1'b0;
                    fwd_fft_bram_last_out <= 1'b0;
                    if (fwd_fft_bram_read_addr == NFFT_WINDOW_SIZE-1) begin 
                        fwd_fft_bram_read_addr <={ADDRESS_BIT_WIDTH{1'b0}}; 
                    end else begin  
                        fwd_fft_bram_read_addr <= fwd_fft_bram_read_addr + 'b1;   
                    end
                    fwd_fft_bram_state <= ACTION_TO_SLAVE;  
                end
                DONE: begin
                    fwd_fft_bram_state <= DONE;
                    fwd_fft_bram_last_out <= 1'b0;
                    fwd_fft_bram_valid_out <= 1'b0;
                end
                default: fwd_fft_bram_state <= READ_WAIT_INIT_1;
            endcase
        end
        
        if (fwd_fft_bram_last_out && fwd_fft_bram_valid_out) begin
            copy1_bram_read_addr <= {ADDRESS_BIT_WIDTH{1'b0}};
            copy1_bram_state <= READ_WAIT_INIT_1;
            copy1_bram_last_out <= 1'b0;
            copy1_bram_valid_out <= 1'b0;
        end else begin
            case (copy1_bram_state) 
                READ_WAIT_INIT_1: begin
                    copy1_bram_state <= READ_WAIT_INIT_2;
                end
                READ_WAIT_INIT_2: begin
                    copy1_bram_state <= ACTION_TO_SLAVE;
                    copy1_bram_read_addr <= copy1_bram_read_addr + 'b1;
                end
                ACTION_TO_SLAVE: begin
                    copy1_bram_valid_out <= 1'b1;
                    if (copy1_bram_read_addr == 0) begin
                        copy1_bram_last_out <= 1'b1;
                        copy1_bram_state <= DONE;
                    end else begin 
                        copy1_bram_state <= WAITING_FOR_SLAVE;
                    end
                end
                WAITING_FOR_SLAVE: begin
                    copy1_bram_valid_out <= 1'b0;
                    copy1_bram_last_out <= 1'b0;
                    if (copy1_bram_read_addr == NFFT_WINDOW_SIZE-1) begin 
                        copy1_bram_read_addr <={ADDRESS_BIT_WIDTH{1'b0}}; 
                    end else begin  
                        copy1_bram_read_addr <= copy1_bram_read_addr + 'b1;   
                    end
                    copy1_bram_state <= ACTION_TO_SLAVE;
                end
                DONE: begin
                    copy1_bram_state <= DONE;
                    copy1_bram_last_out <= 1'b0;
                    copy1_bram_valid_out <= 1'b0;
                end
                default: copy1_bram_state <= READ_WAIT_INIT_1;
            endcase
        end
        
        if (copy1_bram_last_out && copy1_bram_valid_out) begin
            copy2_bram_read_addr <= {ADDRESS_BIT_WIDTH{1'b0}};
            copy2_bram_state <= READ_WAIT_INIT_1;
            copy2_bram_last_out <= 1'b0;
            copy2_bram_valid_out <= 1'b0;
        end else begin
            case (copy2_bram_state) 
                READ_WAIT_INIT_1: begin
                    copy2_bram_state <= READ_WAIT_INIT_2;
                end
                READ_WAIT_INIT_2: begin
                    copy2_bram_state <= ACTION_TO_SLAVE;
                    copy2_bram_read_addr <= copy2_bram_read_addr + 'b1;
                end
                ACTION_TO_SLAVE: begin
                    copy2_bram_valid_out <= 1'b1;
                    if (copy2_bram_read_addr == 0) begin
                        copy2_bram_last_out <= 1'b1;
                        copy2_bram_state <= DONE;
                    end else begin 
                        copy2_bram_state <= WAITING_FOR_SLAVE;
                    end
                end
                WAITING_FOR_SLAVE: begin
                    if (inv_fft_ready == 1'b1) begin
                        copy2_bram_valid_out <= 1'b0;
                        copy2_bram_last_out <= 1'b0;
                        if (copy2_bram_read_addr == NFFT_WINDOW_SIZE-1) begin 
                            copy2_bram_read_addr <={ADDRESS_BIT_WIDTH{1'b0}}; 
                        end else begin  
                            copy2_bram_read_addr <= copy2_bram_read_addr + 'b1;   
                        end
                        copy2_bram_state <= ACTION_TO_SLAVE;
                    end else begin
                        copy2_bram_state <= WAITING_FOR_SLAVE;
                    end  
                end
                DONE: begin
                    copy2_bram_state <= DONE;
                    copy2_bram_last_out <= 1'b0;
                    copy2_bram_valid_out <= 1'b0;
                end
                default: copy2_bram_state <= READ_WAIT_INIT_1;
            endcase
        end
    end

    xadc_wiz_0 my_adc ( .dclk_in(clk_100mhz), .daddr_in(8'h13), //read from 0x13 for a
                        .vauxn3(vauxn3),.vauxp3(vauxp3),
                        .vp_in(1),.vn_in(1),
                        .di_in(16'b0),
                        .do_out(adc_data),.drdy_out(adc_ready),
                        .den_in(1), .dwe_in(0));
 
    recorder myrec( .clk_in(clk_100mhz),.rst_in(btnd),
                    .ready_in(sample_trigger),.filter_in(sw[11]),
                    .mic_in(scaled_signed_adc_data),
                    .write_addr(input_aud_bram_write_addr),
                    .recorder_last(recorder_last_out),
                    .recorder_valid(recorder_valid_out),
                    .data_out(recorder_data)); 
                    
    hann_rom hann_coeff_rom (   .clka(clk_100mhz),    // input wire clka
                                .addra(hann_addr),  // input wire [9 : 0] addra
                                .douta(hann_coeff)  // output wire [10 : 0] douta
    );
    
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
    xfft_0 fwd_fft (.aclk(clk_100mhz), .s_axis_data_tdata(sw[10] ? {1'b0,hann_data_product[11+BIT_DEPTH-1:11+1]} : data_from_input_aud_bram), 
                    .s_axis_data_tvalid(input_aud_bram_valid_out),
                    .s_axis_data_tlast(input_aud_bram_last_out), .s_axis_data_tready(fft_ready),
                    .s_axis_config_tdata(0), 
                     .s_axis_config_tvalid(0),
                     .s_axis_config_tready(),
                    .m_axis_data_tdata(fft_out_data), .m_axis_data_tvalid(fft_out_valid),
                    .m_axis_data_tlast(fft_out_last), .m_axis_data_tready(fft_out_ready));
                   
    freq_detection_fft fwd_fft2 (.aclk(clk_100mhz), .s_axis_data_tdata(fft_data1), 
                    .s_axis_data_tvalid(fft_valid1),
                    .s_axis_data_tlast(fft_last1), .s_axis_data_tready(fft_ready1),
                    .s_axis_config_tdata(0), 
                     .s_axis_config_tvalid(0),
                     .s_axis_config_tready(),
                    .m_axis_data_tdata(fft_out_data1), .m_axis_data_tvalid(fft_out_valid1),
                    .m_axis_data_tlast(fft_out_last1), .m_axis_data_tready(1));
                            
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
                    
    xfft_0 inv_fft (.aclk(clk_100mhz), .s_axis_data_tdata(data_from_copy2_bram), 
                    .s_axis_data_tvalid(copy2_bram_valid_out),
                    .s_axis_data_tlast(copy2_bram_last_out), .s_axis_data_tready(inv_fft_ready),
                    .s_axis_config_tdata(0), 
                    .s_axis_config_tvalid(1),
                    .s_axis_config_tready(),
                    .m_axis_data_tdata(inv_fft_out_data), .m_axis_data_tvalid(inv_fft_out_valid),
                    .m_axis_data_tlast(inv_fft_out_last), .m_axis_data_tready(1));
             
    playback player(    .clk_in(clk_100mhz), .rst_in(btnd),
                        .ready_in(sample_trigger),.filter_in(sw[12]),
                        .read_addr(inv_fft_bram_read_addr), 
                        .input_data(data_from_inv_fft_bram[BIT_DEPTH-1:0]),
                        .playback_start(playback_start),
                        .data_out(playback_data));  
                                                                                                          
    volume_control vc (.vol_in(sw[15:13]),
                       .signal_in(playback_data[BIT_DEPTH-1: BIT_DEPTH-1-16+1]), .signal_out(vol_out));

    pwm (.clk_in(clk_100mhz), .rst_in(btnd), .level_in({~vol_out[11],vol_out[10:0]}), .pwm_out(pwm_val));
    assign aud_pwm = pwm_val?1'bZ:1'b0;
      
    logic [9:0] addr_count;
    logic [9:0] draw_addr;
    logic [16:0] spectrogram_count;
    logic [16:0] spectrogram_draw_addr;
    logic spectrogram_wea;
    logic [15:0] spectrogram_raw_amp_in;
    
    logic [31:0] raw_amp_out;
    logic [31:0] shifted_amp_out;
    logic [15:0] spectrogram_raw_amp_out;
    
    parameter SPECTROGRAM_BRAM_WIDTH = 256;
    parameter SPECTROGRAM_BRAM_HEIGHT = 512;
    
//    assign spectrogram_wea = sqrt_valid && addr_count <= 'd512;
    always_ff @(posedge clk_100mhz) begin
        if (rst_in) begin
            addr_count <= 0;
            spectrogram_count <= 0;
            spectrogram_wea <= 0;
            spectrogram_raw_amp_in <= 0;
        end else if (!rst_in && sqrt_valid)begin
            spectrogram_wea <= addr_count <= SPECTROGRAM_BRAM_HEIGHT;
            if (sqrt_last) begin
                addr_count <= 'd0; //allign
            end else begin
                addr_count <= addr_count + 1;
                
                if (addr_count <= SPECTROGRAM_BRAM_HEIGHT) begin
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
    value_bram mvb_raw (.addra(addr_count), .clka(clk_100mhz), .dina({8'b0,sqrt_data}),
                    .douta(), .ena(1'b1), .wea(sqrt_valid),.dinb(0),
                    .addrb(draw_addr), .clkb(pixel_clk), .doutb(raw_amp_out),
                    .web(1'b0), .enb(1'b1));    
                    
    value_bram mvb_shifted (.addra(addr_count), .clka(clk_100mhz), .dina({8'b0,sqrt_data}),
                    .douta(), .ena(1'b1), .wea(sqrt_valid),.dinb(0),
                    .addrb(draw_addr), .clkb(pixel_clk), .doutb(shifted_amp_out),
                    .web(1'b0), .enb(1'b1));     
                    
    spectrogram_bram msb_raw (.addra(spectrogram_count), .clka(clk_100mhz), .dina(spectrogram_raw_amp_in),
                    .douta(), .ena(1'b1), .wea(spectrogram_wea),.dinb(0),
                    .addrb(spectrogram_draw_addr), .clkb(pixel_clk), .doutb(spectrogram_raw_amp_out),
                    .web(1'b0), .enb(1'b1));
                    
    visualizer viz (.clk_in(pixel_clk), .rst_in(btnd), 
                    .raw_amp_out(raw_amp_out), .shifted_amp_out(shifted_amp_out),  
                    .spectrogram_raw_amp_out(spectrogram_raw_amp_out), .nat_freq(nat_freq),
                    .amp_scale(sw[3:0]), .visualize_mode(sw[5:4]), .pwm_val(pwm_val), 
                    .draw_addr(draw_addr), .spectrogram_draw_addr(spectrogram_draw_addr),
                    .vga_r(vga_r), .vga_b(vga_b), .vga_g(vga_g), .vga_hs(vga_hs), .vga_vs(vga_vs), 
                    .aud_pwm(aud_pwm));  
                    
    logic [9:0] fftk_addr;
    logic [31:0] fftk_ampl;
    logic [31:0] fft2k_ampl;
    logic [31:0] fft3k_ampl;
    
    value_bram fftk (.addra(addr_count), .clka(clk_100mhz), .dina({8'b0,sqrt_data}),
                    .douta(), .ena(1'b1), .wea(sqrt_valid),.dinb(0),
                    .addrb(fftk_addr), .clkb(pixel_clk), .doutb(fftk_ampl),
                    .web(1'b0), .enb(1'b1));
    value_bram fft2k (.addra(addr_count), .clka(clk_100mhz), .dina({8'b0,sqrt_data}),
                    .douta(), .ena(1'b1), .wea(sqrt_valid),.dinb(0),
                    .addrb(fftk_addr*2), .clkb(pixel_clk), .doutb(fft2k_ampl),
                    .web(1'b0), .enb(1'b1));                
    value_bram fft3k (.addra(addr_count), .clka(clk_100mhz), .dina({8'b0,sqrt_data}),
                    .douta(), .ena(1'b1), .wea(sqrt_valid),.dinb(0),
                    .addrb(fftk_addr*3), .clkb(pixel_clk), .doutb(fft3k_ampl),
                    .web(1'b0), .enb(1'b1));
                    
    localparam FFT_WINDOW_SIZE = 1024;
    localparam FFT_SAMPLE_SIZE = 32;
    localparam HPS_NUMBER_OF_TERMS = 3;
           
    logic s_ready;
    logic [FFT_SAMPLE_SIZE*HPS_NUMBER_OF_TERMS-1:0] s_data;
    logic s_last;
    logic s_valid;
    logic m_valid;
    logic [9:0] m_data;
    
    freq_detect_v3_0 #(.FFT_WINDOW_SIZE(FFT_WINDOW_SIZE), .FFT_SAMPLE_SIZE(FFT_SAMPLE_SIZE)) 
        my_freq_detect(.clk(pixel_clk), .resetn(1'b1),
                            .s00_axis_tready(s_ready),
                            .s00_axis_tdata(s_data),.s00_axis_tlast(s_last),
                            .s00_axis_tvalid(s_valid),
                            .m00_axis_tvalid(m_valid),
                            .m00_axis_tdata(m_data),
                            .m00_axis_tready());
                            
    /*
    Memstate mem_state;
    logic [9:0] nat_freq;
    
    always_ff @(posedge pixel_clk) begin
        if (btnd == 1'b1) begin // kinda reset
            fftk_addr <= 10'b0;
            mem_state <= READ_WAIT;
            s_data <= {FFT_SAMPLE_SIZE*HPS_NUMBER_OF_TERMS{1'b0}};
            s_last <= 1'b0;
            s_valid <= 1'b0;
            nat_freq <=10'b0;
        end else begin
            case (mem_state) 
                READ_WAIT: begin
                        mem_state <= ACTION_TO_SLAVE;
                    end
                ACTION_TO_SLAVE: begin
                        if (fftk_addr == 10'd170) begin
                            s_last <=1'b1;
                            fftk_addr <= 10'd0;
                        end else begin
                            fftk_addr <= fftk_addr + 10'b1;
                            s_last <=1'b0;
                        end
                        if (fftk_addr < 10'd2)
                            s_data <= {FFT_SAMPLE_SIZE*HPS_NUMBER_OF_TERMS{1'b0}};
                        else
                            s_data <= {fftk_ampl, fft2k_ampl, fft3k_ampl};
                        s_valid <= 1'b1;
                        mem_state <= WAITING_FOR_SLAVE;
                    end
                WAITING_FOR_SLAVE: begin
                        if (s_ready == 1'b1) begin
                            s_valid <= 1'b0;
                            s_last <= 1'b0;
                            mem_state <= ACTION_TO_SLAVE;
                        end else begin
                            mem_state <= WAITING_FOR_SLAVE;
                        end  
                        mem_state <= READ_WAIT;    
                    end
                default: mem_state <= READ_WAIT;
            endcase 
            
            if (m_valid == 1'b1) begin
                nat_freq <= m_data;
            end
        end
    end  */
    
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