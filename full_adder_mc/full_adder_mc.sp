.include ../cell_lib.sp

.global vdd
.global vss
Vdd vdd 0 dc 3.3v
Vss vss 0 dc 0

xdut a b cin out cout full_adder
Cload out vss 10f
Cload1 cout vss 10f

* Input voltage sources
* A = 1, B = 0, cin toggles 0 <-> 1
* So SUM goes low when CIN goes high, and high when CIN goes low
Va a 0 dc 3.3
Vb b 0 dc 0
Vcin cin 0 PULSE(0v 3.3v 50n 1n 1n 49n 100n)

.control
let mc_runs = 1000
let current_run = 0
set curplot = new
set tran_meas = $curplot
let tplh_cout_delays = vector(mc_runs)
let tphl_cout_delays = vector(mc_runs)
let tplh_out_delays = vector(mc_runs)
let tphl_out_delays = vector(mc_runs)

* agauss: absolute variation, rgauss: relative variation
define agauss(nom, avar, sig) (nom + avar/sig * sgauss(0))
define rgauss(nom, rvar, sig) (nom + nom*rvar/sig * sgauss(0))

* Nominal sizes for xdut.xxor1
let nom_xxor1_m0_w = @m.xdut.xxor1.m0[w]
let nom_xxor1_m0_l = @m.xdut.xxor1.m0[l]
let nom_xxor1_m1_w = @m.xdut.xxor1.m1[w]
let nom_xxor1_m1_l = @m.xdut.xxor1.m1[l]
let nom_xxor1_m2_w = @m.xdut.xxor1.m2[w]
let nom_xxor1_m2_l = @m.xdut.xxor1.m2[l]
let nom_xxor1_m3_w = @m.xdut.xxor1.m3[w]
let nom_xxor1_m3_l = @m.xdut.xxor1.m3[l]
let nom_xxor1_m4_w = @m.xdut.xxor1.m4[w]
let nom_xxor1_m4_l = @m.xdut.xxor1.m4[l]
let nom_xxor1_m5_w = @m.xdut.xxor1.m5[w]
let nom_xxor1_m5_l = @m.xdut.xxor1.m5[l]
let nom_xxor1_m6_w = @m.xdut.xxor1.m6[w]
let nom_xxor1_m6_l = @m.xdut.xxor1.m6[l]
let nom_xxor1_m7_w = @m.xdut.xxor1.m7[w]
let nom_xxor1_m7_l = @m.xdut.xxor1.m7[l]
let nom_xxor1_m8_w = @m.xdut.xxor1.m8[w]
let nom_xxor1_m8_l = @m.xdut.xxor1.m8[l]
let nom_xxor1_m9_w = @m.xdut.xxor1.m9[w]
let nom_xxor1_m9_l = @m.xdut.xxor1.m9[l]

* Nominal sizes for xdut.xxor2
let nom_xxor2_m0_w = @m.xdut.xxor2.m0[w]
let nom_xxor2_m0_l = @m.xdut.xxor2.m0[l]
let nom_xxor2_m1_w = @m.xdut.xxor2.m1[w]
let nom_xxor2_m1_l = @m.xdut.xxor2.m1[l]
let nom_xxor2_m2_w = @m.xdut.xxor2.m2[w]
let nom_xxor2_m2_l = @m.xdut.xxor2.m2[l]
let nom_xxor2_m3_w = @m.xdut.xxor2.m3[w]
let nom_xxor2_m3_l = @m.xdut.xxor2.m3[l]
let nom_xxor2_m4_w = @m.xdut.xxor2.m4[w]
let nom_xxor2_m4_l = @m.xdut.xxor2.m4[l]
let nom_xxor2_m5_w = @m.xdut.xxor2.m5[w]
let nom_xxor2_m5_l = @m.xdut.xxor2.m5[l]
let nom_xxor2_m6_w = @m.xdut.xxor2.m6[w]
let nom_xxor2_m6_l = @m.xdut.xxor2.m6[l]
let nom_xxor2_m7_w = @m.xdut.xxor2.m7[w]
let nom_xxor2_m7_l = @m.xdut.xxor2.m7[l]
let nom_xxor2_m8_w = @m.xdut.xxor2.m8[w]
let nom_xxor2_m8_l = @m.xdut.xxor2.m8[l]
let nom_xxor2_m9_w = @m.xdut.xxor2.m9[w]
let nom_xxor2_m9_l = @m.xdut.xxor2.m9[l]

