	TITLE	'BOOT LOADER MODULE FOR CP/M 3.0'

	; DEFINE LOGICAL VALUES:
TRUE		EQU	-1
FALSE		EQU	NOT TRUE

	; DETERMINE IF FOR BANK SELECT OR NOT:
BANKED		EQU	FALSE	;<--------------- BANKED VERSION

	; DEFINE PUBLIC LABELS:
	PUBLIC	?INIT,?LDCCP,?RLCCP,?TIME
	PUBLIC	OUT$BLOCKS,NMB
	PUBLIC	@SPIW,@SPIR,@SELCS
	PUBLIC	@year,@mon,@day,@days

	; EXTERNALLY DEFINED ENTRY POINTS AND LABELS:
	EXTRN	?PMSG,?CONIN,?CONOUT,?CO
	EXTRN	@CIVEC,@COVEC,@AIVEC,@AOVEC,@LOVEC
	EXTRN 	@CBNK,?BNKSL

	IF	BANKED
	EXTRN	BANKBUF		;128 BYTE BUFFER IN MOVE MODULE FOR USE
				; DURING COLD AND WARM BOOTS
	ENDIF

	EXTRN	@SEC,@MIN,@HOUR,@DATE	;FIELDS HOLDING CURRENT TIME AND DATE


	; INCLUDE Z-80 MACROS:
	MACLIB	Z80


	; SOME MISCELLANEOUS EQUATES:
BDOS		EQU	5
CR		EQU	13	;ASCII CARRIAGE RETURN
LF		EQU	10	;ASCII LINEFEED
;
;	PORT ASSIGNMENTS
;
SDCARDBASE	EQU	06CH

SDDATAOUT	EQU	SDCARDBASE		; (6CH) Data TO port to SD CONTRROLLER
SDDATAIN	EQU	SDCARDBASE		; (6CH) Data TO port to SD CONTRROLLER
SPEEDPORT	EQU	SDCARDBASE+1		; (6DH) HIGH TO READ/WRITE SECTORS WITH HIGH SPEED SPI CLOCK
SDCSPORT	EQU	SDCARDBASE+2		; (6EH) SD Select Port
SDSTATUS	EQU	SDCARDBASE+2		; (6EH) SD Status Port
SDRW		EQU	SDCARDBASE+3		; (6FH) Port to pulse SPI Read/Write

HIGHSPEED	EQU	01H;			; Select SPI 10MHz CLK
LOWSPEED	EQU	00H			; Select SPI 4KHz CLK (Default on startup)
SDCSA		EQU	0FEH			; CS* select bit for SD Card drive A
SDCSB		EQU	0FDH			; CS* select bit for SD Card drive B 
SDBUSY		EQU	01H;
SDCSREADA	EQU	80H;			; Bit to test if Drive A CS* pin is low (not currently used)
SDCSREADB	EQU	40H;			; Bit to test if Drive B CS* pin is low (not currently used)

SPIBASEPORT	EQU	068H			; Base I/O port fot SPI module
SPIADDRESSOUT	EQU	SPIBASEPORT		; 68H, Data OUT port from SPI module to RTC
SPIDATAOUT	EQU	SPIBASEPORT+1		; 69H, Data OUT port from SPI module to RTC
SPIDATAIN	EQU	SPIBASEPORT+1		; 69H, Data IN from EEPROM
SPICS		EQU	SPIBASEPORT+2		; 6AH, CS Data OUT port to SPI/EEPROM module
SPISTATUS	EQU	SPIBASEPORT+2		; 6AH, Busy Flag IN port from SPI/EEPROM

SPIREAD	EQU	SPIBASEPORT+3		; 6B, Read pulse to SPI module
SPIWRITE	EQU	SPIBASEPORT+3		; 6B, Write pulse to SPI module

RTCCSLOW		EQU	00H		; Bit 0 has CS  (Note, HIGH to select chip)
RTCCSHIGH		EQU	01H			

RTCSECONDS	EQU	0H			;All registers OR 80H for WRITE Address
RTCMINUTES	EQU	1H
RTCHOURS	EQU	2H
RTCDAY		EQU	3H
RTCDATE		EQU	4H
RTCMONTH	EQU	5H
RTCYEAR		EQU	6H

