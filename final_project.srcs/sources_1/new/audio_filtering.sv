///////////////////////////////////////////////////////////////////////////////
//
// Record/playback
//
///////////////////////////////////////////////////////////////////////////////

module recorder(
  input wire clk_in,              // 100MHz system clock
  input wire rst_in,               // 1 to reset to initial state
  input wire ready_in,             // 1 when data is available
  input wire filter_in,            // 1 when using low-pass filter for audio input
  input wire signed[BIT_DEPTH-1:0] mic_in,         // PCM data from mic
  output logic [ADDRESS_BIT_WIDTH-1:0] write_addr,
  output logic window_finish,
  output logic [BIT_DEPTH-1:0] data_out
);                               

    parameter WINDOW_SIZE = 512;
    parameter WINDOW_COUNT = 4;
    parameter MAX_ADDR = 2048;
    parameter BIT_DEPTH = 16;
    parameter ADDRESS_BIT_WIDTH = 11; 
    parameter COUNT = 3'd6; // downsampling coefficient         
                  
    logic signed [BIT_DEPTH-1:0] aud_in_filter_input;
    logic signed [BIT_DEPTH-1+10:0] aud_in_filter_output;
    fir31 input_low_pass_filter(  .clk_in(clk_in), .rst_in(rst_in), .ready_in(ready_in),
                            .x_in(aud_in_filter_input), .y_out(aud_in_filter_output));             
    
    logic [2:0] count; // used to downsample from 48kHz to 8kHz 
    logic [8:0] sample_counter;      
    
    always_ff @(posedge clk_in)begin
        // Testing audio and microphone
        //data_out = filter_in?tone_440:tone_750; //send tone immediately to output
        //data_out = mic_in; //send microphone input immediately to output
        
        if (rst_in) begin
            count <= 0;
            sample_counter <= 0;
            write_addr <= 0;
        end else if (ready_in) begin
            if (count == COUNT-1) begin
                data_out <= filter_in ? aud_in_filter_output[BIT_DEPTH-1+10:10] : mic_in;
                write_addr <= write_addr + 1; 
                sample_counter <= sample_counter == WINDOW_SIZE-1 ? 0 : sample_counter + 1;
                if (sample_counter == WINDOW_SIZE-1) window_finish <= 1;
            end else window_finish <= 0;
            aud_in_filter_input <= mic_in;
            count <= count < COUNT-1 ? count + 1 : 0;
        end else window_finish <= 0;    
    end                        
endmodule