* Nominal sizes for xdut.xmux1
let nom_xmux1_mo0_w = @m.xdut.xmux1.mo0[w]
let nom_xmux1_mo0_l = @m.xdut.xmux1.mo0[l]
let nom_xmux1_mo1_w = @m.xdut.xmux1.mo1[w]
let nom_xmux1_mo1_l = @m.xdut.xmux1.mo1[l]
let nom_xmux1_m0_w = @m.xdut.xmux1.m0[w]
let nom_xmux1_m0_l = @m.xdut.xmux1.m0[l]
let nom_xmux1_m1_w = @m.xdut.xmux1.m1[w]
let nom_xmux1_m1_l = @m.xdut.xmux1.m1[l]
let nom_xmux1_m2_w = @m.xdut.xmux1.m2[w]
let nom_xmux1_m2_l = @m.xdut.xmux1.m2[l]
let nom_xmux1_m3_w = @m.xdut.xmux1.m3[w]
let nom_xmux1_m3_l = @m.xdut.xmux1.m3[l]
let nom_xmux1_m4_w = @m.xdut.xmux1.m4[w]
let nom_xmux1_m4_l = @m.xdut.xmux1.m4[l]
let nom_xmux1_m5_w = @m.xdut.xmux1.m5[w]
let nom_xmux1_m5_l = @m.xdut.xmux1.m5[l]
let nom_xmux1_m6_w = @m.xdut.xmux1.m6[w]
let nom_xmux1_m6_l = @m.xdut.xmux1.m6[l]
let nom_xmux1_m7_w = @m.xdut.xmux1.m7[w]
let nom_xmux1_m7_l = @m.xdut.xmux1.m7[l]
let nom_xmux1_m8_w = @m.xdut.xmux1.m8[w]
let nom_xmux1_m8_l = @m.xdut.xmux1.m8[l]
let nom_xmux1_m9_w = @m.xdut.xmux1.m9[w]
let nom_xmux1_m9_l = @m.xdut.xmux1.m9[l]

