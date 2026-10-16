.include ../cell_lib.sp 

.global vdd
.global vss
Vdd vdd 0 dc 3.3v
Vss vss 0 dc 0

xdut a b cin out cout full_adder
Cload out vss 10f
Cload1 cout vss 10f 

*Input voltage sources for a and b
* A = 1
* B = 0
* Toggle cin between 0 and 1
* This means that sum will go low when CIN goes high, and SUM goes high when CIN goes low
Va a 0 dc 3.3
Vb b 0 dc 0
Vcin cin 0 PULSE(0v 3.3v 50n 1n 1n 49n 100n)

.control
let mc_runs = 3000
let current_run = 0
set curplot = new
set tran_meas = $curplot
let tplh_cout_delays = vector(mc_runs)
let tphl_cout_delays = vector(mc_runs)

let tphl_out_delays = vector(mc_runs)
let tplh_out_delays = vector(mc_runs)

define agauss(nom, avar, sig) (nom + avar/sig * sgauss(0))

let xm0w = @m.xdut.xxor1.m0[w]
let xm0l = @m.xdut.xxor1.m0[l]

let xm1w = @m.xdut.xxor1.m1[w]
let xm1l = @m.xdut.xxor1.m1[l]

let xm2w = @m.xdut.xxor1.m2[w]
let xm2l = @m.xdut.xxor1.m2[l]

let xm3w = @m.xdut.xxor1.m3[w]
let xm3l = @m.xdut.xxor1.m3[l]

let xm4w = @m.xdut.xxor1.m4[w]
let xm4l = @m.xdut.xxor1.m4[l]

let xm5w = @m.xdut.xxor1.m5[w]
let xm5l = @m.xdut.xxor1.m5[l]

let xm6w = @m.xdut.xxor1.m6[w]
let xm6l = @m.xdut.xxor1.m6[l]

let xm7w = @m.xdut.xxor1.m7[w]
let xm7l = @m.xdut.xxor1.m7[l]

let xm8w = @m.xdut.xxor1.m8[w]
let xm8l = @m.xdut.xxor1.m8[l]

let xm9w = @m.xdut.xxor1.m9[w]
let xm9l = @m.xdut.xxor1.m9[l]



*MUX initial values
let mmo0w = @m.xdut.xmux1.mo0[w]
let mmo0l = @m.xdut.xmux1.mo0[l]

let mmo1w = @m.xdut.xmux1.mo1[w]
let mmo1l = @m.xdut.xmux1.mo1[l]

let mm0w = @m.xdut.xmux1.m0[w]
let mm0l = @m.xdut.xmux1.m0[l]

let mm1w = @m.xdut.xmux1.m1[w]
let mm1l = @m.xdut.xmux1.m1[l]

let mm2w = @m.xdut.xmux1.m2[w]
let mm2l = @m.xdut.xmux1.m2[l]

let mm3w = @m.xdut.xmux1.m3[w]
let mm3l = @m.xdut.xmux1.m3[l]

let mm4w = @m.xdut.xmux1.m4[w]
let mm4l = @m.xdut.xmux1.m4[l]

let mm5w = @m.xdut.xmux1.m5[w]
let mm5l = @m.xdut.xmux1.m5[l]

let mm6w = @m.xdut.xmux1.m6[w]
let mm6l = @m.xdut.xmux1.m6[l]

let mm7w = @m.xdut.xmux1.m7[w]
let mm7l = @m.xdut.xmux1.m7[l]

let mm8w = @m.xdut.xmux1.m8[w]
let mm8l = @m.xdut.xmux1.m8[l]

let mm9w = @m.xdut.xmux1.m9[w]
let mm9l = @m.xdut.xmux1.m9[l]