module playback(
  input wire clk_in,              // 100MHz system clock
  input wire rst_in,               // 1 to reset to initial state
  input wire ready_in,             // 1 when data is available
  input wire filter_in,           // 1 when using low-pass filter for audio output
  output logic [ADDRESS_BIT_WIDTH-1:0] read_addr,
  input wire signed[BIT_DEPTH-1:0] input_data,         // PCM data from mic
  input wire playback_start,
  output logic signed [BIT_DEPTH-1:0] data_out      // PCM data to headphone
);                         

    parameter WINDOW_SIZE = 512;
    parameter WINDOW_COUNT = 4;
    parameter MAX_ADDR = 2048;
    parameter BIT_DEPTH = 16; 
    parameter ADDRESS_BIT_WIDTH = 11;
    parameter COUNT = 3'd6; // downsampling coefficient
                  
    logic signed [BIT_DEPTH-1:0] aud_out_filter_input;
    logic signed [BIT_DEPTH-1+10:0] aud_out_filter_output;
    fir31 output_low_pass_filter(  .clk_in(clk_in), .rst_in(rst_in), .ready_in(ready_in),
                            .x_in(aud_out_filter_input), .y_out(aud_out_filter_output));            
    
    logic [2:0] count; // used to upsample from 8kHz to 48kHz   
    logic processing;                      
    
    always_ff @(posedge clk_in)begin
        if (rst_in) begin
            count <= 0;
            read_addr <= 0;
        end else if (ready_in) begin
            if (count == COUNT-1) begin
                read_addr <= read_addr < MAX_ADDR - 1 ? read_addr + 1 : 0; 
            end
            aud_out_filter_input <= count == COUNT-1 ? input_data : 0;
            data_out <= filter_in ? aud_out_filter_output[BIT_DEPTH-1+10:10] : input_data;
            count <= count < COUNT-1 ? count + 1 : 0;
        end     
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
  input  wire clk_in,rst_in,ready_in,
  input wire signed [BIT_DEPTH-1:0] x_in,
  output logic signed [BIT_DEPTH-1+10:0] y_out
);
    parameter BIT_DEPTH = 16;  

    logic signed [BIT_DEPTH-1:0] sample [31:0]; // 32 element array each 8 bits wide
    logic [4:0] offset; // pointer for the array! (5 bits because 32 elements in above array!) 
    logic [4:0] index, sample_index;
    assign sample_index = offset-1-index;
    logic computing;
    logic signed [BIT_DEPTH-1+10:0] sum;

    logic signed [9:0] coeff_out;
    coeffs31 coeff(.index_in(index),.coeff_out(coeff_out));

    always_ff @(posedge clk_in) begin
        // if (ready_in) y_out <= {x_in,10'd0};  // for now just pass data through
        if (rst_in) begin
            sample[0] <= 0;
            sample[1] <= 0;
            sample[2] <= 0;
            sample[3] <= 0;
            sample[4] <= 0;
            sample[5] <= 0;
            sample[6] <= 0;
            sample[7] <= 0;
            sample[8] <= 0;
            sample[9] <= 0;
            sample[10] <= 0;
            sample[11] <= 0;
            sample[12] <= 0; 
            sample[13] <= 0;
            sample[14] <= 0;
            sample[15] <= 0;
            sample[16] <= 0;
            sample[17] <= 0;
            sample[18] <= 0;
            sample[19] <= 0;
            sample[20] <= 0;
            sample[21] <= 0;
            sample[22] <= 0;
            sample[23] <= 0;
            sample[24] <= 0;
            sample[25] <= 0;
            sample[26] <= 0;
            sample[27] <= 0;
            sample[28] <= 0;
            sample[29] <= 0;
            sample[30] <= 0;
            sample[31] <= 0;
            
            offset <= 0;
            index <= 0;
            computing <= 0;
        end else if (ready_in) begin
            sample[offset] <= x_in;
            index <= 0;
            offset <= offset + 1;
            computing <= 1;
            sum <= 0;
        end else if (computing && index <= 5'd30) begin
            sum <= sum + coeff_out*sample[sample_index];
            index <= index + 1;
        end else if (computing && index > 5'd30) begin
            y_out <= sum;
            computing <= 0;
        end
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
      5'd0:  coeff = 10'sd2;
      5'd1:  coeff = 10'sd2;
      5'd2:  coeff = 10'sd1;
      5'd3:  coeff = 10'sd0;
      5'd4:  coeff = -10'sd3;
      5'd5:  coeff = -10'sd9;
      5'd6:  coeff = -10'sd14;
      5'd7:  coeff = -10'sd17;
      5'd8:  coeff = -10'sd14;
      5'd9:  coeff = 10'sd0;
      5'd10: coeff = 10'sd25;
      5'd11: coeff = 10'sd60;
      5'd12: coeff = 10'sd99;
      5'd13: coeff = 10'sd135;
      5'd14: coeff = 10'sd161;
      5'd15: coeff = 10'sd170;
      5'd16: coeff = 10'sd161;
      5'd17: coeff = 10'sd135;
      5'd18: coeff = 10'sd99;
      5'd19: coeff = 10'sd60;
      5'd20: coeff = 10'sd25;
      5'd21: coeff = 10'sd0;
      5'd22: coeff = -10'sd14;
      5'd23: coeff = -10'sd17;
      5'd24: coeff = -10'sd14;
      5'd25: coeff = -10'sd9;
      5'd26: coeff = -10'sd3;
      5'd27: coeff = 10'sd0;
      5'd28: coeff = 10'sd1;
      5'd29: coeff = 10'sd2;
      5'd30: coeff = 10'sd2;
      default: coeff = 10'hXXX;
    endcase
  end
endmodule