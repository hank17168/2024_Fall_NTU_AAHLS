// SPDX-FileCopyrightText: 2020 Efabless Corporation
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// SPDX-License-Identifier: Apache-2.0

`default_nettype none
/*
 *-------------------------------------------------------------
 *
 * user_proj_example
 *
 * This is an example of a (trivially simple) user project,
 * showing how the user project can connect to the logic
 * analyzer, the wishbone bus, and the I/O pads.
 *
 * This project generates an integer count, which is output
 * on the user area GPIO pads (digital output only).  The
 * wishbone connection allows the project to be controlled
 * (start and stop) from the management SoC program.
 *
 * See the testbenches in directory "mprj_counter" for the
 * example programs that drive this user project.  The three
 * testbenches are "io_ports", "la_test1", and "la_test2".
 *
 *-------------------------------------------------------------
 */

module user_proj_example #(
    parameter BITS = 32,
    parameter DELAYS=10
)(
`ifdef USE_POWER_PINS
    inout vccd1,	// User area 1 1.8V supply
    inout vssd1,	// User area 1 digital ground
`endif

    // Wishbone Slave ports (WB MI A)
    input wb_clk_i,
    input wb_rst_i,
    input wbs_stb_i,
    input wbs_cyc_i,
    input wbs_we_i,
    input [3:0] wbs_sel_i,
    input [31:0] wbs_dat_i,
    input [31:0] wbs_adr_i,
    output wbs_ack_o,
    output [31:0] wbs_dat_o,

    // Logic Analyzer Signals
    input  [127:0] la_data_in,
    output [127:0] la_data_out,
    input  [127:0] la_oenb,

    // IOs
    input  [`MPRJ_IO_PADS-1:0] io_in,
    output [`MPRJ_IO_PADS-1:0] io_out,
    output [`MPRJ_IO_PADS-1:0] io_oeb,

    // IRQ
    output [2:0] irq
);
    wire clk;
    wire rst;

    wire [`MPRJ_IO_PADS-1:0] io_in;
    wire [`MPRJ_IO_PADS-1:0] io_out;
    wire [`MPRJ_IO_PADS-1:0] io_oeb;


    assign irq = 3'b000;
    reg  [ 3:0] delay_cnt;   
    wire [ 3:0] bram_we   = wbs_sel_i & {4{wbs_we_i}};
    wire        bram_en   = wbs_cyc_i & wbs_stb_i & (wbs_adr_i[31:20] == 12'h380);
    wire [31:0] bram_di   = wbs_dat_i;
    wire [31:0] bram_do;
    wire [31:0] bram_adr  = wbs_adr_i;
    assign      wbs_dat_o = bram_do;
    assign      wbs_ack_o = (delay_cnt == 10)? 1 : 0;
    
    always@(posedge wb_clk_i or posedge wb_rst_i) begin
    	if(wb_rst_i) delay_cnt <= 0;
    	else if(bram_en && delay_cnt == 10) delay_cnt <= 0;
    	else if(bram_en && delay_cnt < 10)  delay_cnt <= delay_cnt + 1;
    	else delay_cnt <= 0;
    end

    bram user_bram (
        .CLK(wb_clk_i),
        .WE0(bram_we),
        .EN0(bram_en),
        .Di0(bram_di),
        .Do0(bram_do),
        .A0(bram_adr)
    );

/*
    wire m_valid = wbs_cyc_i && wbs_stb_i && (wbs_adr_i[31:20] == 12'h380);
    wire [3:0] bram_WE = wbs_sel_i & {4{wbs_we_i}};
    wire [31:0] addr_i = wbs_adr_i;
    wire [BITS-1:0] data_i = wbs_dat_i;
    wire [BITS-1:0] data_o;
    reg s_ready;
    reg [3:0] delay_cnt;

    assign wbs_ack_o = s_ready;
    assign wbs_dat_o = data_o;
    assign irq = 3'b000;

    wire next_s_ready = (delay_cnt == DELAYS - 1);
    wire [3:0] next_delay_cnt = next_s_ready ? 4'd0 : delay_cnt + 1;

    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            delay_cnt <= 4'd0;
            s_ready <= 1'b0;
        end else if (m_valid && !s_ready) begin
            delay_cnt <= next_delay_cnt;
            s_ready <= next_s_ready;
        end else begin
            delay_cnt <= 4'd0;
            s_ready <= 1'b0;
        end
    end

    bram user_bram (
        .CLK(wb_clk_i),
        .WE0(bram_WE),
        .EN0(m_valid),
        .Di0(data_i),
        .Do0(data_o),
        .A0(addr_i)
    );
*/

endmodule



`default_nettype wire
