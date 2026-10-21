*Propagation testing for carry select adder
.include ../cell_lib.sp

.global vdd
.global vss

Vdd vdd 0 dc 3.3v 
Vss vss 0 dc 0


*0xFFFF + 0x0001
Xdut
+ vdd vdd vdd vdd vdd vdd vdd vdd vdd vdd vdd vdd vdd vdd vdd vdd
+ b0 vss vss vss vss vss vss vss vss vss vss vss vss vss vss vss
+ vss
+ s0 s1 s2 s3 s4 s5 s6 s7 s8 s9 sa sb sc sd se sf
+ cout carry_select_16

Vb0 b0 0 pulse(0 3.3 1n 50p 50p 5n 10n)

Cs0  s0  0 10f
Cs1  s1  0 10f
Cs2  s2  0 10f
Cs3  s3  0 10f
Cs4  s4  0 10f
Cs5  s5  0 10f
Cs6  s6  0 10f
Cs7  s7  0 10f
Cs8  s8  0 10f
Cs9  s9  0 10f
Csa  sa  0 10f
Csb  sb  0 10f
Csc  sc  0 10f
Csd  sd  0 10f
Cse  se  0 10f
Csf  sf  0 10f
Cout cout 0 10f
.control
tran 10p 12n
meas tran tpd_cout_r_10f trig v(b0) val=1.65 rise=1 targ v(cout) val=1.65 rise=1
meas tran tpd_sf_r_10f   trig v(b0) val=1.65 rise=1 targ v(sf)   val=1.65 fall=1
meas tran tpd_cout_f_10f trig v(b0) val=1.65 fall=1 targ v(cout) val=1.65 fall=1
meas tran tpd_sf_f_10f   trig v(b0) val=1.65 fall=1 targ v(sf)   val=1.65 rise=1
plot v(b0) v(xdut.c2)+4 v(xdut.c5)+8 v(xdut.c9)+12 v(xdut.ce)+16 v(cout)+20 v(sf)+24 xlimit 0.9n 5.5n
set hcopydevtype=svg
hardcopy csa_rise.svg v(b0) v(xdut.c2)+4 v(xdut.c5)+8 v(xdut.c9)+12 v(xdut.ce)+16 v(cout)+20 v(sf)+24 xlimit 0.9n 5.5n

alter cs0  40f
alter cs1  40f
alter cs2  40f
alter cs3  40f
alter cs4  40f
alter cs5  40f
alter cs6  40f
alter cs7  40f
alter cs8  40f
alter cs9  40f
alter csa  40f
alter csb  40f
alter csc  40f
alter csd  40f
alter cse  40f
alter csf  40f
alter cout 40f

tran 10p 12n
meas tran tpd_cout_r_40f trig v(b0) val=1.65 rise=1 targ v(cout) val=1.65 rise=1
meas tran tpd_sf_r_40f   trig v(b0) val=1.65 rise=1 targ v(sf)   val=1.65 fall=1
meas tran tpd_cout_f_40f trig v(b0) val=1.65 fall=1 targ v(cout) val=1.65 fall=1
meas tran tpd_sf_f_40f   trig v(b0) val=1.65 fall=1 targ v(sf)   val=1.65 rise=1

echo "10f delays"
print tran1.tpd_cout_r_10f tran1.tpd_sf_r_10f tran1.tpd_cout_f_10f tran1.tpd_sf_f_10f
echo "40f delays"
print tran2.tpd_cout_r_40f tran2.tpd_sf_r_40f tran2.tpd_cout_f_40f tran2.tpd_sf_f_40f

.endc
