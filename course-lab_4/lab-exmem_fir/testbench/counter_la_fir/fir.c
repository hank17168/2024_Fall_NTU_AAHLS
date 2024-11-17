#include "fir.h"

void __attribute__ ( ( section ( ".mprjram" ) ) ) initfir() {
	//initial your fir
	for(int i = 0;i < 11;i = i + 1){
		inputbuffer[i]  = 0;
		outputsignal[i] = 0;
	}
}

int* __attribute__ ( ( section ( ".mprjram" ) ) ) fir(){
	initfir();
	//write down your fir
	for(int i = 0;i < 11;i = i + 1){
		for(int j = 10;j > 0;j = j - 1){
			inputbuffer[j] = inputbuffer[j - 1];
		}
		inputbuffer[0] = inputsignal[i];
		int y = 0;
		for(int k = 0;k < 11;k = k + 1){
			y += taps[k] * inputbuffer[k];
		}
		outputsignal[i] = y;
	}
	return outputsignal;
}
		
