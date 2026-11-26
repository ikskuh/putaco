# Generate the ALU table and run the bare Verilog testbench with Icarus Verilog.
testbench: gen-netlist
    zig-0.17.1 build
    mkdir -p zig-out/gateware
    iverilog \
        -g2012 \
        -gspecify \
        -Wall \
        -Wno-portbind  \
        -s testbench \
        -o zig-out/gateware/testbench \
        gateware/testbench.v \
        gateware/PutacoCore.v \
        gateware/PutacoFilterUnit.v \
        gateware/memory/*.v \
        gateware/74xx/*.v \
        gateware/streamers/*.v
    vvp zig-out/gateware/testbench

# Standalone part models: no ALU generation or Zig toolchain required.
test-74xx:
    mkdir -p zig-out/gateware/74xx
    for source in gateware/74xx/*.v; do iverilog -g2012 -gspecify -Wall -tnull "$source" || exit $?; done
    iverilog -g2012 -gspecify -Wall -s test_74xx \
        -o zig-out/gateware/74xx/test_74xx \
        gateware/test_74xx.v gateware/74xx/*.v
    vvp zig-out/gateware/74xx/test_74xx

# Datasheet memory models and preload fixtures; independent of Zig.
test-memory:
    mkdir -p zig-out/gateware/memory
    for source in gateware/memory/*.v; do iverilog -g2012 -Wall -tnull "$source" || exit $?; done
    iverilog -g2012 -Wall -s test_memory \
        -o zig-out/gateware/memory/test_memory \
        gateware/test_memory.v gateware/memory/*.v
    vvp zig-out/gateware/memory/test_memory


test-echo:
    zig build 
    ./zig-out/bin/assembler < examples/echo.p8 > examples/echo.bin
    @echo "----"
    echo 'Hello, World!' | ./zig-out/bin/simulator examples/echo.bin


test-hello:
    zig build 
    ./zig-out/bin/assembler < examples/hello.p8 > examples/hello.bin
    @echo "----"
    ./zig-out/bin/simulator examples/hello.bin


gen-netlist:
    zig build -freference-trace=8 --error-style minimal --summary none
    ./zig-out/bin/hwcomp < hardware/netlist.hw gateware/netlist-patches.json \
        | tee  gateware/PutacoCore.v
