;**********************************************************************
; Low Power Controller                                                *
; Turn on xxx sec, turn off yyy sec                                   *
;                                                                     *
;**********************************************************************
; Copyright(c) by Aixi Wang  aixi.wang@hotmail.com                    *
;                                                                     *
; BSD license applied                                           *
;**********************************************************************
;              ------------- 
; N/C         | 1         8 | GP3/MCLR#/VPP
; VDD         | 2         7 | VSS
; GP2         | 3         6 | N/C
; GP1/ICSPCLK | 4         5 | GP0/ICSPDAT
;              -------------
; GP2(output)  
; GP1(output) is reserved, LED control & debug
; GP0(output) power control, high => turn on power
;**********************************************************************
; Revision History
; v01 -- initial version
; v02 -- validated with real hardware  
; v03 -- changed to wdt wakeup mode to save more power
; [v04 2019-01-13]
; * added wdt task framework
; * added reinit code to re-enable gpio setting after wdt wakup
; [v05 2019-01-15]
; * fixed off countering bug caused by incorrect jump label
;**********************************************************************
;------------------------
; command header
;------------------------
    LIST      P=10F202,R=DEC    ; list directive to define processor
    
    #include <p10F202.inc>      ; processor specific variable definitions
    
    __CONFIG   _MCLRE_OFF & _CP_ON & _WDT_ON & _IntRC_OSC

;---------------------------
; global setting
; WDT wakeup period = 2304 ms 
;
; task0 -> turn on power 
; task1 -> turn off power
;---------------------------
; 15 -> 15/3.2 ~= 7
#define TASK0_TH_H  0
#define TASK0_TH_L  7

; 600 -> 600/2.3 ~= 260 = 1*256 + 4
; 300 -> 130
#define TASK1_TH_H  1
#define TASK1_TH_L  4

;------------------------
; variables
;------------------------
w_temp      equ     0x10        ; reserved for framework
status_temp equ     0x11        ; reserved for framework
delay_cnt1  equ     0x12        ; reserved for framework
delay_cnt2  equ     0x13        ; reserved for framework
delay_cnt3  equ     0x14        ; reserved for framework

task0_wdt_cnt_l   equ      0x15        ;
task0_wdt_cnt_h   equ      0x16        ;
task1_wdt_cnt_l   equ      0x17        ;
task1_wdt_cnt_h   equ      0x18        ;



flag        equ      0x1e        ; task switch
                                 ; bit0 -- wdt task1
                                 ; bit1 -- wdt task2
#define BIT_TASK0 0
#define BIT_TASK1 1
#define BIT_TASK2 2
#define BIT_TASK3 3
#define BIT_TASK4 4
#define BIT_TASK5 5
#define BIT_TASK6 6
#define BIT_TASK7 7

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
   
   movlw 0xff                    ; loop3 -----
   movwf delay_cnt2
   movlw 0xff               ; loop2 -----
   movwf delay_cnt3
   decfsz delay_cnt3,f  ; loop1 -----
   goto $-1             ; loop1 -----
   decfsz delay_cnt2,f
   goto $-5                 ; loop2 ------
   decfsz delay_cnt1,f          
   goto $-9                    ; loop3 -----  
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
    clrbit GPIO,1
    delay 1
    setbit GPIO,1
    delay 1
    endm
    
led_on macro
    ; drive ws3812 led on
    clrbit GPIO,1   ; power on    
    endm
    
led_off macro
    ; drive ws3812 led off
    setbit GPIO,1   ; power on
    endm

power_on macro
    ; turn of main power
    setbit GPIO,0   ; power on
    endm
    
power_off macro
    ; turn off main power
    clrbit GPIO,0   ; power off
    endm    
;------------------------
; main
;------------------------
    org     0x000               ; coding begins here
    movwf   OSCCAL              ; update register with factory cal value 