RTCCTLREG	EQU	0FH
RTCSTATUSREG	EQU	10H
RTCRAM		EQU	20H			;20H -- 7FH

ENABLEOSC	EQU	80H			;Bit to enable/start the RTC chip (0=start, 1=stop)
WP		EQU	40H			;Write Protect. Bit must be 0 to alter any other register. 
						;Note alarms etc are not implemented in this simple example.
;
	; WE CAN DO INITIALIZATION FROM BANKED MEMORY (IF WE HAVE IT):
	IF	BANKED
	DSEG	; INIT DONE FROM BANKED MEMORY
	ELSE
	CSEG	; INIT TO BE DONE FROM COMMON MEMORY
	ENDIF


	;;;;; ?INIT
	; HARDWARE INITIALIZATION OTHER THAN CHARACTER AND DISK I/O:
?INIT:
	; ASSIGN CONSOLE INPUT AND OUTPUT TO CRT:
	LXI	H,8000H		;SIGNIFIES DEVICE 0
	SHLD	@CIVEC		;CONSOLE INPUT VECTOR
	SHLD	@COVEC		;CONSOLE OUTPUT VECTOR

	; ASSIGN PRINTER TO LPT:
	LXI	H,4000H		;SIGNIFIES DEVICE 1
	SHLD	@LOVEC		;LIST OUTPUT VECTOR

	; ASSIGN AUX TO CRT1:
	LXI	H,02000H	;SIGNIFIES DEVICE 2
	SHLD	@AIVEC		;AUXILLIARY INPUT VECTOR
	SHLD	@AOVEC		;AUXILLIARY OUTPUT VECTOR
NMB	equ	10h	
	mvi	b,RTCCTLREG OR 80H
; Enable osc, disable wp , turn off int, disable alarm bits
	mvi	c,0
	call	WRITESPI
        ; PRINT THE SIGN-ON MESSAGE:
        LXI     H,SIGNON$MSG    ;POINT TO IT
        JMP     ?PMSG           ;AND PRINT IT

;
	;;;;; OUT$BLOCKS
	; ROUTINE OUTPUTS SPECIFIED # BYTES TO SPECIFIED OUTPUT PORTS:
	IF	BANKED
	CSEG			;WE WANT THIS ROUTINE IN COMMON MEMORY
	ENDIF
OUT$BLOCKS:
	MOV	A,M		;GET A BYTE FROM THE BLOCK
	ORA	A		;END OF OUTPUT BLOCK ?
	RZ			;THEN DONE!!
	MOV	B,A		;ELSE PUT # BYTES TO SEND OUT IN [B]
	INX	H		;POINT TO PORT TO SEND TO
	MOV	C,M		;GET IT TO [C]
	INX	H		;POINT TO 1ST BYTE OF BLOCK TO SEND OUT
	OUTIR			;Z-80 BLOCK OUTPUT
	JR	OUT$BLOCKS


	;;;;; ?LDCCP
	; THIS ROUTINE IS ENTERED TO LOAD THE CCP.COM FILE INTO THE TPA BANK
	;  AT SYSTEM COLD START:
?LDCCP:
	; SET UP THE FCB FOR THE FILE OPERATION:
	XRA	A		;ZERO EXTENT
	STA	CCP$FCB+15
	LXI	H,0		;START AT BEGINNING OF FILE
	SHLD	FCB$NR

	; TRY TO OPEN THE CCP.COM FILE:
	LXI	D,CCP$FCB	;POINT TO FCB
	CALL	OPEN		;ATTEMPT THE OPEN OPERATION
	INR	A		;WAS IT ON THE DISK ?
	JRNZ	CCP$FOUND	;YES -- GO LOAD IT

	; WE ARRIVE HERE WHEN CCP.COM FILE WASN'T FOUND:
	LXI	H,CCP$MSG	;REPORT THE ERROR
	CALL	?PMSG
	CALL	?CONIN		;GET A RESPONSE
	JR	?LDCCP		;AND TRY AGAIN

	; FILE WAS OPENED OK -- READ IT IN:
