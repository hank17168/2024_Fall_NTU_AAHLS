module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11
)
(
	 //----------- AXI-Lite Interface (Read/Write Transaction) ------
    output  wire                     awready,	// address write ready
    output  wire                     wready,	// data    write ready
    input   wire                     awvalid,	// address write valid
	input   wire                     wvalid,	// data    write valid
    input   wire [(pADDR_WIDTH-1):0] awaddr,	// address write data   => Write the Address of Coefficient
    input   wire [(pDATA_WIDTH-1):0] wdata,		// data    write data   => Write the Coefficient
	 
    output  wire                     arready,	// address read  ready
    input   wire                     rready,	// data    read  ready
    input   wire                     arvalid,	// address read  valid
	output  wire                     rvalid,	// data    read  valid
    input   wire [(pADDR_WIDTH-1):0] araddr,	// address read  data   => Send the Address of Coefficient to Read
    output  wire [(pDATA_WIDTH-1):0] rdata,		// data    read  data   => Coefficient of that Address
	 //------------------ AXI-Stream In X[n] ----------------------
    input   wire                     ss_tvalid, 
    input   wire [(pDATA_WIDTH-1):0] ss_tdata,	// data input x[t-i]
    input   wire                     ss_tlast, 
    output  wire                     ss_tready,
	 //----------------- AXI-Stream Out Y[t] ----------------------
    input   wire                     sm_tready, 
    output  wire                     sm_tvalid, 
    output  wire [(pDATA_WIDTH-1):0] sm_tdata,	// data output Y[t]
    output  wire                     sm_tlast, 
    //----------------- bram for tap RAM -------------------------
    output  wire [3:0]               tap_WE,
    output  wire                     tap_EN,
    output  wire [(pDATA_WIDTH-1):0] tap_Di,	// transfer tape from fir to memory
    output  wire [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do,	// output from Tape_Ram
    //----------------- bram for data RAM ------------------------
    output  wire [3:0]               data_WE,
    output  wire                     data_EN,
    output  wire [(pDATA_WIDTH-1):0] data_Di,	// data after calculation
    output  wire [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,	// output from Data_Ram

    input   wire                     axis_clk,
    input   wire                     axis_rst_n
);
//begin
    // write your code here!
//end
parameter AP_START = 2'b00;
parameter AP_IDLE  = 2'b01;
parameter AP_DONE  = 2'b10;

parameter SM_IDLE  = 1'b0;
parameter SM_DONE  = 1'b1;

parameter FIR_IDLE = 2'b00;
parameter FIR_START= 2'b01;
parameter FIR_PROC = 2'b10;
parameter FIR_DONE = 2'b11;
//----------------------- AXI-Lite -----------------------------
reg r_arready;	// address read  ready
reg r_awready;	// address write ready
reg r_rvalid;	// data    read  valid
reg r_wready;	// data    write ready
// -------------- Configuration Register control ---------------
// 0x00 => bit 0: ap_start, bit 1: ap_done, bit 2: ap_idle
wire [2:0]  ap_ctrl;   
reg  [1:0]  ap_state;
reg  [1:0]  next_ap_state;
reg  [31:0] data_length; // 0x10-14: data length
reg  [5:0]  init_addr;   // data RAM initialize
reg  [9:0]  tlast_cnt;   // count to data length 600
reg  [4:0]  out_cnt;       
// ---------------- FIR -------------------
reg  [1:0]  fir_state;
reg  [1:0]  next_fir_state;
reg  [(pDATA_WIDTH-1):0] h;
reg  [(pDATA_WIDTH-1):0] x;
reg  [(pDATA_WIDTH-1):0] m;  
reg  [(pDATA_WIDTH-1):0] y;
// ---------------- Address ---------------
wire [5:0] tap_AR;    // address which will send into tap_RAM
reg  [3:0] k;
reg  [3:0] x_cnt;
reg  [3:0] x_cnt_tmp;
wire [5:0] data_AR;

//----------------------- AXI-Lite -----------------------------    
always@(posedge axis_clk, negedge axis_rst_n) begin
	if(!axis_rst_n) begin
		r_arready	<= 0;	// address read  ready
		r_awready	<= 0;	// address write ready
		r_rvalid 	<= 0;   // data    read  valid
		r_wready 	<= 0;	// data    write ready
	end
	else begin
		r_arready	<= (arvalid)?1 : 0;	// address read  ready
		r_rvalid 	<= (arvalid | rvalid & ~rready)?1 : 0; // data    read  valid
		r_awready	<= (awvalid && wvalid)?1 : 0;	// address write ready
		r_wready	<= (awvalid && wvalid)?1 : 0;   // data    write ready
	end
end	 
assign arready = r_arready;
assign awready = r_awready;
assign rvalid  = r_rvalid;
assign wready  = r_wready;
assign rdata   = (araddr[7:0] == 8'd0)? ap_ctrl : tap_Do; // read ap_state or Tap_SRAM data

// -------------- Configuration Register control ---------------
assign ap_ctrl[2] = (ap_state == AP_IDLE)?1:0;
assign ap_ctrl[1] = (ap_state == AP_DONE)?1:0;
assign ap_ctrl[0] = (ap_state == AP_IDLE && awaddr == 12'd0 && tlast_cnt != data_length)?1:0;

always@(*) begin
    case (ap_state)
        AP_IDLE : next_ap_state = (awaddr == 12'd0 && wdata[0] && tlast_cnt != data_length) ? AP_START : AP_IDLE;
        AP_START: next_ap_state = sm_tlast ? AP_DONE : AP_START;
        AP_DONE : next_ap_state = (araddr == 12'd0 && arvalid && rvalid) ? AP_IDLE : AP_DONE;
        default : next_ap_state = AP_IDLE;
    endcase
end

always@(posedge axis_clk or negedge axis_rst_n) begin
	if (!axis_rst_n)
		ap_state <= AP_IDLE;
	else
		ap_state <= next_ap_state;
end

// 0x10-14: data length
always@(posedge axis_clk , negedge axis_rst_n) begin
	if (!axis_rst_n)
		data_length <= 32'b0;
	else if(awaddr == 8'h10)
		data_length <= wdata;
	else
	    data_length <= data_length;
end
//------------------------- tap / Data RAM signals ----------------------------- // 0x20-FF: tap parameter
assign tap_EN = 1;
assign tap_WE = ((wvalid == 1) && (awaddr[7:0] != 0))? 4'b1111 : 4'b0000;
assign tap_A  = (ap_ctrl[2] == 1 && (wvalid == 1 || wready == 1))? awaddr[5:0] : tap_AR[5:0];
assign tap_Di = wdata;
 
assign data_EN = 1;
assign data_WE = (ss_tready || init_addr != 6'd44)? 4'b1111 : 4'b0000;	// if ss_tlast not asserted, still can write
assign data_A  = (ap_ctrl[2] == 1 && init_addr != 6'd44)? init_addr : data_AR;	// data initialize before ap_start
assign data_Di = (ap_ctrl[2] == 1 && init_addr != 6'd44)? 0 : ss_tdata;				// 44 => 11-tap data 

always @(posedge axis_clk or negedge axis_rst_n) begin
	if (!axis_rst_n) 
		init_addr <= 6'd0;
	else if(init_addr == 6'd44)
		init_addr <= init_addr;
	else
	    init_addr <= init_addr + 4;
end

//-------------- data length ------------------
always@(posedge axis_clk or negedge axis_rst_n) begin
	if (!axis_rst_n) 
		tlast_cnt <= 10'd0;
	else
		tlast_cnt <= (sm_tvalid == 1'b1)? tlast_cnt + 1'b1 : tlast_cnt;
end

//-------------- AXI-Stream output Y -------------
always@(posedge axis_clk or negedge axis_rst_n) begin
	if (!axis_rst_n)
		out_cnt <= 5'd0;
	else if (fir_state == FIR_IDLE)
		out_cnt <= (tlast_cnt == 0)? 10'd13 : 10'd8;
	else if (fir_state == FIR_START || fir_state == FIR_PROC)
	    out_cnt <= out_cnt - 1'b1;
	else
		out_cnt <= out_cnt;
end
always@(*) begin
    case (fir_state)
        FIR_IDLE : begin
                        if(ap_ctrl[2] == 1'b0 && tlast_cnt == 0) 
                            next_fir_state = FIR_START;
                        else if(ap_ctrl == 1'b0 && tlast_cnt != 0)
                            next_fir_state = FIR_PROC;
                        else 
                            next_fir_state = FIR_IDLE;
                   end
        FIR_START: next_fir_state = (out_cnt == 0)? FIR_DONE : FIR_START;
        FIR_PROC : next_fir_state = (out_cnt == 0)? FIR_DONE : FIR_PROC;
        FIR_DONE : next_fir_state = FIR_IDLE;
        default  : next_fir_state = FIR_IDLE;
    endcase
end

always@(posedge axis_clk or negedge axis_rst_n) begin
    if(!axis_rst_n)
        fir_state <= FIR_IDLE;
    else begin
        fir_state <= next_fir_state;
    end
end

//------------ FIR ---------------

always @(posedge axis_clk or negedge axis_rst_n) begin
	if (!axis_rst_n) begin
		h <= 32'd0;
		x <= 32'd0;
		m <= 32'd0;
		y <= 32'd0;
	end
	else begin
		h <= tap_Do;
		x <= data_Do;
		m <= h * x;
		y <= (fir_state == FIR_DONE)?0:y + m;
	end
end

//---------------------- Address ----------------------
always @(posedge axis_clk or negedge axis_rst_n) begin
	if (!axis_rst_n)
		k <= 4'd10;
	else if(ap_ctrl[2])
		k <= 4'd10;
	else
		k <= (k != 4'd10)? k+1 : 4'd0;
end

assign tap_AR = (ap_ctrl[2] == 1'b0)? 4 * k : araddr[5:0];

always@(*) begin
    if (ap_state != AP_IDLE && k == 10)
        x_cnt_tmp = (x_cnt != 10) ? x_cnt + 1 : 0;
    else
        x_cnt_tmp = x_cnt;
end

always @(posedge axis_clk or negedge axis_rst_n) begin
	if (!axis_rst_n)
		x_cnt <= 4'd0;
	else
		x_cnt <= x_cnt_tmp;
end

assign data_AR = (k <= x_cnt)? 4 * (x_cnt - k) : 4 * (11 + x_cnt - k); // x[t-i]

//---------------------- AXI-Stream ---------------------------
// tvalid is driven by master / tready is driven by tslave
// Stream-in X
assign ss_tready = (ap_ctrl[2] == 0 && init_addr == 6'd44 && k == 4'd0)? 1'b1 : 1'b0;
// Stream-out Y
assign sm_tvalid = (fir_state == FIR_DONE)? 1'b1 : 1'b0;
assign sm_tdata  = y;
assign sm_tlast  = (fir_state == FIR_IDLE && tlast_cnt == data_length)? 1'b1 : 1'b0; 

endmodule