dowhile current_run < mc_runs
  alter @m.xdut.xxor1.m0[w] = agauss(nom_xxor1_m0_w, 9n, 4)
  alter @m.xdut.xxor1.m1[w] = agauss(nom_xxor1_m1_w, 9n, 4)
  alter @m.xdut.xxor1.m2[w] = agauss(nom_xxor1_m2_w, 9n, 4)
  alter @m.xdut.xxor1.m3[w] = agauss(nom_xxor1_m3_w, 9n, 4)
  alter @m.xdut.xxor1.m4[w] = agauss(nom_xxor1_m4_w, 9n, 4)
  alter @m.xdut.xxor1.m5[w] = agauss(nom_xxor1_m5_w, 9n, 4)
  alter @m.xdut.xxor1.m6[w] = agauss(nom_xxor1_m6_w, 9n, 4)
  alter @m.xdut.xxor1.m7[w] = agauss(nom_xxor1_m7_w, 9n, 4)
  alter @m.xdut.xxor1.m8[w] = agauss(nom_xxor1_m8_w, 9n, 4)
  alter @m.xdut.xxor1.m9[w] = agauss(nom_xxor1_m9_w, 9n, 4)

  alter @m.xdut.xxor1.m0[l] = agauss(nom_xxor1_m0_l, 9n, 4)
  alter @m.xdut.xxor1.m1[l] = agauss(nom_xxor1_m1_l, 9n, 4)
  alter @m.xdut.xxor1.m2[l] = agauss(nom_xxor1_m2_l, 9n, 4)
  alter @m.xdut.xxor1.m3[l] = agauss(nom_xxor1_m3_l, 9n, 4)
  alter @m.xdut.xxor1.m4[l] = agauss(nom_xxor1_m4_l, 9n, 4)
  alter @m.xdut.xxor1.m5[l] = agauss(nom_xxor1_m5_l, 9n, 4)
  alter @m.xdut.xxor1.m6[l] = agauss(nom_xxor1_m6_l, 9n, 4)
  alter @m.xdut.xxor1.m7[l] = agauss(nom_xxor1_m7_l, 9n, 4)
  alter @m.xdut.xxor1.m8[l] = agauss(nom_xxor1_m8_l, 9n, 4)
  alter @m.xdut.xxor1.m9[l] = agauss(nom_xxor1_m9_l, 9n, 4)

  alter @m.xdut.xxor2.m0[w] = agauss(nom_xxor2_m0_w, 9n, 4)
  alter @m.xdut.xxor2.m1[w] = agauss(nom_xxor2_m1_w, 9n, 4)
  alter @m.xdut.xxor2.m2[w] = agauss(nom_xxor2_m2_w, 9n, 4)
  alter @m.xdut.xxor2.m3[w] = agauss(nom_xxor2_m3_w, 9n, 4)
  alter @m.xdut.xxor2.m4[w] = agauss(nom_xxor2_m4_w, 9n, 4)
  alter @m.xdut.xxor2.m5[w] = agauss(nom_xxor2_m5_w, 9n, 4)
  alter @m.xdut.xxor2.m6[w] = agauss(nom_xxor2_m6_w, 9n, 4)
  alter @m.xdut.xxor2.m7[w] = agauss(nom_xxor2_m7_w, 9n, 4)
  alter @m.xdut.xxor2.m8[w] = agauss(nom_xxor2_m8_w, 9n, 4)
  alter @m.xdut.xxor2.m9[w] = agauss(nom_xxor2_m9_w, 9n, 4)

  alter @m.xdut.xxor2.m0[l] = agauss(nom_xxor2_m0_l, 9n, 4)
  alter @m.xdut.xxor2.m1[l] = agauss(nom_xxor2_m1_l, 9n, 4)
  alter @m.xdut.xxor2.m2[l] = agauss(nom_xxor2_m2_l, 9n, 4)
  alter @m.xdut.xxor2.m3[l] = agauss(nom_xxor2_m3_l, 9n, 4)
  alter @m.xdut.xxor2.m4[l] = agauss(nom_xxor2_m4_l, 9n, 4)
  alter @m.xdut.xxor2.m5[l] = agauss(nom_xxor2_m5_l, 9n, 4)
  alter @m.xdut.xxor2.m6[l] = agauss(nom_xxor2_m6_l, 9n, 4)
  alter @m.xdut.xxor2.m7[l] = agauss(nom_xxor2_m7_l, 9n, 4)
  alter @m.xdut.xxor2.m8[l] = agauss(nom_xxor2_m8_l, 9n, 4)
  alter @m.xdut.xxor2.m9[l] = agauss(nom_xxor2_m9_l, 9n, 4)

  alter @m.xdut.xmux1.mo0[w] = agauss(nom_xmux1_mo0_w, 9n, 4)
  alter @m.xdut.xmux1.mo1[w] = agauss(nom_xmux1_mo1_w, 9n, 4)
  alter @m.xdut.xmux1.m0[w] = agauss(nom_xmux1_m0_w, 9n, 4)
  alter @m.xdut.xmux1.m1[w] = agauss(nom_xmux1_m1_w, 9n, 4)
  alter @m.xdut.xmux1.m2[w] = agauss(nom_xmux1_m2_w, 9n, 4)
  alter @m.xdut.xmux1.m3[w] = agauss(nom_xmux1_m3_w, 9n, 4)
  alter @m.xdut.xmux1.m4[w] = agauss(nom_xmux1_m4_w, 9n, 4)
  alter @m.xdut.xmux1.m5[w] = agauss(nom_xmux1_m5_w, 9n, 4)
  alter @m.xdut.xmux1.m6[w] = agauss(nom_xmux1_m6_w, 9n, 4)
  alter @m.xdut.xmux1.m7[w] = agauss(nom_xmux1_m7_w, 9n, 4)
  alter @m.xdut.xmux1.m8[w] = agauss(nom_xmux1_m8_w, 9n, 4)
  alter @m.xdut.xmux1.m9[w] = agauss(nom_xmux1_m9_w, 9n, 4)

  alter @m.xdut.xmux1.mo0[l] = agauss(nom_xmux1_mo0_l, 9n, 4)
  alter @m.xdut.xmux1.mo1[l] = agauss(nom_xmux1_mo1_l, 9n, 4)
  alter @m.xdut.xmux1.m0[l] = agauss(nom_xmux1_m0_l, 9n, 4)
  alter @m.xdut.xmux1.m1[l] = agauss(nom_xmux1_m1_l, 9n, 4)
  alter @m.xdut.xmux1.m2[l] = agauss(nom_xmux1_m2_l, 9n, 4)
  alter @m.xdut.xmux1.m3[l] = agauss(nom_xmux1_m3_l, 9n, 4)
  alter @m.xdut.xmux1.m4[l] = agauss(nom_xmux1_m4_l, 9n, 4)
  alter @m.xdut.xmux1.m5[l] = agauss(nom_xmux1_m5_l, 9n, 4)
  alter @m.xdut.xmux1.m6[l] = agauss(nom_xmux1_m6_l, 9n, 4)
  alter @m.xdut.xmux1.m7[l] = agauss(nom_xmux1_m7_l, 9n, 4)
  alter @m.xdut.xmux1.m8[l] = agauss(nom_xmux1_m8_l, 9n, 4)
  alter @m.xdut.xmux1.m9[l] = agauss(nom_xmux1_m9_l, 9n, 4)

  tran 10p 150n 40n
  meas tran tplh_cout TRIG v(cin) val=1.65 rise=1 targ v(cout) val=1.65 rise=1
  meas tran tphl_cout TRIG v(cin) val=1.65 fall=1 targ v(cout) val=1.65 fall=1
  meas tran tplh_out TRIG v(cin) val=1.65 fall=1 targ v(out) val=1.65 rise=1
  meas tran tphl_out TRIG v(cin) val=1.65 rise=1 targ v(out) val=1.65 fall=1

  set simplot = $curplot
  setplot $tran_meas

  let tplh_cout_delays[current_run] = {$simplot}.tplh_cout
  let tphl_cout_delays[current_run] = {$simplot}.tphl_cout
  let tplh_out_delays[current_run] = {$simplot}.tplh_out
  let tphl_out_delays[current_run] = {$simplot}.tphl_out

  destroy $simplot
  let current_run = current_run + 1
end

print tplh_cout_delays tphl_cout_delays tplh_out_delays tphl_out_delays

* write the scale column once, and add a header row of vector names
set wr_singlescale
set wr_vecnames
wrdata full_adder_mc.txt tplh_cout_delays tphl_cout_delays tplh_out_delays tphl_out_delays

quit
.endc
