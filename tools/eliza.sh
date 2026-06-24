#!/bin/sh
# eliza.sh -- chat with the Pop-11 ELIZA (Weizenbaum's DOCTOR), locally.
#
#   tools/eliza.sh                 # interactive session
#   echo 'I am sad.' | tools/eliza.sh    # or pipe a conversation
#
# Type at it; `bye`, `goodbye`, `quit`, or end-of-file (Ctrl-D) leaves.
# Implementation: examples/eliza.p  (script: examples/doctor.txt).

U=$(cd "$(dirname "$0")/.." && pwd)          # repo root
exec "$U/poplog" "$U/target/pop/basepop11" "$U/examples/eliza.p"
