; PUTACO-8 ECHO PROGRAM

; Declares a constant value
.constant IO_DATA, 0
.constant IO_STATUS, 1
.constant RXF, 1
.constant TXE, 2

restart:
    LD   IO_STATUS
    AND  3              ; (TXE | RXF)
    SUB  3           
    JNZ  restart
    LD   IO_DATA
    ST   IO_DATA
