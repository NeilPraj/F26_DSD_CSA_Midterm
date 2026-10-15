*Full Adder Propagation Delay Fixture
.include ../cell_lib.sp 

.global vdd
.global vss

Vdd vdd 0 dc 3.3v
Vss vss 0 dc 0

xdut a b cin out cout full_adder
Cload out vss 10f
Cload1 cout vss 10f

Va a 0 dc 3.3
Vb b 0 dc 0
Vcin cin 0 PULSE(0v 3.3v 50n 1n 1n 49n 100n)

.control
tran 10p 150n 40n
meas tran tplh_cout TRIG v(cin) val=1.65 rise=1 targ v(cout) val=1.65 rise=1
meas tran tphl_cout TRIG v(cin) val=1.65 fall=1 targ v(cout) val=1.65 fall=1
meas tran tphl_out  TRIG v(cin) val=1.65 rise=1 targ v(out)  val=1.65 fall=1
meas tran tplh_out  TRIG v(cin) val=1.65 fall=1 targ v(out)  val=1.65 rise=1
.endc

.end
