; PUTACO-8 TEST PROGRAM

; Declares a constant value
.constant IO_DATA, 0
.constant IO_STATUS, 1
.constant TXE, 2

.constant LF, 10
.constant CR, 13

; Allocates a new RAM address, starting at 16
.alloc ret_addr, 1

    SET  write_e
    ST   ret_addr
    SET  'H'
    JMP  write_out

write_e:
    SET  write_l0
    ST   ret_addr
    SET  'e'
    JMP  write_out

write_l0:
    SET  write_l1
    ST   ret_addr
    SET  'l'
    JMP  write_out

write_l1:
    SET  write_o
    ST   ret_addr
    SET  'l'
    JMP  write_out

write_o:
    SET  write_bang
    ST   ret_addr
    SET  'o'
    JMP  write_out

write_bang:
    SET  write_eol
    ST   ret_addr
    SET  '!'
    JMP  write_out

write_eol:
    SET  stop
    ST   ret_addr
    SET  LF
    JMP  write_out


stop:
    HALT 0


.alloc write_data, 1  ; output byte
write_out:
    ST   write_data
.loop:
    ; wait until FIFO is empty (TXE unset)
    LD   IO_STATUS
    AND  TXE
    JZ   .loop

    ; then write the register
    LD   write_data
    ST   IO_DATA

    JMP  *ret_addr ; indirect jump to the return address