dowhile current_run < mc_runs
  alter @m.xdut.xxor1.m0[w] = agauss(xm0w, 9n, 4)
  alter @m.xdut.xxor1.m1[w] = agauss(xm1w, 9n, 4)
  alter @m.xdut.xxor1.m2[w] = agauss(xm2w, 9n, 4)
  alter @m.xdut.xxor1.m3[w] = agauss(xm3w, 9n, 4)
  alter @m.xdut.xxor1.m4[w] = agauss(xm4w, 9n, 4)
  alter @m.xdut.xxor1.m5[w] = agauss(xm5w, 9n, 4)
  alter @m.xdut.xxor1.m6[w] = agauss(xm6w, 9n, 4)
  alter @m.xdut.xxor1.m7[w] = agauss(xm7w, 9n, 4)
  alter @m.xdut.xxor1.m8[w] = agauss(xm8w, 9n, 4)
  alter @m.xdut.xxor1.m9[w] = agauss(xm9w, 9n, 4)

  alter @m.xdut.xxor1.m0[l] = agauss(xm0l, 9n, 4)
  alter @m.xdut.xxor1.m1[l] = agauss(xm1l, 9n, 4)
  alter @m.xdut.xxor1.m2[l] = agauss(xm2l, 9n, 4)
  alter @m.xdut.xxor1.m3[l] = agauss(xm3l, 9n, 4)
  alter @m.xdut.xxor1.m4[l] = agauss(xm4l, 9n, 4)
  alter @m.xdut.xxor1.m5[l] = agauss(xm5l, 9n, 4)
  alter @m.xdut.xxor1.m6[l] = agauss(xm6l, 9n, 4)
  alter @m.xdut.xxor1.m7[l] = agauss(xm7l, 9n, 4)
  alter @m.xdut.xxor1.m8[l] = agauss(xm8l, 9n, 4)
  alter @m.xdut.xxor1.m9[l] = agauss(xm9l, 9n, 4)

  alter @m.xdut.xxor2.m0[w] = agauss(xm0w, 9n, 4)
  alter @m.xdut.xxor2.m1[w] = agauss(xm1w, 9n, 4)
  alter @m.xdut.xxor2.m2[w] = agauss(xm2w, 9n, 4)
  alter @m.xdut.xxor2.m3[w] = agauss(xm3w, 9n, 4)
  alter @m.xdut.xxor2.m4[w] = agauss(xm4w, 9n, 4)
  alter @m.xdut.xxor2.m5[w] = agauss(xm5w, 9n, 4)
  alter @m.xdut.xxor2.m6[w] = agauss(xm6w, 9n, 4)
  alter @m.xdut.xxor2.m7[w] = agauss(xm7w, 9n, 4)
  alter @m.xdut.xxor2.m8[w] = agauss(xm8w, 9n, 4)
  alter @m.xdut.xxor2.m9[w] = agauss(xm9w, 9n, 4)

  alter @m.xdut.xxor2.m0[l] = agauss(xm0l, 9n, 4)
  alter @m.xdut.xxor2.m1[l] = agauss(xm1l, 9n, 4)
  alter @m.xdut.xxor2.m2[l] = agauss(xm2l, 9n, 4)
  alter @m.xdut.xxor2.m3[l] = agauss(xm3l, 9n, 4)
  alter @m.xdut.xxor2.m4[l] = agauss(xm4l, 9n, 4)
  alter @m.xdut.xxor2.m5[l] = agauss(xm5l, 9n, 4)
  alter @m.xdut.xxor2.m6[l] = agauss(xm6l, 9n, 4)
  alter @m.xdut.xxor2.m7[l] = agauss(xm7l, 9n, 4)
  alter @m.xdut.xxor2.m8[l] = agauss(xm8l, 9n, 4)
  alter @m.xdut.xxor2.m9[l] = agauss(xm9l, 9n, 4)


  alter @m.xdut.xmux1.mo0[w] = agauss(mmo0w, 9n, 4)
  alter @m.xdut.xmux1.mo1[w] = agauss(mmo1w, 9n, 4)
  alter @m.xdut.xmux1.m0[w] = agauss(mm0w, 9n, 4)
  alter @m.xdut.xmux1.m1[w] = agauss(mm1w, 9n, 4)
  alter @m.xdut.xmux1.m2[w] = agauss(mm2w, 9n, 4)
  alter @m.xdut.xmux1.m3[w] = agauss(mm3w, 9n, 4)
  alter @m.xdut.xmux1.m4[w] = agauss(mm4w, 9n, 4)
  alter @m.xdut.xmux1.m5[w] = agauss(mm5w, 9n, 4)
  alter @m.xdut.xmux1.m6[w] = agauss(mm6w, 9n, 4)
  alter @m.xdut.xmux1.m7[w] = agauss(mm7w, 9n, 4)
  alter @m.xdut.xmux1.m8[w] = agauss(mm8w, 9n, 4)
  alter @m.xdut.xmux1.m9[w] = agauss(mm9w, 9n, 4)

  alter @m.xdut.xmux1.mo0[l] = agauss(mmo0l, 9n, 4)
  alter @m.xdut.xmux1.mo1[l] = agauss(mmo1l, 9n, 4)
  alter @m.xdut.xmux1.m0[l] = agauss(mm0l, 9n, 4)
  alter @m.xdut.xmux1.m1[l] = agauss(mm1l, 9n, 4)
  alter @m.xdut.xmux1.m2[l] = agauss(mm2l, 9n, 4)
  alter @m.xdut.xmux1.m3[l] = agauss(mm3l, 9n, 4)
  alter @m.xdut.xmux1.m4[l] = agauss(mm4l, 9n, 4)
  alter @m.xdut.xmux1.m5[l] = agauss(mm5l, 9n, 4)
  alter @m.xdut.xmux1.m6[l] = agauss(mm6l, 9n, 4)
  alter @m.xdut.xmux1.m7[l] = agauss(mm7l, 9n, 4)
  alter @m.xdut.xmux1.m8[l] = agauss(mm8l, 9n, 4)
  alter @m.xdut.xmux1.m9[l] = agauss(mm9l, 9n, 4)


  tran 10p 150n 40n
  meas tran tplh_cout TRIG v(cin) val=1.65 rise=1 targ v(cout) val=1.65 rise=1
  meas tran tphl_cout TRIG v(cin) val=1.65 fall=1 targ v(cout) val=1.65 fall=1
  meas tran tphl_out  TRIG v(cin) val=1.65 rise=1 targ v(out)  val=1.65 fall=1
  meas tran tplh_out  TRIG v(cin) val=1.65 fall=1 targ v(out)  val=1.65 rise=1

  set simplot = $curplot          
  setplot $tran_meas             

  let tplh_cout_delays[current_run] = {$simplot}.tplh_cout
  let tphl_cout_delays[current_run] = {$simplot}.tphl_cout
  let tphl_out_delays[current_run]  = {$simplot}.tphl_out
  let tplh_out_delays[current_run]  = {$simplot}.tplh_out

  destroy $simplot              
  let current_run = current_run + 1
end

print tplh_cout_delays tphl_cout_delays tplh_out_delays tphl_out_delays

set wr_singlescale    * write the scale column once, not before every vector
set wr_vecnames       * add a header row with the vector names
wrdata full_adder_mc.txt tplh_cout_delays tphl_cout_delays tplh_out_delays tphl_out_delays

quit
.endc
