.include ./cell_lib.sp

.global vdd
.global vss
Vdd vdd 0 dc 3.3v
Vss vss 0 dc 0

xdut a b cin out cout full_adder
Cload out vss 10f
Cload1 cout vss 10f 

*Input voltage sources for a and b
Va a 0 dc 3.3
Vb b 0 dc 0
Vcin cin 0 PULSE(0v 3.3v 0n 1n 1n 499n 1000n)

.control
let mc_runs = 100
let current_run = 0
set curplot = new
set scratch = $curplot

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
  alter @m.xdut.xxor1.m0[w] = agauss(xm0w, 3n, 1)
  alter @m.xdut.xxor1.m1[w] = agauss(xm1w, 3n, 1)
  alter @m.xdut.xxor1.m2[w] = agauss(xm2w, 3n, 1)
  alter @m.xdut.xxor1.m3[w] = agauss(xm3w, 3n, 1)
  alter @m.xdut.xxor1.m4[w] = agauss(xm4w, 3n, 1)
  alter @m.xdut.xxor1.m5[w] = agauss(xm5w, 3n, 1)
  alter @m.xdut.xxor1.m6[w] = agauss(xm6w, 3n, 1)
  alter @m.xdut.xxor1.m7[w] = agauss(xm7w, 3n, 1)
  alter @m.xdut.xxor1.m8[w] = agauss(xm8w, 3n, 1)
  alter @m.xdut.xxor1.m9[w] = agauss(xm9w, 3n, 1)

  alter @m.xdut.xxor1.m0[l] = agauss(xm0l, 3n, 1)
  alter @m.xdut.xxor1.m1[l] = agauss(xm1l, 3n, 1)
  alter @m.xdut.xxor1.m2[l] = agauss(xm2l, 3n, 1)
  alter @m.xdut.xxor1.m3[l] = agauss(xm3l, 3n, 1)
  alter @m.xdut.xxor1.m4[l] = agauss(xm4l, 3n, 1)
  alter @m.xdut.xxor1.m5[l] = agauss(xm5l, 3n, 1)
  alter @m.xdut.xxor1.m6[l] = agauss(xm6l, 3n, 1)
  alter @m.xdut.xxor1.m7[l] = agauss(xm7l, 3n, 1)
  alter @m.xdut.xxor1.m8[l] = agauss(xm8l, 3n, 1)
  alter @m.xdut.xxor1.m9[l] = agauss(xm9l, 3n, 1)

  alter @m.xdut.xxor2.m0[w] = agauss(xm0w, 3n, 1)
  alter @m.xdut.xxor2.m1[w] = agauss(xm1w, 3n, 1)
  alter @m.xdut.xxor2.m2[w] = agauss(xm2w, 3n, 1)
  alter @m.xdut.xxor2.m3[w] = agauss(xm3w, 3n, 1)
  alter @m.xdut.xxor2.m4[w] = agauss(xm4w, 3n, 1)
  alter @m.xdut.xxor2.m5[w] = agauss(xm5w, 3n, 1)
  alter @m.xdut.xxor2.m6[w] = agauss(xm6w, 3n, 1)
  alter @m.xdut.xxor2.m7[w] = agauss(xm7w, 3n, 1)
  alter @m.xdut.xxor2.m8[w] = agauss(xm8w, 3n, 1)
  alter @m.xdut.xxor2.m9[w] = agauss(xm9w, 3n, 1)

  alter @m.xdut.xxor2.m0[l] = agauss(xm0l, 3n, 1)
  alter @m.xdut.xxor2.m1[l] = agauss(xm1l, 3n, 1)
  alter @m.xdut.xxor2.m2[l] = agauss(xm2l, 3n, 1)
  alter @m.xdut.xxor2.m3[l] = agauss(xm3l, 3n, 1)
  alter @m.xdut.xxor2.m4[l] = agauss(xm4l, 3n, 1)
  alter @m.xdut.xxor2.m5[l] = agauss(xm5l, 3n, 1)
  alter @m.xdut.xxor2.m6[l] = agauss(xm6l, 3n, 1)
  alter @m.xdut.xxor2.m7[l] = agauss(xm7l, 3n, 1)
  alter @m.xdut.xxor2.m8[l] = agauss(xm8l, 3n, 1)
  alter @m.xdut.xxor2.m9[l] = agauss(xm9l, 3n, 1)


  alter @m.xdut.xmux1.mo0[w] = agauss(mmo0w, 3n, 1)
  alter @m.xdut.xmux1.mo1[w] = agauss(mmo1w, 3n, 1)
  alter @m.xdut.xmux1.m0[w] = agauss(mm0w, 3n, 1)
  alter @m.xdut.xmux1.m1[w] = agauss(mm1w, 3n, 1)
  alter @m.xdut.xmux1.m2[w] = agauss(mm2w, 3n, 1)
  alter @m.xdut.xmux1.m3[w] = agauss(mm3w, 3n, 1)
  alter @m.xdut.xmux1.m4[w] = agauss(mm4w, 3n, 1)
  alter @m.xdut.xmux1.m5[w] = agauss(mm5w, 3n, 1)
  alter @m.xdut.xmux1.m6[w] = agauss(mm6w, 3n, 1)
  alter @m.xdut.xmux1.m7[w] = agauss(mm7w, 3n, 1)
  alter @m.xdut.xmux1.m8[w] = agauss(mm8w, 3n, 1)
  alter @m.xdut.xmux1.m9[w] = agauss(mm9w, 3n, 1)

  alter @m.xdut.xmux1.mo0[l] = agauss(mmo0l, 3n, 1)
  alter @m.xdut.xmux1.mo1[l] = agauss(mmo1l, 3n, 1)
  alter @m.xdut.xmux1.m0[l] = agauss(mm0l, 3n, 1)
  alter @m.xdut.xmux1.m1[l] = agauss(mm1l, 3n, 1)
  alter @m.xdut.xmux1.m2[l] = agauss(mm2l, 3n, 1)
  alter @m.xdut.xmux1.m3[l] = agauss(mm3l, 3n, 1)
  alter @m.xdut.xmux1.m4[l] = agauss(mm4l, 3n, 1)
  alter @m.xdut.xmux1.m5[l] = agauss(mm5l, 3n, 1)
  alter @m.xdut.xmux1.m6[l] = agauss(mm6l, 3n, 1)
  alter @m.xdut.xmux1.m7[l] = agauss(mm7l, 3n, 1)
  alter @m.xdut.xmux1.m8[l] = agauss(mm8l, 3n, 1)
  alter @m.xdut.xmux1.m9[l] = agauss(mm9l, 3n, 1)

end



.endc 

