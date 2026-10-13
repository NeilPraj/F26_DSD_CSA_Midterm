* Full adder exhaustive test - all 8 input combinations
.include ./cell_lib.sp

.global vdd vss
Vdd vdd vss dc 3.3v
Vss vss 0 0

Xdut a b cin out cout full_adder
Cload  out  vss 10f
Cload1 cout vss 10f

Va   a   0 PULSE(0v 3.3v 100n 1n 1n 99n  200n)
Vb   b   0 PULSE(0v 3.3v 200n 1n 1n 199n 400n)
Vcin cin 0 PULSE(0v 3.3v 400n 1n 1n 399n 800n)

.control
tran 0.1ns 1600ns          ; two full passes through all 8 combos
plot cin+20 b+16 a+12 cout+4 out title 'Full Adder: inputs (top) / outputs (bottom)'
plot a b cin title 'Inputs'
plot out cout title 'Outputs'
.endc

.end
