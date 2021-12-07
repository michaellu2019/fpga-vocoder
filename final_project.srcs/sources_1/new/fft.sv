module fwd_fft(
  input wire clk_in,              // 100MHz system clock
  input wire rst_in,                // 1 to reset to initial state
  input wire signed [2*BIT_DEPTH-1:0] input_data,
  input wire input_last,
  input wire input_valid,
  output logic [ADDRESS_BIT_WIDTH-1:0] read_addr,
  output logic [ADDRESS_BIT_WIDTH-1:0] write_addr,        
  output logic signed [2*BIT_DEPTH-1:0] data_out
);        
    parameter WINDOW_SIZE = 512;
    parameter WINDOW_NUM = 4;
    parameter NFFT_WINDOW_SIZE = WINDOW_SIZE*WINDOW_NUM;
    parameter BIT_DEPTH = 16; 
    parameter ADDRESS_BIT_WIDTH = $clog2(NFFT_WINDOW_SIZE);

    logic [ADDRESS_BIT_WIDTH-1:0] fft_data_counter;
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
    xfft_0 my_fft ( .aclk(clk_in), .s_axis_data_tdata(input_data), 
                    .s_axis_data_tvalid(input_bram_valid_out),
                    .s_axis_data_tlast(input_bram_last_out), .s_axis_data_tready(fft_ready),
                    .s_axis_config_tdata(0), 
                    .s_axis_config_tvalid(0),
                    .s_axis_config_tready(),
                    .m_axis_data_tdata(fft_out_data), .m_axis_data_tvalid(fft_out_valid),
                    .m_axis_data_tlast(fft_out_last), .m_axis_data_tready(1));
    
    MemState input_bram_state;
    logic input_bram_last_out, input_bram_valid_out;

    always_ff @(posedge clk_in)begin
        if (rst_in) begin
            read_addr <= {ADDRESS_BIT_WIDTH{1'b0}};
        end
        if (input_last && input_valid) begin
            fft_data_counter <= {ADDRESS_BIT_WIDTH{1'b0}};
            input_bram_state <= READ_WAIT_INIT_1;
            input_bram_last_out <= 1'b0;
            input_bram_valid_out <= 1'b0;
        end else begin
            case (input_bram_state) 
                READ_WAIT_INIT_1: begin
                    input_bram_state <= READ_WAIT_INIT_2;
                end
                READ_WAIT_INIT_2: begin
                    input_bram_state <= ACTION_TO_SLAVE;
                    fft_data_counter <= fft_data_counter + 1'b1;
                    read_addr <= read_addr + 'b1;
                end
                ACTION_TO_SLAVE: begin
                    input_bram_valid_out <= 1'b1;
                    if (fft_data_counter == 0) begin
                        input_bram_last_out <= 1'b1;
                        input_bram_state <= DONE;
                    end else begin 
                        input_bram_state <= WAITING_FOR_SLAVE;
                    end
                end
                WAITING_FOR_SLAVE: begin
                    if (fft_ready == 1'b1) begin
                        input_bram_valid_out <= 1'b0;
                        input_bram_last_out <= 1'b0;
                        if (fft_data_counter == NFFT_WINDOW_SIZE-1) begin 
                            read_addr <= read_addr + INPUT_WINDOW_SIZE - 1;
                            fft_data_counter <={ADDRESS_BIT_WIDTH{1'b0}}; 
                        end else begin  
                            read_addr <= read_addr + 1'b1;
                            fft_data_counter <= fft_data_counter + 'b1;   
                        end
                        input_bram_state <= ACTION_TO_SLAVE;
                    end else begin
                        input_bram_state <= WAITING_FOR_SLAVE;
                    end  
                end
                DONE: begin
                    input_bram_state <= DONE;
                    input_bram_last_out <= 1'b0;
                    input_bram_valid_out <= 1'b0;
                end
                default: input_bram_state <= READ_WAIT_INIT_1;
            endcase
        end
        if (fft_out_valid) begin
            write_addr <= fft_out_last ? NFFT_WINDOW_SIZE-1 : write_addr + 1'b1;
            data_out <= fft_out_data;
        end
    end               
endmodule 

module inv_fft(
  input wire clk_in,              // 100MHz system clock
  input wire rst_in,                // 1 to reset to initial state
  input wire signed[2*BIT_DEPTH-1:0] input_data,
  input wire input_last,
  input wire input_valid,
  output logic [ADDRESS_BIT_WIDTH:0] read_addr, write_addr, 
  output logic output_last,
  output logic output_valid,       
  output logic signed [2*BIT_DEPTH-1:0] data_out
);        

    parameter WINDOW_SIZE = 512;
    parameter WINDOW_NUM = 4;
    parameter NFFT_WINDOW_SIZE = WINDOW_SIZE*WINDOW_NUM;
    parameter BIT_DEPTH = 16; 
    parameter ADDRESS_BIT_WIDTH = $clog2(NFFT_WINDOW_SIZE); 

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