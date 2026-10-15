:Dummy value
V1 1 0 DC 0

.control
  *Set the seed to be fixed so the same values are generated each time
  setseed 12345

  *Create a new plot
  setplot new

  *avar has the same units as nom?
  let n = 1000
  let nom_val = 500n
  let avar_val = 9n
  let sig_val = 3

  *Create a vector and set the scale to the vector
  let samp = vector(n)
  setscale samp

  *Clear the vector
  let my_vec = 0 * samp
  
  define agauss(nom, avar, sig) (nom + avar/sig * sgauss(0))
  let idx = 0
  while idx < n
    
    *Create agauss value
    let sample = agauss(nom_val, avar_val, sig_val)
    
    *Store at idx
    let my_vec[$&idx] = sample

    let idx = idx + 1
  end

  set wr_singlescale
  set wr_vecnames
  wrdata agauss_output.txt my_vec
  echo "Wrote" $&n "values to agauss_output.txt"

  quit
.endc

.end
