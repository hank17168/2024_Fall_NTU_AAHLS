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
 * user_project_wrapper
 *
 * This wrapper enumerates all of the pins available to the
 * user for the user project.
 *
 * An example user project is provided in this wrapper.  The
 * example should be removed and replaced with the actual
 * user project.
 *
 *-------------------------------------------------------------
 */

module user_project_wrapper #(
    parameter BITS = 32
) (
`ifdef USE_POWER_PINS
    inout vdda1,	// User area 1 3.3V supply
    inout vdda2,	// User area 2 3.3V supply
    inout vssa1,	// User area 1 analog ground
    inout vssa2,	// User area 2 analog ground
    inout vccd1,	// User area 1 1.8V supply
    inout vccd2,	// User area 2 1.8v supply
    inout vssd1,	// User area 1 digital ground
    inout vssd2,	// User area 2 digital ground
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

    // Analog (direct connection to GPIO pad---use with caution)
    // Note that analog I/O is not available on the 7 lowest-numbered
    // GPIO pads, and so the analog_io indexing is offset from the
    // GPIO indexing by 7 (also upper 2 GPIOs do not have analog_io).
    inout [`MPRJ_IO_PADS-10:0] analog_io,

    // Independent clock (on independent integer divider)
    input   user_clock2,

    // User maskable interrupt signals
    output [2:0] user_irq
);




