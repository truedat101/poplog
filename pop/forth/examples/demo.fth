\ demo.fth -- a tour of Poplog Forth ( load with forth_load )

: square ( n -- n^2 )  dup * ;
: cube   ( n -- n^3 )  dup square * ;

\ classic recursive fibonacci ( compiles to a native Poplog procedure )
: fib ( n -- fib )
  dup 2 < if drop 1
  else dup 1- recurse  swap 2 - recurse  + then ;

\ iterative factorial with a begin/while/repeat loop
: fact ( n -- n! )
  1 swap begin dup 1 > while  tuck * swap 1-  repeat drop ;

\ greatest common divisor
: gcd ( a b -- gcd )
  begin ?dup while tuck mod repeat ;

7  square .   cr
3  cube .     cr
10 fib .      cr
6  fact .     cr
48 36 gcd .   cr
