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

\ --- variables (Poplog refs under the hood) ---
variable counter
: bump   counter @ 1+ counter ! ;
bump bump bump   ." counter = "  counter @ .  cr

\ --- counted loops + strings (loops live inside : definitions) ---
: stars    ( n -- )   0 do ." *" loop cr ;
: triangle ( -- )     6 1 do i stars loop ;
triangle

\ --- nested loops: a multiplication table ---
: row    ( n -- )   4 1 do dup i * . loop drop cr ;
: table  ( -- )     ." mult table:" cr  4 1 do i row loop ;
table

: greet  ." Hello from Poplog Forth!" cr ;
greet