//------------------------ADDRESS DECODE--------------------------------

    assign mem_star = (wbs_adr_i[31: 24] == 8'h38)? 1'b1 : 1'b0;
    assign fir_addr = (wbs_adr_i[31: 24] == 8'h30)? 1'b1 : 1'b0;
    //stream in out
    assign stream_in = (wbs_adr_i[7: 0] == 8'h80)? 1'b1 : 1'b0;
    assign stream_out = (wbs_adr_i[7: 0] == 8'h84)? 1'b1 : 1'b0; 


//--------------------------WB-AXI--------------------------------------
//WB-AXILITE

    wire         awready;
    wire         wready;
    wire         awvalid;
    wire [31 :0] awaddr;
    wire         wvalid;
    wire [31 :0] wdata;
    wire         arready;
    wire         rready;
    wire         arvalid;
    wire [31 :0] araddr;
    wire         rvalid;
    wire [31 :0] rdata;
    wire [31: 0] wbs_r_dat;
    wire         wbs_r_ack;
    wire         wbs_w_ack;
    wire         wbs_si_ack;
    wire         wbs_so_ack;
    wire [31: 0] wbs_so_dat;
    wire [31: 0] wbs_si_dat;

//----------------------------------------------------------------------
//                             read protocol
//-----------------------------------------------------------------------
//  Master 提供 ARADDR 並置位 ARVALID，Slave 確認準備好接收請求時置位 ARREADY
//  當 ARVALID 和 ARREADY 同時為高時握手完成，Master 和 Slave 鎖定位址
//  Slave 傳送數據（RDATA）並置位 RVALID, 當master 確認準備好接收數據時置位 RREADY
//  當 RVALID 和 RREADY 同時為高時握手完成，數據傳輸到 Master
//----------------------------------------------------------------------

    assign arvalid = fir_addr && wbs_cyc_i && wbs_stb_i && (!wbs_we_i);
    assign rready  = fir_addr && wbs_cyc_i && wbs_stb_i && (!wbs_we_i);
    assign araddr  = wbs_adr_i;
    //read ack
    assign wbs_r_ack = rvalid && rready;
    //read data,從output rdata中把data存到wbs_dat_o
    assign wbs_r_dat = rdata; 

//----------------------------------------------------------------------
//                             write protocol
//----------------------------------------------------------------------
//  AWADDR	Master	要寫入的目標位址
//  AWVALID	Master	指示 AWADDR 有效
//  AWREADY	Slave	指示 Slave 準備接收位址
//  WDATA	Master	要寫入的數據
//  WVALID	Master	指示 WDATA 有效
//  WREADY	Slave	指示 Slave 準備接收數據
//-----------------------------------------------------------------------

    assign awvalid = fir_addr && wbs_cyc_i && wbs_stb_i && wbs_we_i;
    assign wdata = wbs_dat_i;
    assign wvalid = fir_addr && wbs_cyc_i && wbs_stb_i && wbs_we_i;
    assign awaddr = wbs_adr_i;
    //write ack
    assign wbs_w_ack = wready && wvalid;
    //write data,把input wdata連到wbs_dat_i
    assign wdata = wbs_dat_i;

//WB-AXISTREAM
    
    wire           ss_tvalid;
    wire [31 :0]   ss_tdata;
    wire           ss_tlast; 
    wire           ss_tready; 
    wire           sm_tready; 
    wire           sm_tvalid; 
    wire [31 :0]   sm_tdata; 
    wire           sm_tlast;

//--------------------------stream in---------------------------------
    
    assign ss_tvalid = stream_in && wbs_cyc_i && wbs_stb_i ;
    assign ss_tdata = wbs_dat_i;
    //assign ss_tlast = ;
    assign wbs_si_ack = ss_tready && ss_tvalid;
    //assign wbs_si_dat = ; dont care

//--------------------------stream out---------------------------------

    assign sm_tready = stream_out && wbs_cyc_i && wbs_stb_i ;
    assign wbs_so_ack = sm_tready && sm_tvalid;
    assign wbs_so_dat = sm_tdata;

//--------------------------select output---------------------------------
    
    wire usr1;
    wire [31: 0] usr2;
    assign wbs_ack_o = temp1;
    assign wbs_dat_o = temp2;
    always@(*) begin
        if(fir_addr) begin
            if(wbs_we_i) begin
                if(stream_in) begin
                    temp1 = wbs_si_ack;
                    temp2 = 32'b0
                end
                else begin
                    temp1 = wbs_w_ack;
                    temp2 = 32'b0;
                end
            end    
            else begin
                if(stream_out) begin
                    temp1 = wbs_so_ack;
                    temp2 = wbs_so_dat;
                end
                else begin
                    temp1 = wbs_r_ack;
                    temp2 = wbs_r_dat;
                end
            end
        end
        //user project
        else begin
            temp1 = usr1;
            temp2 = usr2;
        end
    end

/*--------------------------------------*/
/* User project is instantiated  here   */
/*--------------------------------------*/
    // ram for tap
    wire [3:0]  tap_WE;
    wire        tap_EN;
    wire [31:0] tap_Di;
    wire [31:0] tap_A;
    wire [31:0] tap_Do;

    // ram for data RAM
    wire [3:0]  data_WE;
    wire        data_EN;
    wire [31:0] data_Di;
    wire [31:0] data_A;
    wire [31:0] data_Do;


user_proj_example mprj (
`ifdef USE_POWER_PINS
	.vccd1(vccd1),	// User area 1 1.8V power
	.vssd1(vssd1),	// User area 1 digital ground
`endif

    .wb_clk_i(wb_clk_i),
    .wb_rst_i(wb_rst_i),

    // MGMT SoC Wishbone Slave

    .wbs_cyc_i(wbs_cyc_i),
    .wbs_stb_i(wbs_stb_i),
    .wbs_we_i(wbs_we_i),
    .wbs_sel_i(wbs_sel_i),
    .wbs_adr_i(wbs_adr_i),
    .wbs_dat_i(wbs_dat_i),
    .wbs_ack_o(usr1),
    .wbs_dat_o(usr2),

    // Logic Analyzer

    .la_data_in(la_data_in),
    .la_data_out(la_data_out),
    .la_oenb (la_oenb),

    // IO Pads

    .io_in (io_in),
    .io_out(io_out),
    .io_oeb(io_oeb),

    // IRQ
    .irq(user_irq)
);

//fir 
fir fir1(
    .axis_clk(axis_clk),
    .axis_rst_n(axis_rst_n),
    
    .awready(awready),
    .wready(wready),
    .awvalid(awvalid),
    .awaddr(awaddr),
    .wvalid(wvalid),
    .wdata(wdata),
    .arready(arready),
    .rready(rready),
    .arvalid(arvalid),
    .araddr(araddr),
    .rvalid(rvalid),
    .rdata(rdata),

    .ss_tvalid(ss_tvalid),
    .ss_tdata(ss_tdata),
    .ss_tlast(ss_tlast),
    .ss_tready(ss_tready),
    .sm_tready(sm_tready),
    .sm_tvalid(sm_tvalid),
    .sm_tdata(sm_tdata),
    .sm_tlast(sm_tlast),
    
    .tap_WE(tap_WE),
    .tap_Di(tap_Di),
    .tap_Do(tap_Do),
    .tap_EN(tap_EN),
    .tap_A(tap_A),

    .data_A(data_A),
    .data_WE(data_WE),
    .data_Di(data_Di),
    .data_Do(data_Do),
    .data_EN(data_EN)
);

//tap

bram11 tap(
    .CLK(axis_clk),
    .WE(tap_WE),
    .Di(tap_Di),
    .Do(tap_Do),
    .EN(tap_EN),
    .A(tap_A)
);

//data

bram11 data(
    .CLK(axis_clk),
    .WE(data_WE),
    .Di(tap_Di),
    .Do(tap_Do),
    .EN(tap_EN),
    .A(tap_A)
);
endmodule	// user_project_wrapper

`default_nettype wire