CCP$FOUND:
	LXI	D,0100H		;LOAD AT BOTTOM OF TPA
	CALL	SETDMA		;BY SETTING THE NEXT DMA ADDRESS
	LXI	D,128		;SET MULTI SECTOR I/O COUNT
	CALL	SETMULTI	; TO ALLOW UP TO 16K BYTES IN ONE OPERATION
	LXI	D,CCP$FCB	;POINT TO THE FCB
	CALL	READ		;AND READ THE CCP IN

	; FOLLOWING CODE FOR BANKED SYSTEMS -- MOVES CCP IMAGE TO BANK 2
	;  FOR LATER RELOADING AT WARM STARTS:
	IF	BANKED
	LXI	H,0100H		;GET CCP IMAGE FROM START OF TPA
	MVI	B,25		;TRANSFER 25 LOGICAL SECTORS
	LDA	@CBNK		;GET CURRENT BANK
	PUSH	PSW		;AND SAVE IT
LD$1:
	PUSH	B		;SAVE SECTOR COUNT
	MVI	A,1		;SELECT TPA BANK
	CALL	?BNKSL
	LXI	B,128		;TRANSFER 128 BYTES TO TEMPORARY BUFFER
	LXI	D,BANKBUF	;TEMPORARY BUFFER ADDR IN [DE]
	PUSH	H		;SAVE SOURCE ADDRESS
	PUSH	D		;AND DESTINATION
	PUSH	B		;AND COUNT
	LDIR			;BLOCK MOVE SECTOR TO TEMPORARY BUFFER
	MVI	A,2		;SELECT BANK TO SAVE CCP IN
	CALL	?BNKSL
	POP	B		;GET BACK COUNT
	POP	H		;LAST DESTINATION WILL BE NEW SOURCE ADDR
	POP	D		;LAST SOURCE WILL BE NEW DESTINATION
	LDIR			;BLOCK MOVE SECTOR FROM BUFFER TO ALTERNATE
				; BANK
	XCHG			;NEXT ADDR WILL BE NEW SOURCE ADDR
	POP	B		;GET BACK SECTOR COUNT
	DJNZ	LD$1		;DROP SECTOR COUNT AND LOOP TILL DONE...
	POP	PSW		;WHEN DONE -- RESTORE ORIGINAL BANK
	JMP	?BNKSL
	ELSE

	; IF NON-BANKED WE RETURN THROUGH HERE:
	RET
	ENDIF


	;;;;; ?RLCCP
	; ROUTINE RELOADS CCP IMAGE FROM BANK 2 IF BANKED SYSTEM OR FROM THE
	;  DISK IF NON-BANKED VERSION:
?RLCCP:
	IF	BANKED
	; FOLLOWING CODE FOR BANKED VERSION:
	LXI	H,0100H		;GET CCP IMAGE FROM START OF ALTERNATE BUFFER
	MVI	B,25		;TRANSFER 25 LOGICAL SECTORS
	LDA	@CBNK		;GET CURRENT BANK
	PUSH	PSW		;AND SAVE IT
RL$1:
	PUSH	B		;SAVE SECTOR COUNT
	MVI	A,2		;SELECT ALTERNATE BANK
	CALL	?BNKSL
	LXI	B,128		;TRANSFER 128 BYTES TO TEMPORARY BUFFER
	LXI	D,BANKBUF	;TEMPORARY BUFFER ADDR IN [DE]
	PUSH	H		;SAVE SOURCE ADDRESS
	PUSH	D		;AND DESTINATION
	PUSH	B		;AND COUNT
	LDIR			;BLOCK MOVE SECTOR TO TEMPORARY BUFFER
	MVI	A,1		;PUT CCP TO TPA BANK
	CALL	?BNKSL
	POP	B		;GET BACK COUNT
	POP	H		;LAST DESTINATION WILL BE NEW SOURCE ADDR
	POP	D		;LAST SOURCE WILL BE NEW DESTINATION
	LDIR			;BLOCK MOVE SECTOR FROM BUFFER TO TPA BANK
	XCHG			;NEXT ADDR WILL BE NEW SOURCE ADDR
	POP	B		;GET BACK SECTOR COUNT
	DJNZ	RL$1		;DROP SECTOR COUNT AND LOOP TILL DONE...
	POP	PSW		;GET BACK LAST CURRENT BANK #
	JMP	?BNKSL		;SELECT IT AND RETURN
	ELSE

	; FOLLOWING CODE IS FOR NON-BANKED VERSIONS:
	JMP	?LDCCP		;JUST DO LOAD AS THOUGH COLD BOOT
	ENDIF

