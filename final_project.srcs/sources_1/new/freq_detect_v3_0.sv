`default_nettype none //prevents system from inferring an undeclared logic

module freq_detect_v3_0 #
    (
        // Users to add parameters here
        parameter integer FFT_WINDOW_SIZE = 1024,
        parameter integer FFT_SAMPLE_SIZE = 32,
        localparam HPS_NUMBER_OF_TERMS = 3,
        // product of 3 squared magnitutes corresponding to 3 FFT terms used in calculations
        localparam integer HPS_PRODUCT_SIZE = FFT_SAMPLE_SIZE*HPS_NUMBER_OF_TERMS, 

        // User parameters ends
        // Do not modify the parameters beyond this line


        // Parameters of Axi Slave Bus Interface S00_AXIS
        localparam integer C_S00_AXIS_TDATA_WIDTH    = FFT_SAMPLE_SIZE * HPS_NUMBER_OF_TERMS,

        // Parameters of Axi Master Bus Interface M00_AXIS
        localparam integer C_M00_AXIS_TDATA_WIDTH    = $clog2(FFT_WINDOW_SIZE)
    )
    (
        // Users to add ports here
        input wire clk,
        input wire resetn,
        // User ports ends
        // Do not modify the ports beyond this line

        
        // Ports of Axi Slave Bus Interface S00_AXIS

        output wire  s00_axis_tready,
        input wire [C_S00_AXIS_TDATA_WIDTH-1 : 0] s00_axis_tdata,
        input wire  s00_axis_tlast,
        input wire  s00_axis_tvalid,

        // Ports of Axi Master Bus Interface M00_AXIS
        output wire  m00_axis_tvalid,
        output wire [C_M00_AXIS_TDATA_WIDTH-1 : 0] m00_axis_tdata,
        input wire  m00_axis_tready
    );
    
    reg m00_axis_tvalid_reg;
    reg [C_M00_AXIS_TDATA_WIDTH-1 : 0] m00_axis_tdata_reg;
    reg s00_axis_tready_reg;
    
    assign m00_axis_tvalid = m00_axis_tvalid_reg;
    assign m00_axis_tdata = m00_axis_tdata_reg;
    assign s00_axis_tready = s00_axis_tready_reg;
    
    
    typedef logic [FFT_SAMPLE_SIZE-1:0] fft_sample;
    fft_sample [HPS_NUMBER_OF_TERMS-1:0] s00_axis_tdata_formated;
    assign s00_axis_tdata_formated = s00_axis_tdata;
    
    // variables for pipelined stages
    // stage 1
    typedef logic [FFT_SAMPLE_SIZE-1:0] sample_squared_amplitude;
    sample_squared_amplitude [HPS_NUMBER_OF_TERMS-1:0] squared_amplitudes;
    logic valid_stage_1;
    logic last_stage_1;
    
    // stage 2
    logic [FFT_SAMPLE_SIZE*2-1:0] product_of_first_two_ampl;
    logic valid_stage_2;
    logic last_stage_2;
    
    // combinational between stage 2 and 3
    logic [HPS_PRODUCT_SIZE-1:0] current_hps_value;
    assign current_hps_value = product_of_first_two_ampl * squared_amplitudes[2];
    
    // stage 3
    logic [C_M00_AXIS_TDATA_WIDTH-1:0] current_hps_index;
    logic [HPS_PRODUCT_SIZE-1:0] max_hps_value_tmp;
    logic [C_M00_AXIS_TDATA_WIDTH-1:0] max_hps_index_tmp; // this would keep track of the max hps product index so far, when all data is processed, this would go to the ouput 
    

    always @(posedge clk)begin
        if (resetn==0) begin
            // slave resets
            s00_axis_tready_reg <= 1'b0;
            
            // stage 1
            squared_amplitudes <= {HPS_NUMBER_OF_TERMS*FFT_SAMPLE_SIZE{1'b0}};
            valid_stage_1 <= 1'b0;
            last_stage_1 <= 1'b0;
    
            // stage 2
            product_of_first_two_ampl <= {FFT_SAMPLE_SIZE*2{1'b0}};
            valid_stage_2 <= 1'b0;
            last_stage_2 <= 1'b0;
            
            // stage 3
            current_hps_index <= {C_M00_AXIS_TDATA_WIDTH{1'b0}};
            max_hps_value_tmp <= {HPS_PRODUCT_SIZE{1'b0}};
            max_hps_index_tmp <= {C_M00_AXIS_TDATA_WIDTH{1'b0}};
            
            // master resets
            m00_axis_tvalid_reg <= 0;
            m00_axis_tdata_reg <= 0;

            
        end else begin
            s00_axis_tready_reg <= 1'b1; // in our current design, the module is always ready to receive data
            
            // stage 1
            valid_stage_1 <= s00_axis_tvalid & s00_axis_tready_reg;
            last_stage_1 <= s00_axis_tlast;
            for (int i=0; i < HPS_NUMBER_OF_TERMS; i = i+1) begin
                squared_amplitudes[i] <= s00_axis_tdata_formated[i][FFT_SAMPLE_SIZE/2-1:0] * s00_axis_tdata_formated[i][FFT_SAMPLE_SIZE/2-1:0] +
                    s00_axis_tdata_formated[i][FFT_SAMPLE_SIZE-1:FFT_SAMPLE_SIZE/2] * s00_axis_tdata_formated[i][FFT_SAMPLE_SIZE-1:FFT_SAMPLE_SIZE/2];                            
            end
            
            // stage 2
            product_of_first_two_ampl <= squared_amplitudes[0] * squared_amplitudes[1];
            valid_stage_2 <= valid_stage_1;
            last_stage_2 <= last_stage_1;
            
            // stage 3
            if (valid_stage_2 == 1'b1) begin
            
                if (last_stage_2 == 1'b1) begin
                
                    m00_axis_tvalid_reg <= 1'b1;
                    if (current_hps_value > max_hps_value_tmp) begin
                        m00_axis_tdata_reg <= current_hps_index;
                    end else begin
                        m00_axis_tdata_reg <=  max_hps_index_tmp;
                    end
                    max_hps_value_tmp <= {HPS_PRODUCT_SIZE{1'b0}};
                    max_hps_index_tmp <= {C_M00_AXIS_TDATA_WIDTH{1'b0}};
                    current_hps_index <= {C_M00_AXIS_TDATA_WIDTH{1'b0}};
                    
                end else begin
                
                    if(current_hps_value > max_hps_value_tmp) begin
                        max_hps_value_tmp <= current_hps_value;
                        max_hps_index_tmp <= current_hps_index;
                    end
                        current_hps_index <= current_hps_index + 1'b1;
                end
                
            end else begin
                m00_axis_tvalid_reg <= 1'b0;
            end
            
        end
    end
    
endmodule


`default_nettype wire //important to put at end (makes it work nicer with IP modules)