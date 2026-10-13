* xor gate
.subckt xor2x1 a b y

*nor gate stage
M0 n2 b n3  vdd tp L=5e-7 W=5.6e-7
M1 n3 a vdd vdd tp L=5e-7 W=5.6e-7

M2 n2 a vss vss tn L=6e-7 W=3.6e-7
M3 n2 b vss vss tn L=6e-7 W=3.6e-7

* output stage
M4 n0 n2 vdd vdd tp L=5e-7 W={2.25666 * 8.2e-7}	$ width must be computed
M5  y a  n0  vdd tp L=5e-7 W={2.25666 * 8.2e-7}	$ width must be computed
M6  y b  n0  vdd tp L=5e-7 W={2.25666 * 8.2e-7}	$ width must be computed

M7  y n2 vss vss tn L=6e-7 W=8.2e-7
M8  y a  n1  vss tn L=6e-7 W=8.2e-7
M9 n1 b  vss vss tn L=6e-7 W=8.2e-7

.model tn nmos level=54 version=4.8.2 TOXE=8.00n
.model tp pmos level=54 version=4.8.2 TOXE=7.90n
.ends

