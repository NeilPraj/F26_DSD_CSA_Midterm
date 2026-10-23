* MUX Test - all 8 input combinations
.include ./cell_lib.sp
.global vdd vss
Vdd vdd vss dc 3.3v
Vss vss 0 0

Xdut a b s out mux2x1
Cload  out  vss 10f

Va   a   0 PULSE(0v 3.3v 100n 1n 1n 99n  200n)
Vb   b   0 PULSE(0v 3.3v 200n 1n 1n 199n 400n)
Vs   s   0 PULSE(0v 3.3v 400n 1n 1n 399n 800n)

.control
tran 0.1ns 1600ns          ; two full passes through all 8 combos
plot a+16 b+12 s+8 out title 'MUX: inputs (top) / outputs (bottom)'
set hcopypscolor=1
set color0=white
set color1=black
hardcopy mux_sim_select.ps a+16 b+12 s+8 out title 'MUX: inputs (top) / outputs (bottom)'
plot a b s title 'Inputs'
plot out title 'Outputs'
.endc

.end
