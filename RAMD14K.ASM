;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; 
; RAMD14K - Ramdisk for all 64K Atarai XLs 

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Special Patch program to allow 800XL owners to use
;   Atari DOS 2.5 with a small RamDisk.
;
; Theoretical size of disk is 16KBytes,
;   but 2KBytes are lost to the I/O registers
;   at $D000 to $D7FF and about 1KBytes
;   are lost to overhead.   Net is just
;   over 13KBytes.
;
;
; See COMPUTE! magazine, October 1986 issue,
;   for accompanying article:
;      INSIGHT: ATARI
;
; Program by Bill Wilkinson
;   released to the public domain
;
; Article is Copyright (c) 1986 by COMPUTE!
;   Contact COMPUTE! magazine for reprint
;   permission, etc.
;
; Extended and trimmed by Holger Janz, April 2019
;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Equates used to call CIO
;

XIO.FMTDD = 254 ; Format command
XIO.PRINT = 9   ; Print line
XIO.OPEN  = 3   ; Open
XIO.CLOSE = 12  ; Close
XIO.READ  = 4   ; Read
XIO.WRITE = 8   ; Write
XIO.GET   = 7   ; Get
XIO.PUT   = 11  ; Put

IOCB        =  $0340    ; address of first IOCB
IOCB.CMD    = IOCB+2    ; where command goes in IOCB
IOCB.BUF    = IOCB+4    ; buffer (or name) address
IOCB.BUFLEN = IOCB+8    ; max buffer length address
IOCB.AUX1   = IOCB+10   ; Auxilliary byte 1
IOCB.AUX2   = IOCB+11   ; Auxilliary byte 2

CIOV = $E456            ; the classic location

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; OS Equates
;

RTCLOKH = $12
RTCLOKM = $13
RTCLOKL = $14
CRITIC  = $42
NMIEN   = $d40e

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Miscellaneous vital locations, equated
;   values, and routines used by DOS 2.5

RAMIO    = $1481 ; start of RAMIO of DOS 2.5, end $14e7 = $66
RAMSYNC  = $12CB ; routine which synchronizes RamDisk transfers
WRTVTOC  = $1094 ; write current VTOC back to disk

VTOCPTR  = $45   ; pointer to VTOC in memory
DRVBYT   = $070a ; the infamous "1802" location
INITDOS  = $07e0 ; same as DOS 2.0 and others
FASTRAM  = $07DF ; flag:  + ==>> sync with VBI
PIABPORT = $D301 ; master bank selector, etc.

; DOS and DUP end pointer
NDOS     = $1D7C ; end of the system buffers and minidup
NDUP     = $3306 ; end of dup

MEMDUP   = $153f ; just before Mini-DUP
; Location that says which drive MEM.SAV and DUP.SYS
; are located on (contains ATASCII character--
; not just a byte value)

DISKBUF  = $0304 ; buffer address for read/write
DCBSEC   = $030A ; sector number in DCB
ZTEMP1   = $43   ; zero page temporary loc'n
E.NAK    = $8B   ; "NAK" error code from "drive"

