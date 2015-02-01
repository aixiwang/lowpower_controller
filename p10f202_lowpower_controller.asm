;**********************************************************************
; Low Power Controller                                                *
; Turn on xxx sec, turn off yyy sec                                     *
; In turn on period, if GP0 is high, turn off power directly          *
; The power is turn on/off by a N MOS.                                *
; Low level to turn on the power MOS                                  *
;                                                                     *
;**********************************************************************
; Copyright(c) by Aixi Wang  aixi.wang@hotmail.com                    *
;                                                                     *
; BSD 3-Clause License is applied to the code                         *
;**********************************************************************
;              ------------- 
; N/C         | 1         8 | GP3/MCLR#/VPP
; VDD         | 2         7 | VSS
; GP2         | 3         6 | N/C
; GP1/ICSPCLK | 4         5 | GPO/ICSPDAT
;              -------------
; GP2(output) is used to control ESP8266 power. Low voltage will turn 
;             on external chip power
; GP1(input) is reserved, input
; GP0(input)  is used for setting_in
;**********************************************************************
; Revision History
; v01 -- initial version
; v02 -- validated with real hardware  
; v03 -- changed to wdt wakeup mode to save more power
;
;**********************************************************************
;------------------------
; command header
;------------------------
	list      p=10F202          ; list directive to define processor
	#include <p10F202.inc>      ; processor specific variable definitions

	__CONFIG   _MCLRE_OFF & _CP_ON & _WDT_ON

;------------------------
; global setting
;------------------------
#define ON_SEC 15
#define OFF_SEC 180
#define TH1 ON_SEC/2
#define TH2 (ON_SEC+OFF_SEC)/2
    
;------------------------
; variables
;------------------------
w_temp	    equ     0x10        ; reserved for framework
status_temp	equ     0x11        ; reserved for framework
delay_cnt1  equ     0x12        ; reserved for framework
delay_cnt2  equ     0x13        ; reserved for framework
delay_cnt3  equ     0x14        ; reserved for framework
wdt_wake_cnt equ    0x15        
count_temp   equ    0x16        
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
    movlw k
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
    decf reg,f
    endm

testb_ifzero_go macro  reg,lable
    btfss STATUS,Z
    goto $+2
    goto lable
    endm

testb_ifnonzero_go macro reg,lable
    btfsc STATUS,Z
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
    
testb_ifnotequal_go macro  reg,k,lable
    movlw k    
    subwf reg,w
    btfsc STATUS,Z
    goto $+2
    goto lable    
    endm

testb_ifless_go macro  reg,k,lable
    movlw k    
    subwf reg,w
    btfsc STATUS,C
    goto $+2
    goto lable    
    endm
    
testb_ifnotless_go macro  reg,k,lable
    movlw k    
    subwf reg,w
    btfss STATUS,C
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

delay macro k1
   movlw k1
   movwf delay_cnt1
   movlw 0xff
   movwf delay_cnt2
   movlw 0xff
   movwf delay_cnt3
   decfsz delay_cnt3,f
   goto $-1   
   decfsz delay_cnt2,f
   goto $-5
   decfsz delay_cnt1,f
   goto $-9
   
   endm

clear_ram macro
    movlw 0x08
    movwf fsr
    clrf indf
    incf fsr,f
    btfss fsr,5
    goto $-3
    endm

set_gpio_dir macro k
    movlw k
    tris GPIO
    endm

debug macro
    clrbit GPIO,2
    delay 1
    setbit GPIO,2    
    endm
;------------------------
; main
;------------------------
	org     0x000               ; coding begins here
	movwf   OSCCAL              ; update register with factory cal value 

start:	
	nop
    testbit_ifclear_go STATUS,NOT_TO,main_loop2
    
    ; clear ram
    clear_ram
    
    ; ------ GPIO -------------
    ; GPIO0 input setting_in    1   
    ; GPIO1 input               1
    ; GPIO2 output power_ctl    0
    ; GPIO3 MCLR#               1 
    ; 1001
    set_gpio_dir 0x0b
    
    ; ------ OPTION -----------
    ; 7 GPWU#  1
    ; 6 GPPU#  1
    ; 5 T0CS   0
    ; 4 TOSE   0
    ; 3 PSA    1 Prescaler assigned to the WDT
    ; 2-0      111 1:128
    ; 0xcf
    set_option 0xcf
    
    ; init, turn off power
    setbit GPIO,2

;-------------------------------------------------------------
;
; wdt wakeup method, lower power
; every wdt wakeup, around 2 sec
; 
;-------------------------------------------------------------
main_loop2:
    set_gpio_dir 0x0b
    set_option 0xcf
    
    ; turn on
    testb_ifless_go wdt_wake_cnt,TH1,j_wdt_turnon_power
    ; turn off
    testb_ifless_go wdt_wake_cnt,TH2,j_wdt_turnoff_power
    goto j_wdt_pre_main_loop2
    
j_wdt_turnon_power:
    ;debug
    clrbit GPIO,2
    incb wdt_wake_cnt    
    sleep
    nop
    
j_wdt_turnoff_power:
    setbit GPIO,2
    incb wdt_wake_cnt   
    sleep
    nop 

    
j_wdt_pre_main_loop2:
    clrb wdt_wake_cnt
    sleep
    nop
      
; remaining code goes here
    end

