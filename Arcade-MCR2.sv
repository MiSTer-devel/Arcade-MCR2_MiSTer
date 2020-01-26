//============================================================================
//  Arcade: MCR2
//
//  Port to MiSTer
//  Copyright (C) 2019 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        VGA_CLK,

	//Multiple resolutions are supported using different VGA_CE rates.
	//Must be based on CLK_VIDEO
	output        VGA_CE,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,

	//Base video clock. Usually equals to CLK_SYS.
	output        HDMI_CLK,

	//Multiple resolutions are supported using different HDMI_CE rates.
	//Must be based on CLK_VIDEO
	output        HDMI_CE,

	output  [7:0] HDMI_R,
	output  [7:0] HDMI_G,
	output  [7:0] HDMI_B,
	output        HDMI_HS,
	output        HDMI_VS,
	output        HDMI_DE,   // = ~(VBlank | HBlank)
	output  [1:0] HDMI_SL,   // scanlines fx

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] HDMI_ARX,
	output  [7:0] HDMI_ARY,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,    // 1 - signed audio samples, 0 - unsigned

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE, 

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT
);

assign VGA_F1    = 0;
assign USER_OUT  = '1;
assign LED_USER  = rom_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;

assign HDMI_ARX = status[1] ? 8'd16 : 8'd21;
assign HDMI_ARY = status[1] ? 8'd9  : 8'd20;

