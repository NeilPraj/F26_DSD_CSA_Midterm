.include ../cell_lib.sp

.global vdd
.global vss
Vdd vdd 0 dc 3.3v
Vss vss 0 dc 0

* Select switch
Xselect a_select b_select s_select out_select mux2x1
Cload1 out_select vss 10f

* Input switch
Xinput a_input b_input s_input out_input mux2x1
Cload2 out_input vss 10f

* Select switch sources: A = 1, B = 0, S toggles 0 <-> 1
* So OUT goes low when S goes high, and high when S goes low
Va_select a_select 0 dc 3.3
Vb_select b_select 0 dc 0
Vs_select s_select 0 PULSE(0v 3.3v 50n 1n 1n 49n 100n)

* Input switch sources: S = 0 (selects A), B = 0, A toggles 0 <-> 1
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
let input_switch_lh = vector(mc_runs)
let input_switch_hl = vector(mc_runs)

* agauss: absolute variation, rgauss: relative variation
define agauss(nom, avar, sig) (nom + avar/sig * sgauss(0))
define rgauss(nom, rvar, sig) (nom + nom*rvar/sig * sgauss(0))

* Nominal sizes for xselect
let nom_xselect_mo0_w = @m.xselect.mo0[w]
let nom_xselect_mo0_l = @m.xselect.mo0[l]
let nom_xselect_mo1_w = @m.xselect.mo1[w]
let nom_xselect_mo1_l = @m.xselect.mo1[l]
let nom_xselect_m0_w = @m.xselect.m0[w]
let nom_xselect_m0_l = @m.xselect.m0[l]
let nom_xselect_m1_w = @m.xselect.m1[w]
let nom_xselect_m1_l = @m.xselect.m1[l]
let nom_xselect_m2_w = @m.xselect.m2[w]
let nom_xselect_m2_l = @m.xselect.m2[l]
let nom_xselect_m3_w = @m.xselect.m3[w]
let nom_xselect_m3_l = @m.xselect.m3[l]
let nom_xselect_m4_w = @m.xselect.m4[w]
let nom_xselect_m4_l = @m.xselect.m4[l]
let nom_xselect_m5_w = @m.xselect.m5[w]
let nom_xselect_m5_l = @m.xselect.m5[l]
let nom_xselect_m6_w = @m.xselect.m6[w]
let nom_xselect_m6_l = @m.xselect.m6[l]
let nom_xselect_m7_w = @m.xselect.m7[w]
let nom_xselect_m7_l = @m.xselect.m7[l]
let nom_xselect_m8_w = @m.xselect.m8[w]
let nom_xselect_m8_l = @m.xselect.m8[l]
let nom_xselect_m9_w = @m.xselect.m9[w]
let nom_xselect_m9_l = @m.xselect.m9[l]

* Nominal sizes for xinput
let nom_xinput_mo0_w = @m.xinput.mo0[w]
let nom_xinput_mo0_l = @m.xinput.mo0[l]
let nom_xinput_mo1_w = @m.xinput.mo1[w]
let nom_xinput_mo1_l = @m.xinput.mo1[l]
let nom_xinput_m0_w = @m.xinput.m0[w]
let nom_xinput_m0_l = @m.xinput.m0[l]
let nom_xinput_m1_w = @m.xinput.m1[w]
let nom_xinput_m1_l = @m.xinput.m1[l]
let nom_xinput_m2_w = @m.xinput.m2[w]
let nom_xinput_m2_l = @m.xinput.m2[l]
let nom_xinput_m3_w = @m.xinput.m3[w]
let nom_xinput_m3_l = @m.xinput.m3[l]
let nom_xinput_m4_w = @m.xinput.m4[w]
let nom_xinput_m4_l = @m.xinput.m4[l]
let nom_xinput_m5_w = @m.xinput.m5[w]
let nom_xinput_m5_l = @m.xinput.m5[l]
let nom_xinput_m6_w = @m.xinput.m6[w]
let nom_xinput_m6_l = @m.xinput.m6[l]
let nom_xinput_m7_w = @m.xinput.m7[w]
let nom_xinput_m7_l = @m.xinput.m7[l]
let nom_xinput_m8_w = @m.xinput.m8[w]
let nom_xinput_m8_l = @m.xinput.m8[l]
let nom_xinput_m9_w = @m.xinput.m9[w]
let nom_xinput_m9_l = @m.xinput.m9[l]

