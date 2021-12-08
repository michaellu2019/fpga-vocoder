//Volume Control
module volume_control (input wire [2:0] vol_in, input wire signed [BIT_DEPTH-1:0] signal_in, output logic signed[BIT_DEPTH-1:0] signal_out);
    parameter BIT_DEPTH = 16;  
    logic [2:0] shift;
    assign shift = 3'd7 - vol_in;
    assign signal_out = signal_in>>>shift;
endmodule

//PWM generator for audio generation!
module pwm (input wire clk_in, input wire rst_in, input wire [BIT_DEPTH-1:0] level_in, output logic pwm_out);
    parameter BIT_DEPTH = 12;
    logic [BIT_DEPTH-1:0] count;
    assign pwm_out = count<level_in;
    always_ff @(posedge clk_in)begin
        if (rst_in)begin
            count <= 12'b0;
        end else begin
            count <= count+12'b1;
        end
    end
endmodule