`default_nettype none

module tt_um_example (
    input  wire [7:0] ui_in,    // Inputs: [7:4] Density, [3:0] Flight Speed
    output wire [7:0] uo_out,   // VGA: RRGGBB, HSync, VSync
    input  wire [7:0] uio_in,   // unused
    output wire [7:0] uio_out,  // uio_out[0] is PWM Audio
    output wire [7:0] uio_oe,   // IO direction control
    input  wire       ena,      // always 1
    input  wire       clk,      // clock (25.175 MHz)
    input  wire       rst_n     // reset_n - low to reset
);

    // ------------------------------------------------------------------------
    // Setup & Unused Signals
    // ------------------------------------------------------------------------
    assign uio_oe = 8'b00000001; // Only uio_out[0] is output (PWM audio)
    wire _unused = &{1'b0, uio_in, ena};

    // ------------------------------------------------------------------------
    // Registers
    // ------------------------------------------------------------------------
    reg [9:0]  h_count;
    reg [9:0]  v_count;
    reg [15:0] x_offset;
    reg [15:0] y_offset;
    reg [18:0] voice1, voice2, voice3, voice4;
    reg [7:0]  uo_out_reg;
    reg [7:0]  uio_out_reg;

    assign uo_out = uo_out_reg;
    assign uio_out = uio_out_reg;

    // ------------------------------------------------------------------------
    // VGA Timing Generator (640x480 @ 60Hz)
    // ------------------------------------------------------------------------
    wire h_end = (h_count == 799);
    wire v_end = (v_count == 524);

    always @(posedge clk) begin
        if (!rst_n) begin
            h_count <= 0;
            v_count <= 0;
        end else begin
            if (h_end) begin
                h_count <= 0;
                if (v_end) v_count <= 0;
                else       v_count <= v_count + 1;
            end else begin
                h_count <= h_count + 1;
            end
        end
    end

    wire h_sync_active = (h_count >= (640 + 16)) && (h_count < (640 + 16 + 96));
    wire v_sync_active = (v_count >= (480 + 10)) && (v_count < (480 + 10 + 2));
    
    wire h_sync = ~h_sync_active; // Active low
    wire v_sync = ~v_sync_active; // Active low
    wire display_en = (h_count < 640) && (v_count < 480);

    // ------------------------------------------------------------------------
    // Flight Offset Logic (X/Y scrolling)
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            x_offset <= 0;
            y_offset <= 0;
        end else if (h_end && v_end) begin
            // Scroll flight space smoothly once per frame. 
            // Added '+ 1' so it moves even when ui_in == 0
            x_offset <= x_offset + {12'b0, ui_in[3:0]} + 16'd1;
            y_offset <= y_offset + {13'b0, ui_in[3:1]} + 16'd1; 
        end
    end

    // ------------------------------------------------------------------------
    // Sierpinski Nebula Generation
    // ------------------------------------------------------------------------
    wire [11:0] f_x = h_count + x_offset[11:0];
    wire [11:0] f_y = v_count + y_offset[11:0];
    wire [11:0] fractal = f_x & f_y;

    wire[7:0] f_mask_core = {~ui_in[7:6], 2'b11, ~ui_in[5:4], 2'b11};
    wire[7:0] f_mask_fringe = f_mask_core & 8'b0111_0111; 

    wire nebula_core   = ((fractal[9:2] & f_mask_core) == 0);
    wire nebula_fringe = ((fractal[9:2] & f_mask_fringe) == 0);

    // ------------------------------------------------------------------------
    // Spatial Hash Starfield
    // ------------------------------------------------------------------------
    wire [11:0] st_x = h_count + x_offset[12:1]; 
    wire[11:0] st_y = v_count + y_offset[12:1];
    wire[11:0] hash_val = (st_x ^ {st_y[5:0], st_y[11:6]}) + st_y;
    
    wire star_pixel  = (hash_val[11:3] == 9'h1FF); 
    wire twinkle     = hash_val[0] ^ x_offset[4];  
    wire star_active = star_pixel & twinkle;

    // ------------------------------------------------------------------------
    // Color Palette Mixing
    // ------------------------------------------------------------------------
    wire [1:0] r_c = star_active ? 2'b11 : (nebula_core ? 2'b11 : (nebula_fringe ? 2'b01 : 2'b00));
    wire [1:0] g_c = star_active ? 2'b11 : (nebula_core ? 2'b01 : (nebula_fringe ? 2'b00 : 2'b00));
    wire [1:0] b_c = star_active ? 2'b11 : (nebula_core ? 2'b11 : (nebula_fringe ? 2'b10 : 2'b01));

    // ------------------------------------------------------------------------
    // Audio PWM Square Wave Synthesis (4-voice Chiptune)
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            voice1 <= 0; voice2 <= 0; voice3 <= 0; voice4 <= 0;
        end else begin
            voice1 <= voice1 + 19'd5  + {15'b0, x_offset[11:8]};
            voice2 <= voice2 + 19'd7  + {15'b0, x_offset[12:9]};
            voice3 <= voice3 + 19'd10 + {15'b0, x_offset[13:10]};
            voice4 <= voice4 + 19'd12 + {15'b0, x_offset[10:7]};
        end
    end
    
    wire audio_mix = voice1[18] ^ voice2[18] ^ (voice3[18] & voice4[18]);

    // ------------------------------------------------------------------------
    // Output Registration
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            uo_out_reg  <= 8'b00000000;
            uio_out_reg <= 8'b00000000;
        end else begin
            // CORRECTED TT VGA PMOD Mapping
            // [0]=R1(MSB), [4]=R0(LSB) | [1]=G1, [5]=G0 | [2]=B1,[6]=B0
            if (display_en) begin
                uo_out_reg[0] <= r_c[1]; 
                uo_out_reg[4] <= r_c[0]; 
                uo_out_reg[1] <= g_c[1]; 
                uo_out_reg[5] <= g_c[0]; 
                uo_out_reg[2] <= b_c[1]; 
                uo_out_reg[6] <= b_c[0]; 
            end else begin
                uo_out_reg[0] <= 1'b0;
                uo_out_reg[4] <= 1'b0;
                uo_out_reg[1] <= 1'b0;
                uo_out_reg[5] <= 1'b0;
                uo_out_reg[2] <= 1'b0;
                uo_out_reg[6] <= 1'b0;
            end
            
            uo_out_reg[7] <= h_sync; // Correct TT HSYNC Mapping
            uo_out_reg[3] <= v_sync; // Correct TT VSYNC Mapping

            // Audio Output
            uio_out_reg[0]   <= audio_mix;
            uio_out_reg[7:1] <= 7'b0000000;
        end
    end

endmodule