VTOCSEC = $168   ; sector number of VTOC
DVDOTYP = 2      ; type in VTOC for DOS 2.5
DVMAXSC = 128-16-1-3-3 ; 128 sectors in 16KBytes,
;         less 16 sectors for 2KB I/O "hole"
;         less 1 sector for VTOC
;         less 3 sectors for shortened directory
;         less 3 sectors for BOOT (useless but needed)
; (all this to find max # of sectors on disk)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Addresses of subroutines that we must alter
;
PATCH.RAMIO   = $148D ; RamDisk "I/O" routine
PATCH.SETBANK = $12DE ; sets PIA to select proper bank

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Patch to RAMIO:
;
; At the beginning of RAMIO, DOS 2.5 validates
;   the sector number to be sure it gets a valid
;   bank number
;
; If the bank number is bad, the Y-register
;   is given an error code indicating the
;   "disk" returned a "NAK" code.
;
; We patch in where the bank number is being
;   checked...it used to be checked via
;   a "CMP #4" but now we have a smaller "DISK".
;
    org PATCH.RAMIO
    CMP #3      ; sector must be in banks 0,1,2
    BCC SECOK   ; it is...assume it is okay
    PLP         ; needed to clean up stack
    LDY #E.NAK  ; too bad...give error
    RTS         ; used to be "BNE" to a RTS...dumb!
SECOK
    JSR RAMSYNC ; synchronize and select bank
    LDA ZTEMP1  ; get sector # times 2
    LSR         ; now sector #
    LSR         ; now sector # divided by 2
    ORA #$C0    ; ensure address is in range ($C000-$FFFF)
; rest of code is okay!

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Patch to SETBANK:
;
; The entire routine is replaced
;
; ENTER:  A-register = 0,1,2,3,4
;         If 4, then Main Memory is needed (ROMs)
;         Else, RAM is needed.

    org PATCH.SETBANK
    ROR          ; If A-register was 4 on entry...
    ROR          ; ...then these 3 ROR's...
    ROR          ; ...will set the carry 
    PHP          ; so save the carry for a nonce
    LDA PIABPORT ; and get current bank select info
    LSR          ; strip it of its LSBit
    PLP          ; recover the carry...
    ROL          ; ...and carry becomes ROM select!!!
    STA PIABPORT ; changes RAM to ROM or v.v.
    RTS          ; saved a byte, actually!


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; 
; Start
;
; Up until now, we have just patched DOS 2.5.
;
; Now, we must do several steps:
;
;  1. Reinitialize DOS
;  2. FORMAT the RamDisk
;  3. Alter the VTOC
;  4. Copy DUP.SYS
;  5. Create MEM.SAV
;
; Step 3 is necessary because DOS 2.5's
;   FORMAT routine assumes (A) that a disk
;   is large enough that the VTOC and
;   DIRECTORY can occupy sectors $168 to
;   $170 and (B) that (except for the boot
;   sectors and the VTOC and DIRECTORY)
;   available sector are continuous from
;   1 to the max sector number.
;   We set bits to zero in the VTOC to
;   inform DOS 2.5 that the corresponding
;   sectors are not really there!

        org $4000 
start                   ; Start of code
; start message
        ldx #<msg.start
        ldy #>msg.start
        lda #msg.start.end-msg.start
        jsr print
; start setup
        ldx #<msg.setup
        ldy #>msg.setup
        lda #msg.setup.end-msg.setup
        jsr print        
; add drive to drive list
        lda #$00        ; set flag to say we need
        sta FASTRAM     ; synchronized transfers
; activate RAMDISK at D8:
        lda DRVBYT      ; to active drives...
        ora #$80        ; ...include this drive
        sta DRVBYT      ; and update the mask
        jsr INITDOS     ; including the drive table,
                        ; alloc buffer, etc.
; check for preformat (maybe there is already a ram disk)
        jsr check.vtoc
        tya
        bne prepare.ramdisk ; no ram disk
; there seems to be already a ramdisk
; check file name DUP.SYS set to D8:
        lda #'8'
        sta file.dup.NAME+1
; check for DUP.SYS on D8:
        ldx #$70
        lda #XIO.OPEN   
        sta IOCB.CMD,X
        lda #XIO.READ
        sta IOCB.AUX1,X
        lda #<file.dup.name
        sta IOCB.BUF,X
        lda #>file.dup.name
        sta IOCB.BUF+1,X
        jsr CIOV
        bmi dup.notfound
        jsr close
        bmi dup.notfound
; switch to D8: for MEM.SAV and DUP.SYS
        lda #'8'
        sta MEMDUP     ; set MEM.SAV and DUP.SYS drive
; finish 
dup.notfound
        rts             ; OK and we are done!

prepare.ramdisk
; *** (1) FORMAT
        ldx #<msg.format
        ldy #>msg.format
        lda #msg.format.end-msg.format
        jsr print
; format
        ldx #$70        ; we will use channel 7 for this
        lda #XIO.FMTDD  ; the format command
        sta IOCB.CMD,X  ; is first item on agenda!
        lda #<drv.name  ; LSB of address of drive name
        sta IOCB.BUF,X  ; to IOCB
        lda #>drv.name  ; then MSB
        sta IOCB.BUF+1,X ; also to IOCB
        jsr CIOV        ; call CIO to FORMAT the disk
        bmi oops1       ; but we can't handle an error! (do nothing)
; okay...time to patch the VTOC
        ldy #SIZE.RVTOC
loop
        lda NEW.RVTOC,Y ; get a byte of modified VTOC
        sta (VTOCPTR),Y ; and put it into system VTOC
        dey         ; more to do?
        bpl loop    ; yep
        jsr WRTVTOC ; so write out the modified VTOC

;*** (2) COPY DUP.SYS TO D8:
        ldx #<msg.copy
        ldy #>msg.copy
        lda #msg.copy.end-msg.copy
        jsr print
; start copy of DUP.SYS
        ldx #$70
        lda #XIO.OPEN
        sta IOCB.CMD,X
        lda #XIO.READ
        sta IOCB.AUX1,X
        lda #<file.dup.name
        sta IOCB.BUF,X
        lda #>file.dup.name
        sta IOCB.BUF+1,X
        jsr CIOV
oops1
        bmi oops2           ;NO DUP(?)
; read it into buffer
        ldx #$70
        lda #XIO.GET
        sta IOCB.CMD,X
        lda #<file.dup.size
        sta IOCB.BUFLEN,X
        lda #>file.dup.size
        sta IOCB.BUFLEN+1,X
        lda #<file.dup.buffer
        sta IOCB.BUF,X
        lda #>file.dup.buffer
        sta IOCB.BUF+1,X
        jsr CIOV
oops2
        bmi oops3
        jsr close
        bmi oops3
; file name DUP.SYS set to D8:
        lda #'8' ;
        sta file.dup.NAME+1
; now open for write
        ldx #$70
        lda #XIO.OPEN
        sta IOCB.CMD,X
        lda #XIO.WRITE
        sta IOCB.AUX1,X
        lda #<file.dup.name
        sta IOCB.BUF,X
        lda #>file.dup.name
        sta IOCB.BUF+1,X
        jsr  CIOV
oops3
        bmi  oops4
; write dup.sys to D8:
        ldx #$70
        lda #XIO.PUT
        sta IOCB.CMD,X
        lda #<file.dup.size
        sta IOCB.BUFLEN,X
        lda #>file.dup.size
        sta IOCB.BUFLEN+1,X
        lda #<file.dup.buffer
        sta IOCB.BUF,X
        lda #>file.dup.buffer
        sta IOCB.BUF+1,X
        jsr CIOV
OOPS4
        bmi  OOPS5
; close
        jsr close
        bmi  OOPS5

; only and only if format and copy OK, 
; switch to D8: for MEM.SAV and DUP.SYS
        lda #'8'
        sta MEMDUP     ; set MEM.SAV and DUP.SYS drive
        
;*** (3) CREATE MEM.SAV FILE
        ldx #<msg.create
        ldy #>msg.create
        lda #msg.create.end-msg.create
        jsr print
; start copy of DUP.SYS
        ldx #$70
        lda #XIO.OPEN
        sta IOCB.CMD,X
        lda #XIO.WRITE
        sta IOCB.AUX1,X
        lda #<file.mem.name
        sta IOCB.BUF,X
        lda #>file.mem.name
        sta IOCB.BUF+1,X
        jsr CIOV
OOPS5
        bmi oops6
; write mem.sav to d8:
        ldx #$70
        lda #XIO.PUT
        sta IOCB.CMD,X
        lda #<file.mem.size
        sta IOCB.BUFLEN,X
        lda #>file.mem.size
        sta IOCB.BUFLEN+1,X
        lda #<file.mem.buffer
        sta IOCB.BUF,X
        lda #>file.mem.buffer
        sta IOCB.BUF+1,X
        jsr CIOV
OOPS6
        bmi  oops7
; close channel
        jsr close
        bmi oops7

        rts         ; OK and we are done!

oops7
; set error code in message
        tya
        sec 
        sbc #100    ; error nums always are 1xx dec
        ldx #'0'-1  ; convert tens
count.tens
        inx 
        sec 
        sbc #10
        bpl count.tens ; the easy (slow) way
        clc
        adc #10+'0'
        stx msg.error.code
        sta msg.error.code+1
; error message
        ldx #<msg.error
        ldy #>msg.error
        lda #msg.error.end-msg.error
        jsr print
; close channel, just in case
        jsr close

        rts         ; ERROR and we are done!

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Messages
;

msg.start
        .byte 'RAMD14K FOR ATARI DOS II VERSION '
        .byte $a0,$0b2,$ae,$b5,$a0 ; invers _2.5_
msg.start.end

msg.setup
        .byte 'SET UP RAMDISK D8:', $9b
msg.setup.end

msg.format
        .byte 'FORMAT RAMDISK', $9b
msg.format.end

msg.copy
        .byte 'COPY DUP.SYS', $9b
msg.copy.end

msg.create
        .byte 'CREATE MEM.SAV', $9b
msg.create.end

msg.error
        .byte 'ERROR-  1' ; error code always >128
msg.error.code
        .byte '01',$9b
msg.error.end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; A string to hold drive name for XIO command
;

drv.name
        .byte 'D8:',$9b  
        
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; File names
;

file.dup.name
        .byte 'D1:DUP.SYS',$9b
file.dup.size   = 5126
file.dup.buffer = BUFFER

file.mem.name
        .byte 'D8:MEM.SAV',$9b
file.mem.size   = NDUP-NDOS
file.mem.buffer = NDOS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Close
;

close ; close channel in X
        ldx #$70
        lda #XIO.CLOSE
        sta IOCB.CMD,X
        jsr CIOV
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Check VTOC sector for pre formating
;
; return     Y=0   -> preformated
;            Y=1-3 -> wrong format
;

check.vtoc ; Check VTOC sector
; set DCBSEC and DISKBUF
        lda #<VTOCSEC
        sta DCBSEC
        lda #>VTOCSEC
        sta DCBSEC+1

        lda #<BUFFER
        sta DISKBUF
        lda #>BUFFER
        sta DISKBUF+1
; call RAMIONEW
        clc             ; read
        jsr RAMIO
; check first three bytes
        ldy #$03
        
        lda BUFFER
        cmp #DVDOTYP
        bne check.vtoc.end
        dey

        lda BUFFER+1
        cmp #<DVMAXSC
        bne check.vtoc.end
        dey

        lda BUFFER+2
        cmp #>DVMAXSC
        bne check.vtoc.end
        dey

check.vtoc.end
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; 
; Print Message
;
; IN    X,Y    low, high byte of address to message
;        A    length of message

print    ;print message
        sta IOCB.BUFLEN
        lda #$00
        sta IOCB.BUFLEN+1
        stx IOCB.BUF
        sty IOCB.BUF+1
        lda #XIO.PUT
        sta IOCB.CMD
        ldx #$00
        jsr CIOV
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;  New VTOC layout for 14KB RamDisk"
;
; Following are 74 bytes which define the appearance
;   of the VTOC for our 14KB RamDisk
;
; Some sneakies to observe:
;   even though we only use sector numbers
;   from $01 to $7F, we mark $68 through
;   $6B as being in use...this is because
;   our bank select routine maps sectos
;   $168 through $16B to the same memory
;   locations as those containing $68-$6B.
;   $168 is the VTOC, as is standard with
;   all DOS 2 versions, and $169 to $16B
;   are the directory.   Note that $169 to
;   $170 are normally used for directory,
;   but we have opted for a shortened directory
;   in order to give more file space...
;   our directory still allows 24 files...
;   surely more than enough for what is now
;   a 13KB RamDisk.
;
NEW.RVTOC
    .BYTE DVDOTYP ; DOS "2" family
    .WORD DVMAXSC ; max sector count
    .WORD DVMAXSC ; ditto...but this is "available" sectors
    .BYTE 0,0,0,0,0 ; 5 dummy bytes
    .BYTE $0F   ; sectors 0,1,2,3 in use
    ;           4-7 available
    .BYTE $FF,$FF,$FF ; sectors 8-$1f available
    ;           which uses memory: $C000 to $CFFF
    .BYTE 0,0   ; sectors $20-$2F
    ;           were $D000 to $D7FF, but that
    ;           is I/O area!!
    .BYTE $FF,$FF ; sectors $30-$3f
    ;           memory $D800 to $DFFF
    .BYTE $FF,$FF,$FF,$FF ; sectors $40-$5F
    ;           memory $E000 to $EFFF
    .BYTE $FF   ; sectors $60-$67
    .BYTE $0F   ; sectors $68-$6B marked as in use
    ;           because $168 to $16F are mapped to this
    ;           same bank, and we have chosen to allow
    ;           up to 24 files in the RamDisk
    ;           so we need 4 "holes" for the
    ;           VTOC and 3 directory sectors
    .BYTE $FF,$FF ; sectors $70-$7F
    ;           sectors $60-$7F = memory $F000-$FFFF
    .BYTE $80   ; sector $80 is same as sector $00...
    ;           ...at memory location $C000..
    ;           ...but sector $00 is not used, so we
    ;           ...CAN use sector $80!!
    .BYTE 0,0,0,0,0,0,0
    .BYTE 0,0,0,0,0,0,0,0 ; to sector $FF
    .BYTE 0,0,0,0,0,0,0,0
    .BYTE 0,0,0,0,0,0,0,0 ; to sector $17F
    .BYTE 0,0,0,0,0,0,0,0
    .BYTE 0,0,0,0,0,0,0,0 ; to sector $1FF ...
    ;           end of normal RamDisk
SIZE.RVTOC = *-NEW.RVTOC

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; 
; Buffer for copy

BUFFER  =  *+1


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; 
; Run address
        run start
