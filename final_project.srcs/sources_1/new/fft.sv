module fwd_fft(
  input wire clk_in,              // 100MHz system clock
  input wire rst_in,                // 1 to reset to initial state
  input wire signed [2*BIT_DEPTH-1:0] fft_in_data,
  input wire fft_in_last,
  input wire fft_in_valid,
  output logic [ADDRESS_BIT_WIDTH-1:0] fft_in_bram_read_addr,
  output logic [ADDRESS_BIT_WIDTH-1:0] fft_out_bram_write_addr,        
  output logic signed [2*BIT_DEPTH-1:0] fft_out_data,
  output logic fft_out_last,
  output logic fft_out_valid
);        
    parameter INPUT_WINDOW_SIZE = 512;
    parameter WINDOW_NUM = 4;
    parameter NFFT_WINDOW_SIZE = INPUT_WINDOW_SIZE*WINDOW_NUM;
    parameter BIT_DEPTH = 16; 
    parameter ADDRESS_BIT_WIDTH = $clog2(NFFT_WINDOW_SIZE);

    logic [ADDRESS_BIT_WIDTH-1:0] fft_data_counter;
    logic fft_ready;

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
    
    typedef enum {READ_WAIT_INIT_1, READ_WAIT_INIT_2, ACTION_TO_SLAVE, WAITING_FOR_SLAVE, DONE} MemState;
    MemState input_bram_state;
    logic input_bram_last_out, input_bram_valid_out;

    always_ff @(posedge clk_in)begin
        if (rst_in) begin
            fft_in_bram_read_addr <= {ADDRESS_BIT_WIDTH{1'b0}};
        end
        if (fft_in_last && fft_in_valid) begin
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
                    fft_in_bram_read_addr <= fft_in_bram_read_addr + 'b1;
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
                            fft_in_bram_read_addr <= fft_in_bram_read_addr + INPUT_WINDOW_SIZE - 1;
                            fft_data_counter <={ADDRESS_BIT_WIDTH{1'b0}}; 
                        end else begin  
                            fft_in_bram_read_addr <= fft_in_bram_read_addr + 1'b1;
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
            fft_out_bram_write_addr <= fft_out_last ? NFFT_WINDOW_SIZE-1 : fft_out_bram_write_addr + 1'b1;
        end
    end               
endmodule