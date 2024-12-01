#include "fir.h"
#include <stdint.h>

void __attribute__ ( ( section ( ".mprjram" ) ) ) initfir() {

	// program data length
	reg_fir_len = data_length;

	// program coefficient
	for (uint32_t i = 0; i < 11; i++) {
		wb_write(reg_fir_coeff + 4*i , taps[i]);
	}
}

int* __attribute__ ( ( section ( ".mprjram" ) ) ) fir_excute() {
	
	// StartMark
	reg_mprj_datal = 0x00A50000;

        // ap_start
        reg_fir_ap_ctrl = 1;
	
        uint8_t register t = 0;
        uint8_t register tmp = 0;
	
        //while (t < data_length) {
        //	 reg_fir_x_in = t;
        //        outputsignal[t] =  reg_fir_y_out;
        //        t = t + 1;
        //}

	//reg_fir_x_in = t;
	//while (t < data_length - 1) {
        //        outputsignal[t] =  reg_fir_y_out;
         //       t = t + 1;
        //        reg_fir_x_in = t;
        //}
	//outputsignal[t] =  reg_fir_y_out;
	
	reg_fir_x_in = t;
	while (t < data_length - 1) {
                tmp =  reg_fir_y_out;
                t = t + 1;
                reg_fir_x_in = t;
                outputsignal[t - 1] =  tmp;
                
        }
	outputsignal[t] = reg_fir_y_out;
	
        // check the final Y by using    MPRJ[31:24]
        // send the EndMark 5A signal at MPRJ[23:16]
        reg_fir_ap_ctrl; // check ap_done
        checkbits = outputsignal[N-1] << 24 | 0x005A0000;
        
	return outputsignal;
}
	
		