start:  
    testbit_ifclear_go STATUS,NOT_PD,main_3
    ;testbit_ifclear_go STATUS,NOT_TO,main_3

main_0:
    clrwdt    
    ; clear ram
    clear_ram

    ; ------ GPIO -------------
    ; GPIO0 output    0   
    ; GPIO1 output    0
    ; GPIO2 output    0
    ; GPIO3 MCLR#     1 
    ; 1000
    set_gpio_dir 0x08
    
    ; ------ OPTION -----------
    ; 7 GPWU#  1
    ; 6 GPPU#  0
    ; 5 T0CS   0
    ; 4 TOSE   0
    ; 3 PSA    1 Prescaler assigned to the WDT
    ; 2-0      111 1:128
    ; 0x8f
    set_option 0x8f
    ;setb   GPIO,0x00

    ; init task flag
    setbit flag,BIT_TASK0
    
    ; TODO: debug purpose, will change to lighting control
    debug

    
    setb task0_wdt_cnt_l,0x00
    setb task0_wdt_cnt_h,0x00
    setb task1_wdt_cnt_l,0x00
    setb task1_wdt_cnt_h,0x00
    
    
    power_off   
    
    ; power_on
    sleep
    nop
    

;-------------------------------------------------------------
; WDT tasks, start from here
;-------------------------------------------------------------
main_3:
    set_gpio_dir 0x08
    set_option 0x8f
    ;clrwdt
    ; debug
    
    testbit_ifset_go flag,BIT_TASK0,j_task0
    testbit_ifset_go flag,BIT_TASK1,j_task1
    sleep
    nop

;--------------------------
; j_task block
;--------------------------   
j_task0:
  
    ;--------------------------------
    ; task0 do something begin
    power_on
    
    ; task0 do something end
    ;--------------------------------

    testb_ifless_go task0_wdt_cnt_h,TASK0_TH_H,j_wdt_1 ; high_byte
    testb_ifless_go task0_wdt_cnt_l,TASK0_TH_L,j_wdt_2 ; low byte
    goto j_wdt_3
    
j_wdt_1:
    testb_ifless_go task0_wdt_cnt_l,0xff,j_wdt_1_2 ; low byte
    incb task0_wdt_cnt_l
    incb task0_wdt_cnt_h    
    sleep
    nop

j_wdt_1_2:   
    incb task0_wdt_cnt_l
    sleep
    nop
    
j_wdt_2:

    incb task0_wdt_cnt_l
    sleep
    nop
    
j_wdt_3:
    clrb task0_wdt_cnt_l
    clrb task0_wdt_cnt_h
 
    clrbit flag,BIT_TASK0
    setbit flag,BIT_TASK1 
    sleep
    nop
    
    
 
;--------------------------
; j_task1 block
;-------------------------- 
j_task1:
 
    ;--------------------------------
    ; task1 do something begin
    power_off

    
    ; task0 do something end
    ;--------------------------------

    
    testb_ifless_go task1_wdt_cnt_h,TASK1_TH_H,task1_j_wdt_1 ; high_byte
    testb_ifless_go task1_wdt_cnt_l,TASK1_TH_L,task1_j_wdt_2 ; low byte
    goto task1_j_wdt_3
    
task1_j_wdt_1:
    testb_ifless_go task1_wdt_cnt_l,255,task1_j_wdt_1_2 ; low byte
    

    incb task1_wdt_cnt_l
    incb task1_wdt_cnt_h    
    sleep
    nop
    
task1_j_wdt_1_2:

    incb task1_wdt_cnt_l
    sleep
    nop
    
task1_j_wdt_2:

    incb task1_wdt_cnt_l
    sleep
    nop
    
task1_j_wdt_3:
    clrb task1_wdt_cnt_l
    clrb task1_wdt_cnt_h
 
    clrbit flag,BIT_TASK1
    setbit flag,BIT_TASK0 
    sleep
    nop    


; remaining code goes here
    end

