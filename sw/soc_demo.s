; =====================================================================
;  FILE    : sw/soc_demo.s
;  PROJECT : Project 3 - firmware for RISC-8 CPU + Timer/ADC
; ---------------------------------------------------------------------
;  The CPU reaches a peripheral register by putting its address
;  (0xF0..0xFF) in a register, then LD / ST through that register.
;
;    0xF0 TMR_CTRL   0xF1 TMR_PRESC  0xF2 TMR_LOAD   0xF3 TMR_CMP
;    0xF4 TMR_CNT    0xF5 ADC_CTRL   0xF6 ADC_SMP    0xF7 ADC_DIV
;    0xF8 THR_LO     0xF9 THR_HI     0xFA ADC_DATA   0xFB ADC_RCH
;    0xFC ADC_STAT   0xFD IRQ_EN     0xFE IRQ_STAT   0xFF ID (=A8)
;
;  Analog inputs in the testbench:  ch0 = 0.400 V   ch1 = 1.111 V
;                                   ch2 = 2.000 V   ch3 = 3.000 V
;  Results are written to RAM 0x80 .. 0x91, the testbench checks them.
;
;    Part A  read ID                                   80 = A8
;    Part B  one software conversion, channel 1        81 = 81, 82 = 56
;    Part C  4 timer-triggered conversions, ch 2       83..8A = 82,9B x4
;            flags, then W1C of one flag                8B = 07, 8C = 03
;    Part D  window comparator -> irq pin              8D = 0C, 8E = E8
;    Part F  pointer arithmetic must not pop the FIFO  8F = 1F, 90 = 56,
;                                                      91 = 10
;    Part E  PWM 30 % duty, then HLT (timer keeps running)
;
;  Assemble:  python sw/soc_asm.py sw/soc_demo.s soc_demo.hex
; =====================================================================

; ===== Part A: read the ID register =====
        LDI  R7, 0xFF        ; R7 -> ID
        LD   R1, [R7]        ; R1 = 0xA8
        LDI  R6, 0x80
        ST   R1, [R6]        ; MEM[80] = A8

; ===== Part B: one software-started conversion on channel 1 =====
        LDI  R7, 0xF6        ; ADC_SMP = 3
        LDI  R1, 3
        ST   R1, [R7]
        LDI  R7, 0xF7        ; ADC_DIV = 0
        LDI  R1, 0
        ST   R1, [R7]
        LDI  R7, 0xF5        ; ADC_CTRL = EN + START + CH1
        LDI  R1, 0x13
        ST   R1, [R7]
        LDI  R7, 0xFC        ; R7 -> ADC_STAT
        LDI  R2, 0x10        ; mask: EMPTY bit
waitB:  LD   R1, [R7]
        AND  R1, R1, R2      ; Z = 1 when EMPTY = 0
        BNZ  waitB           ; still empty -> poll again
        LDI  R7, 0xFB        ; ADC_RCH (no pop)
        LD   R1, [R7]
        LDI  R6, 0x81
        ST   R1, [R6]        ; MEM[81] = 81 (valid, ch1)
        LDI  R7, 0xFA        ; ADC_DATA (pops the FIFO)
        LD   R1, [R7]
        LDI  R6, 0x82
        ST   R1, [R6]        ; MEM[82] = 56 (1.111 V)

; ===== Part C: timer overflow starts the ADC (channel 2), 4 samples =====
        LDI  R7, 0xF1        ; TMR_PRESC = 3   (tick every 4 clocks)
        LDI  R1, 3
        ST   R1, [R7]
        LDI  R7, 0xF2        ; TMR_LOAD = 24   (period 4 x 25 = 100 clocks)
        LDI  R1, 24
        ST   R1, [R7]
        LDI  R7, 0xF3        ; TMR_CMP = 12
        LDI  R1, 12
        ST   R1, [R7]
        LDI  R7, 0xF5        ; ADC_CTRL = EN + TRIG=overflow + CH2
        LDI  R1, 0x25
        ST   R1, [R7]
        LDI  R7, 0xF0        ; TMR_CTRL = EN -> timer starts
        LDI  R1, 1
        ST   R1, [R7]
        LDI  R6, 0x83        ; RAM pointer
        LDI  R5, 4           ; loop counter
        LDI  R4, 1
        LDI  R2, 0x10        ; EMPTY mask
        LDI  R7, 0xFC        ; R7 -> ADC_STAT
