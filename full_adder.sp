.include ./cell_lib.sp

.subckt full_adder a b cin S cout vdd vss
.global vdd vss

xor2x1 



.model tp pmos level=54 version=4.8.2 toxe=7.90n
.model tn nmos level=54 version=4.8.2 toxe=8.00n

.ends

