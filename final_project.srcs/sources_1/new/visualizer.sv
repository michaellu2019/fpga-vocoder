`default_nettype none

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
            end else begin
                rgb <= 12'b0000_0000_0000;
            end
        end else if (visualize_mode == 10'd1) begin 
            // draw the spectrogram
            // access the correct memory location in bram for the frequency
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

`default_nettype wire