dowhile current_run < mc_runs
  alter @m.xselect.mo0[w] = agauss(nom_xselect_mo0_w, 18n, 3)
  alter @m.xselect.mo1[w] = agauss(nom_xselect_mo1_w, 18n, 3)
  alter @m.xselect.m0[w] = agauss(nom_xselect_m0_w, 18n, 3)
  alter @m.xselect.m1[w] = agauss(nom_xselect_m1_w, 18n, 3)
  alter @m.xselect.m2[w] = agauss(nom_xselect_m2_w, 18n, 3)
  alter @m.xselect.m3[w] = agauss(nom_xselect_m3_w, 18n, 3)
  alter @m.xselect.m4[w] = agauss(nom_xselect_m4_w, 18n, 3)
  alter @m.xselect.m5[w] = agauss(nom_xselect_m5_w, 18n, 3)
  alter @m.xselect.m6[w] = agauss(nom_xselect_m6_w, 18n, 3)
  alter @m.xselect.m7[w] = agauss(nom_xselect_m7_w, 18n, 3)
  alter @m.xselect.m8[w] = agauss(nom_xselect_m8_w, 18n, 3)
  alter @m.xselect.m9[w] = agauss(nom_xselect_m9_w, 18n, 3)

  alter @m.xselect.mo0[l] = agauss(nom_xselect_mo0_l, 18n, 3)
  alter @m.xselect.mo1[l] = agauss(nom_xselect_mo1_l, 18n, 3)
  alter @m.xselect.m0[l] = agauss(nom_xselect_m0_l, 18n, 3)
  alter @m.xselect.m1[l] = agauss(nom_xselect_m1_l, 18n, 3)
  alter @m.xselect.m2[l] = agauss(nom_xselect_m2_l, 18n, 3)
  alter @m.xselect.m3[l] = agauss(nom_xselect_m3_l, 18n, 3)
  alter @m.xselect.m4[l] = agauss(nom_xselect_m4_l, 18n, 3)
  alter @m.xselect.m5[l] = agauss(nom_xselect_m5_l, 18n, 3)
  alter @m.xselect.m6[l] = agauss(nom_xselect_m6_l, 18n, 3)
  alter @m.xselect.m7[l] = agauss(nom_xselect_m7_l, 18n, 3)
  alter @m.xselect.m8[l] = agauss(nom_xselect_m8_l, 18n, 3)
  alter @m.xselect.m9[l] = agauss(nom_xselect_m9_l, 18n, 3)

  alter @m.xinput.mo0[w] = agauss(nom_xinput_mo0_w, 18n, 3)
  alter @m.xinput.mo1[w] = agauss(nom_xinput_mo1_w, 18n, 3)
  alter @m.xinput.m0[w] = agauss(nom_xinput_m0_w, 18n, 3)
  alter @m.xinput.m1[w] = agauss(nom_xinput_m1_w, 18n, 3)
  alter @m.xinput.m2[w] = agauss(nom_xinput_m2_w, 18n, 3)
  alter @m.xinput.m3[w] = agauss(nom_xinput_m3_w, 18n, 3)
  alter @m.xinput.m4[w] = agauss(nom_xinput_m4_w, 18n, 3)
  alter @m.xinput.m5[w] = agauss(nom_xinput_m5_w, 18n, 3)
  alter @m.xinput.m6[w] = agauss(nom_xinput_m6_w, 18n, 3)
  alter @m.xinput.m7[w] = agauss(nom_xinput_m7_w, 18n, 3)
  alter @m.xinput.m8[w] = agauss(nom_xinput_m8_w, 18n, 3)
  alter @m.xinput.m9[w] = agauss(nom_xinput_m9_w, 18n, 3)

  alter @m.xinput.mo0[l] = agauss(nom_xinput_mo0_l, 18n, 3)
  alter @m.xinput.mo1[l] = agauss(nom_xinput_mo1_l, 18n, 3)
  alter @m.xinput.m0[l] = agauss(nom_xinput_m0_l, 18n, 3)
  alter @m.xinput.m1[l] = agauss(nom_xinput_m1_l, 18n, 3)
  alter @m.xinput.m2[l] = agauss(nom_xinput_m2_l, 18n, 3)
  alter @m.xinput.m3[l] = agauss(nom_xinput_m3_l, 18n, 3)
  alter @m.xinput.m4[l] = agauss(nom_xinput_m4_l, 18n, 3)
  alter @m.xinput.m5[l] = agauss(nom_xinput_m5_l, 18n, 3)
  alter @m.xinput.m6[l] = agauss(nom_xinput_m6_l, 18n, 3)
  alter @m.xinput.m7[l] = agauss(nom_xinput_m7_l, 18n, 3)
  alter @m.xinput.m8[l] = agauss(nom_xinput_m8_l, 18n, 3)
  alter @m.xinput.m9[l] = agauss(nom_xinput_m9_l, 18n, 3)

  tran 10p 150n 40n
  meas tran meas_select_switch_lh TRIG v(s_select) val=1.65 fall=1 targ v(out_select) val=1.65 rise=1
  meas tran meas_select_switch_hl TRIG v(s_select) val=1.65 rise=1 targ v(out_select) val=1.65 fall=1
  meas tran meas_input_switch_lh TRIG v(a_input) val=1.65 rise=1 targ v(out_input) val=1.65 rise=1
  meas tran meas_input_switch_hl TRIG v(a_input) val=1.65 fall=1 targ v(out_input) val=1.65 fall=1

  set simplot = $curplot
  setplot $tran_meas

  let select_switch_lh[current_run] = {$simplot}.meas_select_switch_lh
  let select_switch_hl[current_run] = {$simplot}.meas_select_switch_hl
  let input_switch_lh[current_run] = {$simplot}.meas_input_switch_lh
  let input_switch_hl[current_run] = {$simplot}.meas_input_switch_hl

  destroy $simplot
  let current_run = current_run + 1
end

print select_switch_lh select_switch_hl input_switch_lh input_switch_hl

* write the scale column once, and add a header row of vector names
set wr_singlescale
set wr_vecnames
wrdata mux_mc_delays.txt select_switch_lh select_switch_hl input_switch_lh input_switch_hl

quit
.endc
