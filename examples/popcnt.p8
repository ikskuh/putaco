
.alloc return ; global return address

; uint8_t popcount(uint8_t x);
; pass value in A;
; returns bitcount in A;
popcnt_branchless:
.alloc iter, 1
.alloc cnt, 1
    ST A, iter
    AND 1
    ST A, cnt   ; store the first iteration

    LD  A, iter
    SHX A, -1
    AND 1
    ADD A, *cnt
    ST  A, cnt

    LD  A, iter
    SHX A, -2
    AND 1
    ADD A, *cnt
    ST  A, cnt

    LD  A, iter
    SHX A, -3
    AND 1
    ADD A, *cnt
    ST  A, cnt

    LD  A, iter
    SHX A, -4
    AND 1
    ADD A, *cnt
    ST  A, cnt

    LD  A, iter
    SHX A, -5
    AND 1
    ADD A, *cnt
    ST  A, cnt

    LD  A, iter
    SHX A, -6
    AND 1
    ADD A, *cnt
    ST  A, cnt

    LD  A, iter
    SHX A, -7
    AND 1
    ADD A, *cnt

    JMP *return



; uint8_t popcount(uint8_t x);
; pass value in A;
; returns bitcount in B;
; clobbers B
popcnt_branching:
.alloc value, 1
    ST  A, value
    SET B, 0

    AND A, 1
    JZ $0
    ADD B, 1
$0:

    LD  A, value
    AND A, 2
    JZ  A, $0
    ADD B, 1
$0:

    LD  A, value
    AND A, 4
    JZ  A, $0
    ADD B, 1
$0:

    LD  A, value
    AND A, 8
    JZ  A, $0
    ADD B, 1
$0:

    LD  A, value
    AND A, 16
    JZ  A, $0
    ADD B, 1
$0:

    LD  A, value
    AND A, 32
    JZ  A, $0
    ADD B, 1
$0:

    LD  A, value
    AND A, 64
    JZ  A, $0
    ADD B, 1
$0:

    LD  A, value
    AND A, 128
    JZ  A, $0
    ADD B, 1
$0:

    JMP *return



; uint8_t popcnt(uint8_t x)
; input:  A = x
; output: A = popcount(x)

popcnt_swar:
.alloc x,   1
.alloc tmp, 1
.alloc lo,  1

    ; x = x - ((x >> 1) & 0x55)
    ST  A, x
    SHX A, -1
    AND A, 0x55
    ST  A, tmp
    LD  A, x
    SUB A, *tmp

    ; x = (x & 0x33) + ((x >> 2) & 0x33)
    ST  A, tmp
    AND A, 0x33
    ST  A, lo
    LD  A, tmp
    SHX A, -2
    AND A, 0x33
    ADD A, *lo

    ; x = (x + (x >> 4)) & 0x0F
    ST  A, tmp
    SHX A, -4
    ADD A, *tmp
    AND A, 0x0F

    JMP *return