* mux2x1

.subckt mux2x1 a b s y

* invert the output
mo0 y ny vdd vdd tp L=500n W={1.87651 * 820n}
mo1 y ny vss vss tn L=600n W=820n

* invert s
m0 ns s vdd vdd tp L=500n W=820n
m1 ns s vss vss tn L=500n W=820n

* these networks generate the inverted output y
* pullup networks
* if s is 0 and a is 0 then the output should be 1
m2 ny s n00x vdd tp L=500n W={2.16896 * 820n}
m3 n00x a vdd vdd tp L=500n W={2.16896 * 820n}
* if s is 1 and b is 0 then the output should be 1
m4 ny ns n1x0 vdd tp L=500n W={2.16896 * 820n}
m5 n1x0 b vdd vdd tp L=500n W={2.16896 * 820n}

* pulldown networks
* if s is 0 and a is 1 then the output should be 0
m6 ny ns n11x vss tn L=500n W=820n
m7 n11x a vss vss tn L=500n W=820n
* if s is 1 and b is 1 then the output should be 0
m8 ny s n1x1 vss tn L=500n W=820n
m9 n1x1 b vss vss tn L=500n W=820n

.model tp pmos level=54 version=4.8.2 TOXE=7.90n
.model tn nmos level=54 version=4.8.2 TOXE=8.00n

.ends

