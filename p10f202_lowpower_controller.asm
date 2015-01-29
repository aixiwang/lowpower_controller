;**********************************************************************
; Low Power Controller
; Every xx sec, turn on power xx sec                                  *
; In turn on period, if GP0 is high, turn off power directly          *
; The power is turn on/off by a N MOS.                                *
; Low level to turn on the power MOS                                  *
;                                                                     *
;**********************************************************************
; Copyright(c) by Aixi Wang  aixi.wang@hotmail.com                    *
;                                                                     *
; BSD 3-Clause License is applied for the code                        *
;**********************************************************************
;              ------------- 
; N/C         | 1         8 | GP3/MCLR#/VPP
; VDD         | 2         7 | VSS
; GP2         | 3         6 | N/C
; GP1/ICSPCLK | 4         5 | GPO/ICSPDAT
;              -------------
; GP2(output) is used to control ESP8266 power. Low voltage will turn 
;             on ESP8266 power
; GP1(output) is used for debug_led
; GP0(input)  is used for setting_in from powered module
;**********************************************************************
; Revision History
; v01 -- initial version
; v02 -- Fixed several errors
;**********************************************************************

;------------------------
; common header
;------------------------
	list      p=10F202          ; list directive to define processor
	#include <p10F202.inc>      ; processor specific variable definitions

	__CONFIG   _MCLRE_ON & _CP_OFF & _WDT_OFF

;------------------------
; variables
;------------------------
w_temp	    equ     0x08        ; reserved for framework
status_temp	equ     0x09        ; reserved for framework
delay_cnt1  equ     0x0a        ; reserved for framework
delay_cnt2  equ     0x0b        ; reserved for framework
wdt_wake_cnt equ    0x0c        
last_ram    equ     0x1f        ; reserved for framework, last one

;------------------------
; macros
;------------------------
swapwf macro reg
    xorwf reg,f
    xorwf reg,w
    xorwf reg,f
    endm

setb macro reg,k
    movlw k  
    movwf reg
    endm

getb macro reg
    movf reg,w
    endm

set_option macro k
    option
    endm
    
clrb macro reg
    clrf reg
    endm

setbit macro reg,b
    bsf reg,b
    endm

clrbit macro reg,b
    bcf reg,b
    endm

testbit_ifclear_go macro  reg,b,lable
    btfsc reg,b
    goto $+2
    goto lable
    endm

testbit_ifset_go macro reg,b,lable
    btfss reg,b
    goto $+2
    goto lable
    endm

incb macro reg
    incf reg,f
    endm
  
decb macro reg
    decf reg
    endm

testb_ifzero_go macro  reg,lable
    btfsc reg,b
    goto $+2
    goto lable
    endm

testb_ifnonzero_go macro reg,lable
    btfss reg,b
    goto $+2
    goto lable
    endm

testb_ifequal_go macro  reg,k,lable
    movlw k    
    subwf reg,w
    btfss STATUS,Z
    goto $+2
    goto lable    
    endm

save_w_status macro
    movwf w_temp 
    swapf status,w
    movwf status_temp
    endm

restore_w_status macro
    swapf status_temp,w
    movwf status
    swapf w_temp,f
    swapf w_temp,w
    endm

delayms macro k1
   movlw k1
   movwf delay_cnt1
   movlw 0xff
   movwf delay_cnt2
   decfsz delay_cnt2,f
   goto $-1
   decfsz delay_cnt1,f
   goto $-5
   endm

clear_ram macro
    movlw 0x08
    movwf fsr
    clrf indf
    incf fsr,f
    btfsc fsr,5
    goto $-3
    endm

set_gpio_dir macro k
    movlw k
    tris GPIO
    endm

;------------------------
; main
;------------------------
	org     0x000               ; coding begins here
	movwf   OSCCAL              ; update register with factory cal value 

start:	
	nop  
    ; clear ram
    clear_ram

    ;------ GPIO -------------
    ; GPIO0 input setting_in
    ; GPIO1 output debug_led
    ; GPIO2 output power_ctl
    ; GPIO3 MCLR#
    ; 1001
    setbit GPIO, 2              ; default, turn off ESP8266 power
    set_gpio_dir 0x05

    ;------ OPTION -----------
    ; 7 GPWU#  1
    ; 6 GPPU#  1
    ; 5 T0CS   0
    ; 4 TOSE   0
    ; 3 PSA    1 Prescaler assigned to the WDT
    ; 2-0      111 1:128
    ; 0xcf
    set_option 0xcf
    
    ;
    ; first debug main_loop, once it's ready, switch to main_loop2 to get more lower power
    ;
    ; TODO -- check setting_in, power off directly
    ;
main_loop:
    delayms 0xff
    clrbit GPIO,2
    delayms 0xff
    setbit GPIO,2
    goto main_loop

main_loop2:
    ;    
    ; wdt wakeup method, lower power
    ;
    incb wdt_wake_cnt
    testb_ifequal_go wdt_wake_cnt,100,go_set_high
    testb_ifequal_go wdt_wake_cnt,200,go_set_low
    
go_set_high:
    setbit GPIO,2
    sleep
    nop
    nop
    goto main_loop2
    
go_set_low:
    clrbit GPIO,2
    clrb wdt_wake_cnt
    sleep
    nop
    nop
    goto main_loop2

; remaining code goes here
    end