; SPI code
;  We will need to generalize this code a bit to make is usefull for
;  other kernel routines.
	db	'SPI'
SELCS:		; this may only apply to the rtc
@SELCS:
	out	SPICS	; a = device select
	ret

WRITESPI:	; [c] contains DATA, [B] contains register address
@SPIW:
	mov	a,c
	out	SPIADDRESSOUT	; Send data first
	mov	a,b
	out	SPIDATAOUT	; Send address
	out	SPIWRITE	; Send a write pulse
	call	DELAY
	ret
READSPI:
@SPIR:
READSPI1:
	mov	a,b	; send address
	out	SPIDATAOUT
	in	SPIREAD
	call	DELAY
	in	SPIDATAIN
	push	psw
	call	DELAY
	pop	psw
	ret
DELAY:	push	h
	lxi	hl,40h
DELAY1:	dcx	h
	mov	a,h
	ora	l
	jnz	DELAY1
	pop	hl
DELAY2:	in	SPISTATUS
	ora	a
	jnz	DELAY2
	ret
	
	;;;;; ?TIME
	; ROUTINE SETS/GETS TIME:
; since cp/m keeps date in days from 
; jan 1 1978 we will have to
; calculate the date with that in mind.

;  note that the calculations need to be 
;  16bit since some of the
;  values are larger than 256

; Number of days from start of a year 
; On non leap years we subtract one day per year.
dom:	dw	0,0,30,58,89,119,150,180,211,241,272,303,333,365,0
@days:
days:	dw	0
@year:
year:	dw	0
@mon:
mon:	db	0
@day:
day:	db	0
i:	dw	0
; 
; cp/m diliveres the date values as bcd, so month, and day 
; are 1 byte 2 digit bcd numbers.  
; The date is an unsigned 16bit number.
;
;  we will need code to convert bcd to binary and binary to bcd
;

; the epoch translation will need to go both ways.  When the user
; requests the date, we will need to convert the day/month/year values
; in the clock to days since jan 1 1978.

frmepoch: equ	$
; hl = days since jan 1 1978
; on exit
; hl = year
; d = month
; e = day
	shld	days	; save the days number
