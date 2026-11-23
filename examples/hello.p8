; PUTACO-8 TEST PROGRAM

; Declares a constant value
.constant IO_DATA, 0
.constant IO_STATUS, 1
.constant TXE, 2

.constant LF, 10
.constant CR, 13

; Allocates a new RAM address, starting at 16
.alloc ret_addr, 1

    SET  A, write_e
    ST   A, ret_addr
    SET  A, 'H'
    JMP  write_out

write_e:
    SET  A, write_l0
    ST   A, ret_addr
    SET  A, 'e'
    JMP  write_out

write_l0:
    SET  A, write_l1
    ST   A, ret_addr
    SET  A, 'l'
    JMP  write_out

write_l1:
    SET  A, write_o
    ST   A, ret_addr
    SET  A, 'l'
    JMP  write_out

write_o:
    SET  A, write_bang
    ST   A, ret_addr
    SET  A, 'o'
    JMP  write_out

write_bang:
    SET  A, write_eol
    ST   A, ret_addr
    SET  A, '!'
    JMP  write_out

write_eol:
    SET  A, stop
    ST   A, ret_addr
    SET  A, LF
    JMP  write_out


stop:
    HALT 0


.alloc write_data, 1  ; output byte
write_out:
    ST   A, write_data
.loop:
    ; wait until FIFO is empty (TXE set)
    LD   A, IO_STATUS
    AND  A, TXE
    JZ   A, .loop

    ; then write the register
    LD   A, write_data
    ST   A, IO_DATA

    JMP  *ret_addr ; indirect jump to the return address
