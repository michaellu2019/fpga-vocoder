`default_nettype none //prevents system from inferring an undeclared logic


module freq_shift # 
    (
        // Non blocking freq_shift, will start over if triggered in the middle of the process
        // Users to add parameters here
        parameter integer FFT_WINDOW_SIZE = 1024, // !!! MUST BE A POWER OF 2 for the algorithm to work correctly !!!!!
        parameter integer FFT_SAMPLE_SIZE = 32,
        
        localparam integer ADDRESS_SIZE    = $clog2(FFT_WINDOW_SIZE),
        localparam integer COEFF_INTEGER_SIZE = ADDRESS_SIZE, // when we divide two numbers the reuslting integer bit width is the same as for either
        localparam integer COEFF_DECIMAL_SIZE = ADDRESS_SIZE,
        localparam integer COEFF_SIZE = COEFF_INTEGER_SIZE + COEFF_DECIMAL_SIZE
    )

    (
        input wire clk_in,
        input wire reset_in,
        input wire trigger_in, // starts the module
        input wire [COEFF_SIZE-1:0] coeff_increase_in, // f_desired/f_main, will be used if larger than 1
        input wire [COEFF_SIZE-1:0] coeff_decrease_in, // f_main/f_desired, will be used if equal to or larger than 1
        
        // for interfacing with external raw FFT and shifted FFT brams
        input wire [FFT_SAMPLE_SIZE-1:0] read_data_in,
        output logic [ADDRESS_SIZE-1:0] read_addr_out,
        
        output logic [FFT_SAMPLE_SIZE-1:0] write_data_out,
        output logic [ADDRESS_SIZE-1:0] write_addr_out,
        output logic write_en_out,
        
        // for the next module to know that shift is complete; pulses high.
        output logic shift_done_out
    );
    
    
    typedef enum {WAITING, INCREASE, DECREASE} FuncState;
    FuncState func_state;
    
    logic [COEFF_SIZE-1:0] coeff_increase_reg; // save the input coeff used later in calculation
    logic [COEFF_SIZE-1:0] coeff_decrease_reg; // save the input coeff used later in calculation
    
    // minor FSM inside INCREASING state of FuncState FSM for performing freq shifting that results in higher freq
    typedef enum {INCR_INIT_WAIT_1, INCR_INIT_WAIT_2, INCR_POS_FREQ, INCR_B4_NEG_WAIT_1, INCR_B4_NEG_WAIT_2 , INCR_NEG_FREQ} IncrState;
    IncrState incr_state;
    // minor FSM inside INCR_POS_FREQ state of IncrState FSM for performing freq shifting that results in higher freq of positive freqs
    typedef enum {INCR_POS_ACTION, INCR_POS_READ_WAIT, INCR_POS_UPDATE} IncrPosState;
    IncrPosState incr_pos_state;
    // minor FSM inside INCR_NEG_FREQ state of IncrState FSM for performing freq shifting that results in higher freq of negative freqs
    typedef enum {INCR_NEG_ACTION, INCR_NEG_READ_WAIT, INCR_NEG_UPDATE} IncrNegState;
    IncrNegState incr_neg_state;
    // incr_j_int is write_addr corresponding to read_addr_out when increasing freq
    logic [COEFF_SIZE-1:0] incr_j;
    logic [ADDRESS_SIZE-1:0] incr_j_int;
    assign incr_j_int = incr_j [ADDRESS_SIZE+COEFF_DECIMAL_SIZE-1:COEFF_DECIMAL_SIZE];
    
    logic [ADDRESS_SIZE-1:0] last_written_addr_pos; // for zero padding in freq decrease module
    
    // minor FSM inside DECREASING state of FuncState FSM for performing freq shifting that results in lower freq
    typedef enum {DECR_INIT_WAIT_1, DECR_INIT_WAIT_2, DECR_NEG_FREQ, DECR_B4_POS_WAIT_1, DECR_B4_POS_WAIT_2, DECR_POS_FREQ, DECR_ZERO_PADDING} DecrState;
    DecrState decr_state; 
    // minor FSM inside DECR_NEG_FREQ state of DecrState FSM for performing freq shifting that results in lower freq of negative freqs
    typedef enum {DECR_NEG_ACTION, DECR_NEG_WAIT} DecrNegState;
    DecrNegState decr_neg_state;
    // minor FSM inside DECR_POS_FREQ state of DecrState FSM for performing freq shifting that results in lower freq of positive freqs
    typedef enum {DECR_POS_ACTION, DECR_POS_WAIT} DecrPosState;
    DecrPosState decr_pos_state;
    
    // decr_i is read_addr corresponding to next write_addr_out when decreasing freq
    logic [COEFF_SIZE-1:0] decr_i;
    logic [ADDRESS_SIZE-1:0] decr_i_int;
    assign decr_i_int = decr_i [ADDRESS_SIZE+COEFF_DECIMAL_SIZE-1:COEFF_DECIMAL_SIZE];
    
    always_ff @(posedge clk_in) begin
        if (reset_in == 1'b1) begin
            read_addr_out <= {ADDRESS_SIZE{1'b0}};
            write_addr_out <= {ADDRESS_SIZE{1'b0}};
            write_data_out <= {FFT_SAMPLE_SIZE{1'b0}};
            write_en_out <= 1'b0;
            shift_done_out <=1'b0;
            last_written_addr_pos <= {ADDRESS_SIZE{1'b0}};
            func_state <= WAITING; 
            coeff_increase_reg <= coeff_increase_in;
            incr_j <= {COEFF_SIZE{1'b0}};
            coeff_decrease_reg <= coeff_decrease_in;
            decr_i <= {COEFF_SIZE{1'b0}};
        end else if (trigger_in == 1'b1) begin  // end of reset_in
            // very similar to reset except a different next state
            write_data_out <= {FFT_SAMPLE_SIZE{1'b0}};
            write_en_out <= 1'b0;
            shift_done_out <=1'b0;
            last_written_addr_pos <= {ADDRESS_SIZE{1'b0}}; 
            coeff_increase_reg <= coeff_increase_in;
            coeff_decrease_reg <= coeff_decrease_in;
            // if integer part of coeff_increase_in is larger than 1 
            if (coeff_increase_in[COEFF_SIZE-1: COEFF_DECIMAL_SIZE] > {{(COEFF_INTEGER_SIZE-1){1'b0}}, 1'b1}) begin
                func_state <= INCREASE;
                incr_state <= INCR_INIT_WAIT_1;
                read_addr_out <= {ADDRESS_SIZE{1'b0}};
                incr_j <= {COEFF_SIZE{1'b0}};
                write_addr_out <= {ADDRESS_SIZE{1'b0}};
            end else begin
                func_state <= DECREASE;
                decr_state <= DECR_INIT_WAIT_1;
                read_addr_out <= FFT_WINDOW_SIZE - coeff_decrease_in[COEFF_SIZE-1: COEFF_DECIMAL_SIZE];
                decr_i <= 0 - coeff_decrease_in;
                write_addr_out <= FFT_WINDOW_SIZE - 1;
            end
        end else begin // end of !reset_in and trigger_in
            case (func_state)
                WAITING: begin
                    func_state <= WAITING;
                    write_en_out <= 1'b0;
                    shift_done_out <=1'b0;
                end
                
                INCREASE: begin
                    case (incr_state)
                        INCR_INIT_WAIT_1: begin
                            incr_state <= INCR_INIT_WAIT_2;
                        end
                        
                        INCR_INIT_WAIT_2: begin
                            incr_state <= INCR_POS_FREQ;
                            incr_pos_state <= INCR_POS_ACTION;
                        end
                        
                        // shifting all positive freq and inserting zeroes in between
                        INCR_POS_FREQ: begin
                            case (incr_pos_state) 
                                INCR_POS_ACTION: begin
                                    if (write_addr_out == incr_j_int) begin // if shift FFT address is equal to read_addr*alpha_incr
                                        write_data_out <= read_data_in;
                                        read_addr_out <= read_addr_out + 1;
                                        incr_j <= incr_j + coeff_increase_in;
                                        incr_pos_state <= INCR_POS_READ_WAIT;
                                    end else begin
                                        write_en_out <= 1'b1;
                                        write_data_out <= {FFT_SAMPLE_SIZE{1'b0}};
                                        incr_pos_state <= INCR_POS_UPDATE;
                                    end
                                end
                                
                                INCR_POS_READ_WAIT: begin
                                    incr_pos_state <= INCR_POS_UPDATE;
                                    write_en_out <= 1'b1;
                                end
                                
                                INCR_POS_UPDATE: begin
                                    write_en_out <= 1'b0;
                                    if (write_addr_out >= FFT_WINDOW_SIZE/2) begin
                                        incr_state <= INCR_B4_NEG_WAIT_1;
                                        read_addr_out <= FFT_WINDOW_SIZE - 1;
                                        incr_j <= 0 - coeff_increase_in;
                                        write_addr_out <= FFT_WINDOW_SIZE - 1;
                                    end else begin
                                        write_addr_out <= write_addr_out + 1;
                                        incr_pos_state <= INCR_POS_ACTION;
                                    end
                                end
                                
                                default: incr_pos_state <= INCR_POS_READ_WAIT;
                            endcase
                        end
                        
                        INCR_B4_NEG_WAIT_1: begin
                            incr_state <= INCR_B4_NEG_WAIT_2;
                        end
                        
                        INCR_B4_NEG_WAIT_2: begin
                            incr_state <= INCR_NEG_FREQ;
                            incr_neg_state <= INCR_NEG_ACTION;
                        end
                        
                        // shifting all negative (n > Nfft/2) freq and inserting zeroes in between
                        INCR_NEG_FREQ: begin
                            case (incr_neg_state)
                                INCR_NEG_ACTION: begin
                                    if (write_addr_out == incr_j_int) begin // if shift FFT address is equal to read_addr*alpha_incr
                                        write_data_out <= read_data_in;
                                        read_addr_out <= read_addr_out - 1;
                                        incr_j <= incr_j - coeff_increase_in;
                                        incr_neg_state <= INCR_NEG_READ_WAIT;
                                    end else begin
                                        write_en_out <= 1'b1;
                                        write_data_out <= {FFT_SAMPLE_SIZE{1'b0}};
                                        incr_neg_state <= INCR_NEG_UPDATE;
                                    end
                                end
                                
                                INCR_NEG_READ_WAIT: begin
                                    incr_neg_state <= INCR_NEG_UPDATE;
                                    write_en_out <= 1'b1;
                                end
                                        
                                INCR_NEG_UPDATE: begin
                                    write_en_out <= 1'b0;
                                    if (write_addr_out <= (FFT_WINDOW_SIZE/2+1)) begin // means we are done with increasing frequency
                                        func_state <= WAITING;
                                        shift_done_out <=1'b1; 
                                    end else begin
                                        write_addr_out <= write_addr_out - 1;
                                        incr_neg_state <= INCR_NEG_ACTION;
                                    end
                                end

                                default: incr_neg_state <= INCR_NEG_READ_WAIT; 
                            endcase
                        end
                        
                        default: incr_state <= INCR_INIT_WAIT_1;
                    endcase
                end
                
                DECREASE: begin
                    case (decr_state)
                        DECR_INIT_WAIT_1: begin
                            decr_state <= DECR_INIT_WAIT_2;
                            decr_i <= decr_i - coeff_decrease_in;
                        end
                        
                        DECR_INIT_WAIT_2: begin
                            decr_state <= DECR_NEG_FREQ;
                            decr_neg_state <= DECR_NEG_ACTION;
                            read_addr_out <= decr_i_int; // decr_i is -2*coeff_decrease_in at this point
                        end

                        // shifting all negative (n > Nfft/2) freq
                        DECR_NEG_FREQ: begin
                            case (decr_neg_state) 
                                DECR_NEG_ACTION: begin
                                    write_en_out <= 1'b1;
                                    write_data_out <= read_data_in;
                                    
                                    if (read_addr_out <= FFT_WINDOW_SIZE/2) begin // done with DECR_NEG
                                        decr_state <= DECR_B4_POS_WAIT_1;
                                        read_addr_out <= {ADDRESS_SIZE{1'b0}};
                                        decr_i <= {COEFF_SIZE{1'b0}};
                                    end else begin
                                        decr_neg_state <= DECR_NEG_WAIT;
                                        decr_i <= decr_i - coeff_decrease_in;
                                    end
                                end
                                
                                DECR_NEG_WAIT: begin
                                    write_en_out <= 1'b0;
                                    write_addr_out <= write_addr_out - 1;
                                    read_addr_out <= decr_i_int;
                                    decr_neg_state <= DECR_NEG_ACTION;
                                end
                                
                                default: decr_neg_state <= DECR_NEG_WAIT;
                            endcase
                        end
                        
                        DECR_B4_POS_WAIT_1: begin
                            decr_state <= DECR_B4_POS_WAIT_2;
                            decr_i <= decr_i + coeff_decrease_in;
                            // cleaning up for previous stage
                            write_en_out <= 1'b0;
                            write_addr_out <= {ADDRESS_SIZE{1'b0}};
                        end
                        
                        DECR_B4_POS_WAIT_2: begin
                            decr_state <= DECR_POS_FREQ;
                            decr_pos_state <= DECR_POS_ACTION;
                            read_addr_out <= decr_i_int; // decr_i is coeff_decrease_in at this point
                        end
                        // TODO change this one
                        // shifting all positive (n <= Nfft/2) freq to lower values
                        DECR_POS_FREQ: begin
                            case (decr_pos_state) 
                                DECR_POS_ACTION: begin
                                    write_en_out <= 1'b1;
                                    write_data_out <= read_data_in;
                                    
                                    if (read_addr_out > FFT_WINDOW_SIZE/2) begin // done with DECR_POS
                                        decr_state <= DECR_ZERO_PADDING;
                                        last_written_addr_pos <= write_addr_out;
                                    end else begin
                                        decr_pos_state <= DECR_POS_WAIT;
                                        decr_i <= decr_i + coeff_decrease_in;
                                    end
                                end
                                
                                DECR_POS_WAIT: begin
                                    write_en_out <= 1'b0;
                                    write_addr_out <= write_addr_out + 1;
                                    read_addr_out <= decr_i_int;
                                    decr_pos_state <= DECR_POS_ACTION;
                                end
                                
                                default: decr_pos_state <= DECR_POS_WAIT;
                            endcase
                        end
                 
                        // padding the missing frequnecies in the shifted fft with zeroes
                        DECR_ZERO_PADDING: begin
                            if (write_addr_out >= FFT_WINDOW_SIZE - last_written_addr_pos) begin // we are done with freq decrease
                                write_en_out <= 1'b0;
                                func_state <= WAITING;
                                shift_done_out <=1'b1; 
                            end else begin
                                write_data_out <= {FFT_SAMPLE_SIZE{1'b0}};
                                write_addr_out <= write_addr_out + 1;
                            end
                        end
                        
                        default: decr_state <= DECR_INIT_WAIT_1;
                    endcase
                end
                
                default: begin
                    func_state <= WAITING;
                    write_en_out <= 1'b0;
                    shift_done_out <=1'b0;
                end
            endcase
        end  //end of !reset_in and !trigger_in
        
    end
    
    
endmodule

`default_nettype wire //important to put at end (makes it work nicer with IP modules)