;        for(i = 1978; ; i++){
	lxi	h,1978
	shld	i	; init the counter	
	jmp	frm1
frm:	lhld	i
	inx	h
	shld	i	; i++
;                if(not(i mod 4))
frm1:	lhld	i
	lxi	d,4
	xchg		; mod de%hl -> hl
;	mod
	call	usmod	; unsigned mod (de%hl) res in hl
	mov	a,h
	ora	l
	jz	frmle
;                        days -= 365;
	lhld	days
	lxi	d,-365
	jmp	save1
;                else
;                         days -= 366;
frmle:	lhld	days
	lxi	d,-366
save1:	equ	$
	dad	d
	shld	days
;                year = i+1;
	lhld	i
	inx	h
	shld	year
;                if(days <= 365)
	lhld	days
	lxi	d,365
;	comp	lt
;  c if hl < de
	call	uslt
	jnc	frm
;                {
;                        for(i=1;i<13;i++){
	lxi	h,1
	shld	i
	jmp	frmdm1
frmdm:	lhld	i
	inx	h
	shld	i
;                        if(days <= dom[i+1])
frmdm1:	lhld 	i
	inx	h
	dad	h
	lxi	d,dom
	dad	d
	mov	e,m
	inx	h
	mov	d,m
	lhld	days
;	comp	lt
;  c if hl < de
	call	uslt
	jnc	frmdm
;                        {
;                        month = i;
	lhld	i
	mov	a,l
	sta	mon
;                        days -= dom[i];
	lhld	i
	dad	h
	lxi	d,dom
	dad	d
	mov	e,m
	inx	h
	mov	d,m
	lhld	days
	xchg
;	subt
	call	xyz	
;                        day = days;
	mov	a,l
	sta	day
;
	lhld	year 
	lda	mon
	mov	d,a
	lda	day
	mov	e,a
	ret
xyz:	mov	a,e
	sub	l
	mov	l,a
	mov	a,d
	sbb	h
	mov	h,a
	ret
usmod   mov     a,h
        ora     l
        rz
        push    d
        push    h
        call    usdiv
        pop     d
        call    usmul
        mov     a,h
        cma
        mov     h,a
        mov     a,l
        cma
        mov     l,a
        inx     h
        pop     d
        dad     d
        ret
useq    mov     a,l
        cmp     e
        rnz
        mov     a,h
        cmp     d
        ret
uslt    xchg
        mov     a,d
        cmp     h
        rnz
        mov     a,e
        cmp     l
        ret

usdiv	mov	a,h	;unsigned divide: return (DE / HL) in HL
	ora	l	;return 0 if HL is 0
	rz
	push	b
	call	a172695
	mov	h,b
	mov	l,c
	pop	b
	ret
a172695	mvi	b,1
b172695	mov	a,h
	ora	a
	jm	c172695
	dad	h
	inr	b
	jmp	b172695
c172695	xchg
d172695	mov	a,b
	lxi	b,0
e172695	push	psw
f172695	call	h172695
	jc	g172695
	inx	b
	push	d
	mov	a,d
	cma
	mov	d,a
	mov	a,e
	cma
	mov	e,a
	inx	d
	dad	d
	pop	d
g172695	xra	a
	mov	a,d
	rar
	mov	d,a
	mov	a,e
	rar
	mov	e,a
	pop	psw
	dcr	a
	rz
	push    psw
	mov	a,c
	ral
	mov	c,a
	mov	a,b
	ral
	mov	b,a
	jmp	f172695
h172695	mov	a,h	;this returns C if HL < DE
	cmp	d       ; unsigned compare 
	rc
	rnz
	mov	a,l
	cmp	e
	ret

usmul	push	b	; unsigned multiply return (de*hl) in hl
	call	usm2
	pop	b
	ret
usm2	mov	b,h
	mov	c,l
	lxi	h,0
usm3	mov	a,b
	ora	c
	rz
	mov	a,b
	rar
	mov	b,a
	mov	a,c
	rar
	mov	c,a
	jnc	usm4
	dad	d
usm4	xchg
	dad	h
	xchg	
	jmp	usm3
; calculate number of days from jan 1 1978 to the given date
;
;  hl = year (like 2023)
;  d = month (like 1-12)
;  e = day (like 1-33)
; on exit
; hl = days since jan 1 1978

toepoch: equ $
	dcx	h	; tweek year
	shld	year	; save year
	mov	a,d
	sta	mon	; save month
	mov	a,e
	sta	day	; save day
	lxi	h,0
	shld	days	
;
; for(i=1978;i<year;i++)
	lxi	h,1978
	shld	i
	jmp	nxtyr1
; {
nxtyr:	equ	$
	lhld	i	; i++ 
	inx	h
	shld	i	
nxtyr1:
;	if(not(i/4) ) 
	lhld	i
	lxi	d,4
	xchg
;	mod
	call	usmod	; unsigned mod (de mod hl) res in hl
	mov	a,h
	ora	l
	jz	lex
;	{
;		days += 365;
nle	lhld	days
	lxi	d,365
	jmp	lecom
;	}
;	else 
;	{
;		days += 366; 
lex	lhld	days
	lxi	d,366
;
lecom:	dad	d
	shld	days
;	}
; }
eloop:	equ	$
	lhld	year	
	xchg
	lhld	i
;	comp	eq	
;  z if hl == de
	call	useq
	jnz	nxtyr	

; TBD: if we are in a leap year, then feb might add a day.		
; days += dom[month];
; now for months
	lxi	h,0
	lda	mon	; month index is mon*2
	mov	l,a
	push	h
	pop	d
	dad	d
	lxi	d,dom	; dom[mon*2]
	dad	d
	mov	e,m	; copy digits
	inx	h
	mov	d,m

	lhld	days	; get day count	
	dad	d	; add it on
	shld	days	; save it
; days now has nr of days from jan 1 1978 until current date.
	xchg
	lda	day	; get day number
	inr	a	; add 1 day BUG ALERT
	lxi	h,0
	mov	l,a
	dad	d	; add to days
	shld	days
	ret	
;
;  This should work for about 75 more years
;

;
?TIME:
	mov	a,c	; c is flag
	ora	a
	jnz	SETT	; ff = set
GETT	equ	$

; the year month and day, need to be converted to
; cpm time format
;The time of day is kept as four fields. @DATE is a binary word containing the 
;number of days since 31 December 1977. The bytes @HOUR, @MIN, and @SEC in the 
;System Control Block contain the hour, minute, and second in 
;Binary Coded Decimal (BCD) format.
	mvi	a,RTCCSHIGH	!call	SELCS
	mvi	b,RTCYEAR	!call	READSPI	
	push	psw
	mvi	a,RTCCSLOW 	!call	SELCS
	pop	psw
; the TOD chip (dc1305) stores year, mon, day as BCD digits.
; we need to convert them to binary.
	call	bcd2bin		; convert year
	lxi	h,0
	mov	l,a
; a note to the future, this will fail after 2100
	lxi	d,2000		; and add the century
	dad	d		; year is now correct
	shld	year		; save result
; now get the month
	mvi	a,RTCCSHIGH	!call	SELCS
	mvi	b,RTCMONTH	!call	READSPI 
	push	psw
	mvi	a,RTCCSLOW 	!call	SELCS
	pop	psw
	call	bcd2bin		; convert month to binary
	sta	mon
	mvi	a,RTCCSHIGH	!call	SELCS
	mvi	b,RTCDATE 	!call	READSPI 
	push	psw
	mvi	a,RTCCSLOW 	!call	SELCS
	pop	psw
	call	bcd2bin
	sta	day
; we collected and converted the TOD data
;
	lhld	year
	lda	mon
	mov	d,a
	lda	day
	mov	e,a
; now that month, day, year are in binary format
; compute the number of days from jan 1 1978
	call	toepoch
	shld	@DATE
; cpm expects hrs/min/sec in BCD format.
	mvi	a,RTCCSHIGH	!call	SELCS
	mvi	b,RTCHOURS 	!call	READSPI !sta	@HOUR
	mvi	a,RTCCSLOW 	!call	SELCS
	mvi	a,RTCCSHIGH	!call	SELCS
	mvi	b,RTCMINUTES 	!call	READSPI !sta	@MIN
	mvi	a,RTCCSLOW 	!call	SELCS
	mvi	a,RTCCSHIGH	!call	SELCS
	mvi	b,RTCSECONDS 	!call	READSPI !sta	@SEC
	mvi	a,RTCCSLOW 	!call	SELCS
	ret
;
; convert bcd bytes to binary for toepoch
; the clock chip runs in bcd, the @DATE field is binary.
; so, get the bcd to binary format.
;  using a cheap hack that should work for about 10 years.
;
b2b:	dw	0000h,0101h,0202h,0303h,0404h,0505h,0606h,0707h,0808h
	dw	0909h,0a10h,0b11h,0c12h,0d13h,0e14h,0f15h,1016h,1117h
	dw	1218h,1319h,1420h,1521h,1622h,1723h,1824h,1925h,1a26h
	dw	1b27h,1c28h,1d29h,1e30h,1f31h,2032h,2133h,2234h,2335h
	dw	2436h,2537h,2638h,2739h,2840h,2941h,2a42h,2b43h,2c44h
	dw	2d45h,2e46h,2f47h,3048h,3149h,3250h,3351h,3452h,3553h
	dw	3654h,3755h,3856h,3957h,3a58h,3b59h,0FFFFH
		;3c60, 3d61, 3e62, 3f63, 4064, 4165, 4266, 4367, 4468,
		;4569, 4670, 4771, 4872, 4973, 4a74, 4b75, 4c76, 4d77,
		;4e78, 4f79, 5080, 5181, 5282, 5383, 5484, 5585, 5686,
		;5787, 5888, 5989,
bcd2bin:
	mov	b,a	; copy BCD value of year.
	mvi	c,0
	lxi	h,b2b	; pointer to convertion table.
b2bl1:	
	mov	a,b
	cmp	m	; does the year match
	jz	b2bdn	
	mvi	a,0ffh
	cmp	m
	rz
	inx	h
	inx	h
	jmp	b2bl1
b2bdn:	inx	h
	mov	a,m	; fetch convertions
	ret
;
; cp/m sets up the DATE,HOUR,MIN,SEC storage to
; the values entered by the user.
; To get those values into the RTC we need to read
; them from storage and convert and write to the 
; RTC clock
;
SETT	equ	$	
	lhld	@DATE
;
	call	frmepoch
	lhld	year	; year is 2023, needs to be 23
	lxi	d,-2000
	dad	d
	mvi	a,RTCCSHIGH !  	call	SELCS
	mov	a,l
	call	binbcd		; in BCD
	mvi	b,RTCYEAR OR 80H ! mov c,a ! call WRITESPI	
	mvi	a,RTCCSLOW !	call	SELCS
	mvi	a,RTCCSHIGH !  	call	SELCS
	lda	mon
	call	binbcd		; in BCD
	mvi	b,RTCMONTH OR 80H ! mov c,a ! call WRITESPI	
	mvi	a,RTCCSLOW !	call	SELCS
	mvi	a,RTCCSHIGH !  	call	SELCS
	lda	day	; in BCD
	call	binbcd	
	mvi	b,RTCDAY OR 80H ! mov c,a ! call WRITESPI	
	mvi	a,RTCCSLOW !	call	SELCS
	
	; needs more work
	mvi	a,RTCCSHIGH !  	call	SELCS
	lda	@HOUR! mvi b,RTCHOURS OR 80H  ! mov c,a! call	WRITESPI
	mvi	a,RTCCSLOW !	call	SELCS
	mvi	a,RTCCSHIGH !  	call	SELCS
	lda	@MIN ! mvi b,RTCMINUTES OR 80H! mov c,a! call	WRITESPI
	mvi	a,RTCCSLOW ! 	call	SELCS
	mvi	a,RTCCSHIGH !  	call	SELCS
	lda	@SEC ! mvi b,RTCSECONDS OR 80H! mov c,a! call	WRITESPI	
	mvi	a,RTCCSLOW ! 	call	SELCS
	RET			;Just return in this simple version
;
; keep
binbcd: ora      a
        rz
        push    b
        mov      b,a
        xra     a
;
binbcd1:adi     1
        daa
        dcr     b
        jnz	binbcd1
        pop     b
        ret

	IF	BANKED
	CSEG
	ENDIF

	;;;;;
	; CP/M BDOS FUNCTION INTERFACES

	; OPEN FILE:
OPEN:
	MVI C,15 ! JMP BDOS		; OPEN FILE CONTROL BLOCK

	; SET DMA ADDRESS:
SETDMA:
	MVI C,26 ! JMP BDOS		; SET DATA TRANSFER ADDRESS

	; SET MULTI SECTOR I/O COUNT:
SETMULTI:
	MVI C,44 ! JMP BDOS		; SET RECORD COUNT

	; READ FILE RECORD:
READ:
	MVI C,20 ! JMP BDOS		; READ RECORDS

	; CCP NOT FOUND ERROR MESSAGE:
CCP$MSG:
	DB	CR,LF,'BIOS ERR ON A: NO CCP.COM FILE',0


	; FCB FOR CCP.COM FILE LOADING:
CCP$FCB:
	DB	1		;AUTO-SELECT DRIVE A
	DB	'CCP     COM'	;FILE NAME AND TYPE
	DB	0,0,0,0
	DS	16
FCB$NR:	DB	0,0,0


	; SYSTEM SIGN-ON MESSAGE:
SIGNON$MSG:
	DB	CR,LF,LF,'CP/M VERSION 3.0 (NON-BANKED)' 
	DB	CR,LF,'A: & B: = IDE CF Memory Disk'
	DB	CR,LF,0
	END