waitC:  LD   R1, [R7]
        AND  R1, R1, R2
        BNZ  waitC
        LDI  R3, 0xFB        ; ADC_RCH
        LD   R1, [R3]
        ST   R1, [R6]
        ADDI R6, 1
        LDI  R3, 0xFA        ; ADC_DATA
        LD   R1, [R3]
        ST   R1, [R6]
        ADDI R6, 1
        SUB  R5, R5, R4      ; counter - 1
        BNZ  waitC
        LDI  R7, 0xF0        ; stop the timer
        LDI  R1, 0
        ST   R1, [R7]
        LDI  R7, 0xF5        ; switch the ADC off
        ST   R1, [R7]
        LDI  R7, 0xFE        ; R7 -> IRQ_STAT
        LD   R1, [R7]
        LDI  R6, 0x8B
        ST   R1, [R6]        ; MEM[8B] = 07 (OVF | CMP | EOC)
        LDI  R1, 0x04
        ST   R1, [R7]        ; write 1 to clear EOC only
        LD   R1, [R7]
        LDI  R6, 0x8C
        ST   R1, [R6]        ; MEM[8C] = 03

; ===== Part D: window comparator raises the irq pin =====
        LDI  R1, 0xFF
        ST   R1, [R7]        ; clear all flags (R7 = IRQ_STAT)
        LDI  R7, 0xF9        ; THR_HI = 100
        LDI  R1, 100
        ST   R1, [R7]
        LDI  R7, 0xFD        ; IRQ_EN = ADC_WD
        LDI  R1, 0x08
        ST   R1, [R7]
        LDI  R7, 0xF5        ; ADC_CTRL = EN + START + CH3
        LDI  R1, 0x33
        ST   R1, [R7]
        LDI  R7, 0xFE        ; R7 -> IRQ_STAT
        LDI  R2, 0x04        ; EOC mask
waitD:  LD   R1, [R7]
        AND  R1, R1, R2
        BZ   waitD           ; EOC not set yet -> poll again
        LD   R1, [R7]
        LDI  R6, 0x8D
        ST   R1, [R6]        ; MEM[8D] = 0C (EOC | WD)
        LDI  R3, 0xFA
        LD   R1, [R3]
        LDI  R6, 0x8E
        ST   R1, [R6]        ; MEM[8E] = E8 (3.0 V = 232 > 100)
        LDI  R1, 0x0C
        ST   R1, [R7]        ; acknowledge: irq pin goes low
        LDI  R3, 0xFD
        LDI  R1, 0
        ST   R1, [R3]        ; IRQ_EN = 0

; ===== Part F: queue two results, pointer arithmetic, two pops =====
        LDI  R7, 0xF5
        LDI  R1, 0x03        ; EN + START + CH0
        ST   R1, [R7]
        LDI  R3, 0xFC        ; R3 -> ADC_STAT
        LDI  R2, 0x10
waitF1: LD   R1, [R3]
        AND  R1, R1, R2
        BNZ  waitF1          ; wait for result 1
        LDI  R1, 0x13        ; EN + START + CH1
        ST   R1, [R7]
        LDI  R2, 0x02        ; LEVEL bit 1 (level = 2)
waitF2: LD   R1, [R3]
        AND  R1, R1, R2
        BZ   waitF2          ; wait for result 2
        LDI  R7, 0xFA
        ADD  R4, R7, R0      ; R4 = 0xFA by the ALU: must NOT pop
        LD   R1, [R4]        ; 1st pop
        LD   R2, [R4]        ; 2nd pop (back-to-back)
        LDI  R6, 0x8F
        ST   R1, [R6]        ; MEM[8F] = 1F (0.40 V)
        LDI  R6, 0x90
        ST   R2, [R6]        ; MEM[90] = 56 (1.111 V)
        LD   R1, [R3]
        LDI  R6, 0x91
        ST   R1, [R6]        ; MEM[91] = 10 (empty)

; ===== Part E: PWM 30 % (PRESC 0, LOAD 9, CMP 3), then stop the CPU =====
        LDI  R7, 0xF1
        LDI  R1, 0
        ST   R1, [R7]
        LDI  R7, 0xF2
        LDI  R1, 9
        ST   R1, [R7]
        LDI  R7, 0xF3
        LDI  R1, 3
        ST   R1, [R7]
        LDI  R7, 0xF0
        LDI  R1, 1
        ST   R1, [R7]        ; timer runs on after HLT
        HLT