`include "build_id.v" 
localparam CONF_STR = {
	"A.MCR2;;",
	"H0O1,Aspect Ratio,Original,Wide;",
	"H1H0O2,Orientation,Vert,Horz;",
	"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"H1O6,Control,Mode 1,Mode 2;",
	"H1-;",
	//"H2O6,Control,Digital,Analog;",
	//"H2-;",
	"DIP;",
	"-;",
	//"O6,Service,Off,On;",
	//"OD,Video Mode,15KHz,31KHz;",
	"-;",
	"R0,Reset;",
	"J1,Fire A,Fire B,Fire C,Fire D,Fire E, Fire F,Start,Coin;",
	"jn,A,B,X,Y,L,R,Start,Select;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys,clk_80M;
wire clk_mem = clk_80M;
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys), // 40M
	.outclk_1(clk_80M), // 80M
	.locked(pll_locked)
);

///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire        direct_video;

wire [15:0] audio_l, audio_r;


wire [10:0] ps2_key;

wire [15:0] joy1, joy2, joy3, joy4;
wire [15:0] joy = joy1 | joy2 | joy3 | joy4;
wire [15:0] joy1a, joy2a, joy3a, joy4a;

wire signed [8:0] mouse_x;
wire signed [8:0] mouse_y;
wire        mouse_strobe;
reg   [7:0] mouse_flags;

wire       rotate  = 0;//status[2];

wire [21:0] gamma_bus;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.buttons(buttons),
	.status(status),
	.status_menumask({orientation[0],direct_video}),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_index(ioctl_index),

	.joystick_0(joy1),
	.joystick_1(joy2),
	.joystick_2(joy3),
	.joystick_3(joy4),

	.joystick_analog_0(joy1a),
	.joystick_analog_1(joy2a),
	.joystick_analog_2(joy3a),
	.joystick_analog_3(joy4a),

	.ps2_key(ps2_key)
);

reg mod_shollow    = 0;
reg mod_tron       = 0;
reg mod_twotiger   = 0;
reg mod_wacko      = 0;
reg mod_kroozr     = 0;
reg mod_domino     = 0;

always @(posedge clk_sys) begin
	reg [7:0] mod = 0;
	if (ioctl_wr & (ioctl_index==1)) mod <= ioctl_dout;

        mod_shollow    <= ( mod == 0 );
        mod_tron       <= ( mod == 1 );
        mod_twotiger   <= ( mod == 2 );
        mod_wacko      <= ( mod == 3 );
        mod_kroozr     <= ( mod == 4 );
        mod_domino     <= ( mod == 5 );
end

// load the DIPS
reg [7:0] sw[8];
always @(posedge clk_sys) if (ioctl_wr && (ioctl_index==254) && !ioctl_addr[24:3]) sw[ioctl_addr[2:0]] <= ioctl_dout;


wire       pressed = ps2_key[9];
wire [7:0] code    = ps2_key[7:0];
always @(posedge clk_sys) begin
	reg old_state;
	old_state <= ps2_key[10];
	
	if(old_state != ps2_key[10]) begin
		casex(code)
			'h75: btn_up            <= pressed; // up
			'h72: btn_down          <= pressed; // down
			'h6B: btn_left          <= pressed; // left
			'h74: btn_right         <= pressed; // right
			'h76: btn_coin1         <= pressed; // ESC
			'h05: btn_start1        <= pressed; // F1
			'h06: btn_start2        <= pressed; // F2
			//'h04: btn_start3        <= pressed; // F3
			//'h0C: btn_start4        <= pressed; // F4
			//'h12: btn_fireD         <= pressed; // l-shift
			//'h14: btn_fireC         <= pressed; // ctrl
			'h11: btn_fireB         <= pressed; // alt
			'h29: btn_fireA         <= pressed; // Space
			// JPAC/IPAC/MAME Style Codes
			'h16: btn_start1        <= pressed; // 1
			'h1E: btn_start2        <= pressed; // 2
			//'h26: btn_start3        <= pressed; // 3
			//'h25: btn_start4        <= pressed; // 4
			'h2E: btn_coin1         <= pressed; // 5
			'h36: btn_coin2         <= pressed; // 6
			//'h3D: btn_coin3         <= pressed; // 7
			//'h3E: btn_coin4         <= pressed; // 8
			'h2D: btn_up2           <= pressed; // R
			'h2B: btn_down2         <= pressed; // F
			'h23: btn_left2         <= pressed; // D
			'h34: btn_right2        <= pressed; // G
			'h1C: btn_fire2A        <= pressed; // A
			'h1B: btn_fire2B        <= pressed; // S
			//'h21: btn_fire2C        <= pressed; // Q
			//'h1D: btn_fire2D        <= pressed; // W
			//'h1D: btn_fire2E        <= pressed; // W
			//'h1D: btn_fire2F        <= pressed; // W
			//'h1D: btn_tilt <= pressed; // W
		endcase
	end
end

reg btn_tilt   = 0;
reg btn_left   = 0;
reg btn_right  = 0;
reg btn_down   = 0;
reg btn_up     = 0;
reg btn_fireA  = 0;
reg btn_fireB  = 0;
//reg btn_fireC  = 0;
//reg btn_fireD  = 0;
//reg btn_fireE  = 0;
//reg btn_fireF  = 0;
reg btn_coin1  = 0;
reg btn_coin2  = 0;
//reg btn_coin3  = 0;
//reg btn_coin4  = 0;
reg btn_start1 = 0;
reg btn_start2 = 0;
//reg btn_start3 = 0;
//reg btn_start4 = 0;
reg btn_up2    = 0;
reg btn_down2  = 0;
reg btn_left2  = 0;
reg btn_right2 = 0;
reg btn_fire2A = 0;
reg btn_fire2B = 0;
//reg btn_fire2C = 0;
//reg btn_fire2D = 0;
//reg btn_fire2E = 0;
//reg btn_fire2F = 0;

reg service;
//assign service = status[6]; //needs changed

// Generic controls - make a module from this?

wire m_tilt;

wire m_coin1   = btn_coin1 | joy1[11];
wire m_start1  = btn_start1 | joy1[10];
wire m_up1     = btn_up     | joy1[3];
wire m_down1   = btn_down   | joy1[2];
wire m_left1   = btn_left   | joy1[1];
wire m_right1  = btn_right  | joy1[0];
wire m_fire1a  = btn_fireA  | joy1[4];
wire m_fire1b  = btn_fireB  | joy1[5];
//wire m_fire1c  = btn_fireC  | joy1[6];
//wire m_fire1d  = btn_fireD  | joy1[7];
//wire m_fire1e  = btn_fireE  | joy1[8];
//wire m_fire1f  = btn_fireF  | joy1[9];

wire m_coin2   = btn_coin2 | joy2[11];
wire m_start2  = btn_start2 | joy2[10];
wire m_left2   = btn_left2  | joy2[1];
wire m_right2  = btn_right2 | joy2[0];
wire m_up2     = btn_up2    | joy2[3];
wire m_down2   = btn_down2  | joy2[2];
wire m_fire2a  = btn_fire2A | joy2[4];
wire m_fire2b  = btn_fire2B | joy2[5];
//wire m_fire2c  = btn_fire2C | joy2[6];
//wire m_fire2d  = btn_fire2D | joy2[7];
//wire m_fire2e  = btn_fire2E | joy2[8];
//wire m_fire2f  = btn_fire2F | joy2[9];

//wire m_coin3   = joy3[9];
wire m_start3  = joy3[8];
//wire m_left3   = joy3[1];
//wire m_right3  = joy3[0];
//wire m_up3     = joy3[3];
//wire m_down3   = joy3[2];
//wire m_fire3a  = joy3[4];
//wire m_fire3b  = joy3[5];
//wire m_fire3c  = joy3[6];
//wire m_fire3d  = joy3[7];

//wire m_coin4   = 0;
//wire m_start4  = joy4[8];
//wire m_left4   = joy4[1];
//wire m_right4  = joy4[0];
//wire m_up4     = joy4[3];
//wire m_down4   = joy4[2];
//wire m_fire4a  = joy4[4];
//wire m_fire4b  = joy4[5];
//wire m_fire4c  = joy4[6];
//wire m_fire4d  = joy4[7];

reg        oneplayer;
reg  [1:0] orientation; //left/right / portrait/landscape
reg  [7:0] input_0;
reg  [7:0] input_1;
reg  [7:0] input_2;
reg  [7:0] input_3;
reg  [7:0] input_4;



// Game specific sound board/DIP/input settings
always @(*) begin

	orientation = 2'b00;
	input_0 = 8'hff;
	input_1 = 8'hff;
	input_2 = 8'hff;
	input_3 = sw[0];
	input_4 = 8'hff;


	if (mod_shollow) begin
                orientation = 2'b00;
                input_0 = ~{ service, 1'b0, m_tilt, 1'b0, m_start2, m_start1, m_coin2, m_coin1 };
                input_1 = ~{ m_fire2a, m_fire2b, m_right2, m_left2, m_fire1a, m_fire1b, m_right1, m_left1 };
                input_2 = 8'hFF;
                input_3 = ~{ 8'b00000010 };
        end else if (mod_tron) begin
                orientation = 2'b00;
                oneplayer = 1'b0;
                input_0 = ~{ service, 1'b0, m_tilt, m_fire1a, m_start2, m_start1, m_coin2, m_coin1 };
                input_1 = ~{ 1'b0, spin_angle2 };
                input_2 = ~{ m_down1, m_up1, m_right1, m_left1, m_down1, m_up1, m_right1, m_left1 };
                input_3 = ~{ m_fire1a, 7'b00000010 };
                input_4 = ~{ 1'b0, spin_angle2 };
        end else if (mod_twotiger) begin
                orientation = 2'b01;
                oneplayer = 1'b0;
                input_0 = ~{ service, 1'b0, m_tilt, m_start3, m_start2, m_start1, m_coin2, m_coin1 };
                input_1 = ~{ 1'b0, spin_angle1 };
                input_2 = ~{ 4'b0000, m_fire2b, m_fire2a, m_fire1b, m_fire1a };
                input_3 = 8'hFF;
                input_4 = ~{ 1'b0, spin_angle2 };
        end else if (mod_wacko) begin
                orientation = 2'b01;
                input_0 = ~{ service, 1'b0, m_tilt, 1'b0, m_start2, m_start1, m_coin2, m_coin1 };
                input_1 = x_pos[10:3];
                input_2 = y_pos[10:3];
                input_3 = ~{ 8'b01000000 };
                input_4 = ~{ m_up2, m_down2, m_left2, m_right2, m_up1, m_down1, m_left1, m_right1 };
        end else if (mod_kroozr) begin
                orientation = 2'b01;
                input_0 = ~{ service, 1'b0, m_tilt, m_fire1a | mouse_btns[0], m_start2, m_start1, m_coin2, m_coin1 };
                input_1 = ~{ (m_fire1b | mouse_btns[1]), spin_angle1[6], 3'b111, spin_angle1[5:3] };
                input_2 = { x_pos_kroozr[9], x_pos_kroozr[9], x_pos_kroozr[7:2] };
                input_3 = ~{ 8'b01000000 };
                input_4 = { y_pos_kroozr[9], y_pos_kroozr[9], y_pos_kroozr[7:2] };
        end else if (mod_domino) begin
                orientation = 2'b01;
                input_0 = ~{ service, 1'b0, m_tilt, m_fire1a, m_start2, m_start1, m_coin2, m_coin1 };
                input_1 = ~{ 4'b0000, m_down1, m_up1, m_right1, m_left1 };
                input_2 = ~{ 3'b000, m_fire2a, m_down2, m_up2, m_right2, m_left2 };
                input_3 = ~{ 8'b01000000 };
	end
end


wire rom_download = ioctl_download && !ioctl_index;

wire [15:0] rom_addr;
wire [15:0] rom_do;
wire [13:0] snd_addr;
wire [15:0] snd_do;

wire        ioctl_download;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;

/* ROM structure
00000 - 0BFFF  48k CPU1
0C000 - 0FFFF  16k CPU2
10000 - 13FFF  16k GFX1
14000 - 1BFFF  32k GFX2
*/
reg port1_req, port2_req;
sdram sdram(
        .*,
        .init_n        ( pll_locked ),
        //.clk           ( clk_sys ),
        .clk           ( clk_mem ),

	// port1 used for main CPU
        .port1_req     ( port1_req ),
        .port1_ack     ( ),
        .port1_a       ( ioctl_addr[23:1] ),
        .port1_ds      ( {ioctl_addr[0], ~ioctl_addr[0]} ),
        .port1_we      ( rom_download ),
        .port1_d       ( {ioctl_dout, ioctl_dout} ),
        .port1_q       ( ),

        .cpu1_addr     ( rom_download ? 15'h7fff : rom_addr[15:1] ),
        .cpu1_q        ( rom_do ),

        // port2 for sound board
        .port2_req     ( port2_req ),
        .port2_ack     ( ),
        .port2_a       ( ioctl_addr[23:1] - 16'h6000 ),
        .port2_ds      ( {ioctl_addr[0], ~ioctl_addr[0]} ),
        .port2_we      ( rom_download ),
        .port2_d       ( {ioctl_dout, ioctl_dout} ),
        .port2_q       ( ),

        .snd_addr      ( rom_download ? 15'h7fff : {2'b00, snd_addr[13:1]} ),
        .snd_q         ( snd_do )
);


always @(posedge clk_sys) begin
        reg        ioctl_wr_last = 0;

        ioctl_wr_last <= ioctl_wr && !ioctl_index;
        if (rom_download) begin
                if (~ioctl_wr_last && ioctl_wr && !ioctl_index) begin
                        port1_req <= ~port1_req;
                        port2_req <= ~port2_req;
                end
        end
end

reg reset = 1;
reg rom_loaded = 0;
always @(posedge clk_sys) begin
        reg ioctl_downlD;
        ioctl_downlD <= rom_download;

        if (ioctl_downlD & ~rom_download) rom_loaded <= 1;
        reset <= status[0] | buttons[1] | rom_download | ~rom_loaded;
end

satans_hollow satans_hollow(
        .clock_40(clk_sys),
        .reset(reset),
        .video_r(r),
        .video_g(g),
        .video_b(b),
        .video_vblank(vblank),
        .video_hblank(hblank),
        .video_hs(hs),
        .video_vs(vs),
        .video_csync(cs),
        .video_ce(ce_pix),
        .tv15Khz_mode(1'b1),
        //.tv15Khz_mode(~status[13]),
        .separate_audio(1'b0),
        .audio_out_l(audio_l),
        .audio_out_r(audio_r),

        .input_0      ( input_0),
        .input_1      ( input_1),
        .input_2      ( input_2),
        .input_3      ( input_3),
        .input_4      ( input_4),

        .cpu_rom_addr ( rom_addr),
        .cpu_rom_do   ( rom_addr[0] ? rom_do[15:8] : rom_do[7:0] ),
        .snd_rom_addr ( snd_addr),
        .snd_rom_do   ( snd_addr[0] ? snd_do[15:8] : snd_do[7:0] ),

        .dl_addr      ( ioctl_addr[16:0]),
        .dl_wr        ( ioctl_wr & !ioctl_index),
        .dl_data      ( ioctl_dout)
);
wire ce_pix;
wire hs, vs, cs;
wire hblank, vblank;
wire HSync, VSync;
wire [2:0] r,g,b;
/*
reg ce_pix;
always @(posedge clk_sys) begin
        reg [2:0] div;

        div <= div + 1'd1;
        ce_pix <= !div;
end
*/
wire no_rotate = status[2] | direct_video | orientation[0];

arcade_video #(512,240,9) arcade_video
//arcade_video #(512,480,9) arcade_video
(
	.*,
	//.ce_pix(status[13] ? ce_pix_old: ce_pix),
	//.ce_pix(status[13] ? ce_pix_old: ce_pix),
	.clk_video(clk_sys),
	.RGB_in({r,g,b}),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(hs),
	.VSync(vs),

	.rotate_ccw(orientation[1]),
	.fx(status[5:3])
);


assign AUDIO_L = { audio_l };
assign AUDIO_R = { audio_r };
assign AUDIO_S = 0;

// Mouse controls for Wacko
reg signed [10:0] x_pos;
reg signed [10:0] y_pos;

always @(posedge clk_sys) begin
        if (mouse_strobe) begin
                if (rotate) begin
                        x_pos <= x_pos - mouse_y;
                        y_pos <= y_pos + mouse_x;
                end else begin
                        x_pos <= x_pos + mouse_x;
                        y_pos <= y_pos + mouse_y;
                end
        end
end

// Controls for Kozmik Krooz'r
reg  signed [9:0] x_pos_kroozr;
reg  signed [9:0] y_pos_kroozr;
wire signed [8:0] move_x = rotate ? -mouse_y : mouse_x;
wire signed [8:0] move_y = rotate ?  mouse_x : mouse_y;
wire signed [9:0] x_pos_new = x_pos_kroozr - move_x;
wire signed [9:0] y_pos_new = y_pos_kroozr + move_y;
reg  [1:0] mouse_btns;
always @(posedge clk_sys) begin
        if (mouse_strobe) begin
                mouse_btns <= mouse_flags[1:0];
                if (!((move_x[8] & ~x_pos_kroozr[9] &  x_pos_new[9]) || (~move_x[8] &  x_pos_kroozr[9] & ~x_pos_new[9]))) x_pos_kroozr <= x_pos_new;
                if (!((move_y[8] &  y_pos_kroozr[9] & ~y_pos_new[9]) || (~move_y[8] & ~y_pos_kroozr[9] &  y_pos_new[9]))) y_pos_kroozr <= y_pos_new;
        end
end

// Spinners for Tron, Two Tigers, Krooz'r
wire [6:0] spin_angle1;
spinner spinner1 (
        .clock_40(clk_sys),
        .reset(reset),
        .btn_acc(1),
        .btn_left(m_left1 | m_up1),
        .btn_right(m_right1 | m_down1),
        .ctc_zc_to_2(vs),
        .spin_angle(spin_angle1)
);

wire [6:0] spin_angle2;
spinner spinner2 (
        .clock_40(clk_sys),
        .reset(reset),
        .btn_acc(1),
        .btn_left(m_left2 | m_up2),
        .btn_right(m_right2 | m_down2),
        .ctc_zc_to_2(vs),
        .spin_angle(spin_angle2)
);


endmodule
