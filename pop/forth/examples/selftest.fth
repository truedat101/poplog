\ selftest.fth -- loaded as a .fth file through the Poplog subsystem.
\ Exercises multi-line definitions (which only work for FILE input).

: fib ( n -- fib )
  dup 2 < if drop 1
  else dup 1- recurse
       swap 2 - recurse + then ;

: fact ( n -- n! )
  1 swap begin dup 1 > while tuck * swap 1- repeat drop ;

." fib 10  = "   10 fib  .  cr
." fact 6  = "   6  fact .  cr

\ run the built-in self-test bench too
testbench
