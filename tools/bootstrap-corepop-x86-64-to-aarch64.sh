#!/usr/bin/sh
export POP__as=/usr/bin/aarch64-linux-gnu-as
make CC="aarch64-linux-gnu-gcc -no-pie -Wl,-export-dynamic -Wl,--no-as-needed" \
	stamp_new_corepop
cp target/pop/new_corepop target/pop/corepop.arm64
