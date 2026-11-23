; PUTACO-8 ECHO PROGRAM

; Declares a constant value
.constant IO_DATA, 0
.constant IO_STATUS, 1
.constant RXF, 1
.constant TXE, 2

restart:
    LD   A, IO_STATUS
    AND  A, 3              ; (TXE | RXF)
    SUB  A, 3           
    JNZ  A, restart
    LD   A, IO_DATA
    ST   A, IO_DATA
