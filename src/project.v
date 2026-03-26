`default_nettype none

module tt_um_nebula (
    input  wire [7:0] ui_in,    // Inputs: [7:4] Density, [3:0] Flight Speed
    output wire [7:0] uo_out,   // VGA: RRGGBB, HSync, VSync
    input  wire [7:0] uio_in,   // unused
    output wire[7:0] uio_out,  // uio_out[7] is Audio
    output wire[7:0] uio_oe,   // IO direction control
    input  wire       ena,      // always 1
    input  wire       clk,      // clock (25.175 MHz)
    input  wire       rst_n     // reset_n - low to reset
);

    // ------------------------------------------------------------------------
    // Setup & IO Direction
    // ------------------------------------------------------------------------
    assign uio_oe = 8'b10000000; // uio_out[7] output for Web Simulator audio
    wire _unused = &{1'b0, uio_in, ena};

    // ------------------------------------------------------------------------
    // Registers
    // ------------------------------------------------------------------------
    reg [9:0]  h_count;
    reg [9:0]  v_count;
    reg [15:0] x_offset;
    reg [15:0] y_offset;
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
            x_offset <= x_offset + {12'b0, ui_in[3:0]} + 16'd1;
            y_offset <= y_offset + {13'b0, ui_in[3:1]} + 16'd1; 
        end
    end

    // ------------------------------------------------------------------------
    // Sierpinski Nebula + Spatial Starfield
    // ------------------------------------------------------------------------
    wire [11:0] f_x = h_count + x_offset[11:0];
    wire [11:0] f_y = v_count + y_offset[11:0];
    wire [11:0] fractal = f_x & f_y;

    wire [7:0] f_mask_core = {~ui_in[7:6], 2'b11, ~ui_in[5:4], 2'b11};
    wire [7:0] f_mask_fringe = f_mask_core & 8'b0111_0111; 

    wire nebula_core   = ((fractal[9:2] & f_mask_core) == 0);
    wire nebula_fringe = ((fractal[9:2] & f_mask_fringe) == 0);

    wire [11:0] st_x = h_count + x_offset[12:1]; 
    wire [11:0] st_y = v_count + y_offset[12:1];
    wire [11:0] hash_val = (st_x ^ {st_y[5:0], st_y[11:6]}) + st_y;
    
    wire star_pixel  = (hash_val[11:3] == 9'h1FF); 
    wire twinkle     = hash_val[0] ^ x_offset[4];  
    wire star_active = star_pixel & twinkle;

    wire [1:0] r_c = star_active ? 2'b11 : (nebula_core ? 2'b11 : (nebula_fringe ? 2'b01 : 2'b00));
    wire [1:0] g_c = star_active ? 2'b11 : (nebula_core ? 2'b01 : (nebula_fringe ? 2'b00 : 2'b00));
    wire [1:0] b_c = star_active ? 2'b11 : (nebula_core ? 2'b11 : (nebula_fringe ? 2'b10 : 2'b01));

    // ------------------------------------------------------------------------
    // 🎵 Synthwave Quantized Arpeggiator (C Minor Pentatonic)
    // ------------------------------------------------------------------------
    reg [15:0] arp_phase;
    reg[15:0] bass_phase;

    // 1. Sequencer Lookups: Tie the notes to the visual flight offset
    wire [2:0] arp_step = x_offset[8:6]; // Arpeggio runs fast
    reg [10:0] arp_inc;
    always @(*) begin
        case (arp_step)
            3'b000: arp_inc = 11'd544;  // C4
            3'b001: arp_inc = 11'd648;  // D#4
            3'b010: arp_inc = 11'd816;  // G4
            3'b011: arp_inc = 11'd1089; // C5
            3'b100: arp_inc = 11'd1295; // D#5
            3'b101: arp_inc = 11'd1089; // C5
            3'b110: arp_inc = 11'd816;  // G4
            3'b111: arp_inc = 11'd648;  // D#4
        endcase
    end

    wire [1:0] bass_step = x_offset[11:10]; // Bass runs 8x slower
    reg [7:0] bass_inc;
    always @(*) begin
        case (bass_step)
            2'b00: bass_inc = 8'd136; // C2
            2'b01: bass_inc = 8'd136; // C2 (Hold)
            2'b10: bass_inc = 8'd181; // F2
            2'b11: bass_inc = 8'd204; // G2
        endcase
    end

    // 2. Audio Clocking (31.468 kHz Web Simulator Sample Rate)
    always @(posedge clk) begin
        if (!rst_n) begin
            arp_phase <= 0;
            bass_phase <= 0;
        end else if (h_end) begin 
            arp_phase  <= arp_phase  + {5'b0, arp_inc};
            bass_phase <= bass_phase + {8'b0, bass_inc};
        end
    end
    
    // 3. Rhythmic Gating / Envelopes (Creates the Staccato Synth Effect)
    // Using upper bits of offset to rhythmically mute the square waves 25% of the time.
    wire arp_gate  = (x_offset[5:4] != 2'b11); 
    wire bass_gate = (x_offset[9:8] != 2'b11); 

    // 4. Pure Logic Mix (OR creates a thick 2-oscillator synthesizer chord without static)
    wire sound = (arp_phase[15] & arp_gate) | (bass_phase[15] & bass_gate);

    // ------------------------------------------------------------------------
    // Output Registration
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            uo_out_reg  <= 8'b00000000;
            uio_out_reg <= 8'b00000000;
        end else begin
            if (display_en) begin
                uo_out_reg[0] <= r_c[1]; uo_out_reg[4] <= r_c[0]; 
                uo_out_reg[1] <= g_c[1]; uo_out_reg[5] <= g_c[0]; 
                uo_out_reg[2] <= b_c[1]; uo_out_reg[6] <= b_c[0]; 
            end else begin
                uo_out_reg[0] <= 1'b0; uo_out_reg[4] <= 1'b0;
                uo_out_reg[1] <= 1'b0; uo_out_reg[5] <= 1'b0;
                uo_out_reg[2] <= 1'b0; uo_out_reg[6] <= 1'b0;
            end
            
            uo_out_reg[7] <= h_sync; 
            uo_out_reg[3] <= v_sync; 

            // Audio output on Bit 7
            uio_out_reg[7]   <= sound;
            uio_out_reg[6:0] <= 7'b0000000;
        end
    end

endmodule
