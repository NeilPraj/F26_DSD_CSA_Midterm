.include ../cell_lib.sp 

.global vdd
.global vss
Vdd vdd 0 dc 3.3v
Vss vss 0 dc 0

*Select Switch
Xselect a_select b_select s_select out_select mux2x1
Cload1 out_select vss 10f

*Input Switch
Xinput a_input b_input s_input out_input mux2x1
Cload3 out_input vss 10f

*Input voltage sources for switching select
Va_select a_select 0 dc 3.3
Vb_select b_select 0 dc 0
Vs_select s_select 0 PULSE(0v 3.3v 50n 1n 1n 49n 100n)

*Input voltage sources for switching input
Va_input a_input 0 PULSE(0v 3.3v 50n 1n 1n 49n 100n)
Vb_input b_input 0 dc 0
Vs_input s_input 0 dc 0

.control
let mc_runs = 1000
let current_run = 0
set curplot = new
set tran_meas = $curplot
let select_switch_hl = vector(mc_runs)
let select_switch_lh = vector(mc_runs)

let input_switch_hl = vector(mc_runs)
let input_switch_lh = vector(mc_runs)

define agauss(nom, avar, sig) (nom + avar/sig * sgauss(0))

let xmo0w = @m.xselect.mo0[w] 
let xmo1w = @m.xselect.mo1[w] 
let xm0w = @m.xselect.m0[w]
let xm1w = @m.xselect.m1[w]
let xm2w = @m.xselect.m2[w]
let xm3w = @m.xselect.m3[w]
let xm4w = @m.xselect.m4[w]
let xm5w = @m.xselect.m5[w]
let xm6w = @m.xselect.m6[w]
let xm7w = @m.xselect.m7[w]
let xm8w = @m.xselect.m8[w]
let xm9w = @m.xselect.m9[w] 

let xmo0l = @m.xselect.mo0[l] 
let xmo1l = @m.xselect.mo1[l] 
let xm0l = @m.xselect.m0[l]
let xm1l = @m.xselect.m1[l]
let xm2l = @m.xselect.m2[l]
let xm3l = @m.xselect.m3[l]
let xm4l = @m.xselect.m4[l]
let xm5l = @m.xselect.m5[l]
let xm6l = @m.xselect.m6[l]
let xm7l = @m.xselect.m7[l]
let xm8l = @m.xselect.m8[l]
let xm9l = @m.xselect.m9[l] 

dowhile current_run < mc_runs
  alter @m.xselect.mo0[w] = agauss(xmo0w, 9n, 4)
  alter @m.xselect.mo1[w] = agauss(xmo1w, 9n, 4)
  alter @m.xselect.m0[w] = agauss(xm0w, 9n, 4)
  alter @m.xselect.m1[w] = agauss(xm1w, 9n, 4)
  alter @m.xselect.m2[w] = agauss(xm2w, 9n, 4)
  alter @m.xselect.m3[w] = agauss(xm3w, 9n, 4)
  alter @m.xselect.m4[w] = agauss(xm4w, 9n, 4)
  alter @m.xselect.m5[w] = agauss(xm5w, 9n, 4)
  alter @m.xselect.m6[w] = agauss(xm6w, 9n, 4)
  alter @m.xselect.m7[w] = agauss(xm7w, 9n, 4)
  alter @m.xselect.m8[w] = agauss(xm8w, 9n, 4)
  alter @m.xselect.m9[w] = agauss(xm9w, 9n, 4)

  alter @m.xselect.mo0[l] = agauss(xmo0l, 9n, 4)
  alter @m.xselect.mo1[l] = agauss(xmo1l, 9n, 4)
  alter @m.xselect.m0[l] = agauss(xm0l, 9n, 4)
  alter @m.xselect.m1[l] = agauss(xm1l, 9n, 4)
  alter @m.xselect.m2[l] = agauss(xm2l, 9n, 4)
  alter @m.xselect.m3[l] = agauss(xm3l, 9n, 4)
  alter @m.xselect.m4[l] = agauss(xm4l, 9n, 4)
  alter @m.xselect.m5[l] = agauss(xm5l, 9n, 4)
  alter @m.xselect.m6[l] = agauss(xm6l, 9n, 4)
  alter @m.xselect.m7[l] = agauss(xm7l, 9n, 4)
  alter @m.xselect.m8[l] = agauss(xm8l, 9n, 4)
  alter @m.xselect.m9[l] = agauss(xm9l, 9n, 4)



  alter @m.xinput.mo0[w] = agauss(xmo0w, 9n, 4)
  alter @m.xinput.mo1[w] = agauss(xmo1w, 9n, 4)
  alter @m.xinput.m0[w] = agauss(xm0w, 9n, 4)
  alter @m.xinput.m1[w] = agauss(xm1w, 9n, 4)
  alter @m.xinput.m2[w] = agauss(xm2w, 9n, 4)
  alter @m.xinput.m3[w] = agauss(xm3w, 9n, 4)
  alter @m.xinput.m4[w] = agauss(xm4w, 9n, 4)
  alter @m.xinput.m5[w] = agauss(xm5w, 9n, 4)
  alter @m.xinput.m6[w] = agauss(xm6w, 9n, 4)
  alter @m.xinput.m7[w] = agauss(xm7w, 9n, 4)
  alter @m.xinput.m8[w] = agauss(xm8w, 9n, 4)
  alter @m.xinput.m9[w] = agauss(xm9w, 9n, 4)

  alter @m.xinput.mo0[l] = agauss(xmo0l, 9n, 4)
  alter @m.xinput.mo1[l] = agauss(xmo1l, 9n, 4)
  alter @m.xinput.m0[l] = agauss(xm0l, 9n, 4)
  alter @m.xinput.m1[l] = agauss(xm1l, 9n, 4)
  alter @m.xinput.m2[l] = agauss(xm2l, 9n, 4)
  alter @m.xinput.m3[l] = agauss(xm3l, 9n, 4)
  alter @m.xinput.m4[l] = agauss(xm4l, 9n, 4)
  alter @m.xinput.m5[l] = agauss(xm5l, 9n, 4)
  alter @m.xinput.m6[l] = agauss(xm6l, 9n, 4)
  alter @m.xinput.m7[l] = agauss(xm7l, 9n, 4)
  alter @m.xinput.m8[l] = agauss(xm8l, 9n, 4)
  alter @m.xinput.m9[l] = agauss(xm9l, 9n, 4)
  

  tran 10p 150n 40n
  meas tran select_delay_lh TRIG v(s_select) val=1.65 fall=1 targ v(out_select) val=1.65 rise=1
  meas tran select_delay_hl TRIG v(s_select) val=1.65 rise=1 targ v(out_select) val=1.65 fall=1
  meas tran input_delay_lh  TRIG v(a_input)  val=1.65 rise=1 targ v(out_input)  val=1.65 rise=1
  meas tran input_delay_hl  TRIG v(a_input)  val=1.65 fall=1 targ v(out_input)  val=1.65 fall=1

  set simplot = $curplot
  setplot $tran_meas

  let select_switch_lh[current_run] = {$simplot}.select_delay_lh
  let select_switch_hl[current_run] = {$simplot}.select_delay_hl
  let input_switch_lh[current_run] = {$simplot}.input_delay_lh
  let input_switch_hl[current_run] = {$simplot}.input_delay_hl

  destroy $simplot
  let current_run = current_run + 1
end

print select_switch_lh select_switch_hl input_switch_lh input_switch_hl

set wr_singlescale
set wr_vecnames
wrdata mux_mc_delays.txt select_switch_lh select_switch_hl input_switch_lh input_switch_hl
quit
.endc
