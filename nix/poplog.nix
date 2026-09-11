# Poplog package: builds the full system (basepop11 + the four language
# images) from source, bootstrapped by a per-platform binary seed
# `corepop` vendored under nix/seeds/ (replaceable by a fetchurl of a
# release artifact -- see `seed` below).
#
# Poplog generates and executes its own machine code and lays memory
# out at fixed addresses, so standard hardening (PIE, relro, stack
# protectors) must be off; the seed binary is patchelf'd so it can run
# inside the build sandbox.

{ lib, stdenv, system, self
, ncurses, perl, patchelf
, sigtool ? null
# --- experimental native graphics (Dear ImGui) ---------------------------
# withGraphics builds basepop11 with --experimental-graphics.  On Linux the
# backend is SDL3 + OpenGL3 (imgui_backend_sdl.cpp); on macOS it is Metal +
# Cocoa (imgui_backend.mm), whose frameworks come from the Darwin stdenv SDK
# (no extra derivations).  Either way the ImGui source is a fetchFromGitHub
# FOD because the sandbox has no network and the in-tree pop/extern/imgui/ is
# gitignored.
, withGraphics ? false
, sdl3 ? null, libGL ? null, pkg-config ? null, imgui ? null
}:

let
  seedName = {
    "x86_64-linux"   = "corepop-x86_64-linux";
    "aarch64-linux"  = "corepop-aarch64-linux";
    "aarch64-darwin" = "corepop-aarch64-darwin";
    "riscv64-linux"  = "corepop-riscv64-linux";
  }.${system};
  seed = "${self}/nix/seeds/${seedName}";
  isDarwin = stdenv.isDarwin;
in
stdenv.mkDerivation {
  pname = "poplog" + lib.optionalString withGraphics "-gfx";
  version = "16.1-arm64";

  src = self;

  # self-modifying / fixed-address runtime: no hardening
  hardeningDisable = [ "all" ];

  nativeBuildInputs =
    lib.optionals (!isDarwin) [ patchelf ]
    ++ lib.optionals (isDarwin && sigtool != null) [ sigtool ]
    # SDL3 is found via pkg-config on Linux; macOS links frameworks directly
    ++ lib.optionals (withGraphics && !isDarwin) [ pkg-config ];
  buildInputs = [ ncurses ]
    # Linux gfx: SDL3 + OpenGL.  macOS gfx: Metal/Cocoa come from the stdenv SDK.
    ++ lib.optionals (withGraphics && !isDarwin) [ sdl3 libGL ];

  postPatch = ''
    patchShebangs scripts tools || true
  '';

  configurePhase = ''
    runHook preConfigure
    export HOME=$TMPDIR
    # install the seed corepop first (configure checks for it)
    mkdir -p target/pop
    cp ${seed} target/pop/corepop
    chmod 755 target/pop/corepop
    ${lib.optionalString (!isDarwin) ''
      # make the foreign seed binary runnable inside the sandbox
      # (it links only libc/libm/libdl)
      patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
               --set-rpath "${stdenv.cc.libc}/lib" \
               target/pop/corepop
    ''}
    ${lib.optionalString withGraphics ''
      # vendor the ImGui source (fetch-imgui.sh can't run -- no network);
      # the tree is gitignored so it isn't in src=self.
      mkdir -p pop/extern/imgui
      cp -R ${imgui}/. pop/extern/imgui/
      chmod -R u+w pop/extern/imgui
    ''}
    ./configure ${if withGraphics then "--experimental-graphics" else "--with_no_x"}
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    # the sandbox has no /usr/bin/{as,ar}; popc honours these overrides
    export POP__as="$(command -v as)"
    export POP__ar="$(command -v ar)"
    export POP__ranlib="$(command -v ranlib)"
    make all
    runHook postBuild
  '';

  # the build validates itself: the smoke test is part of installPhase
  installPhase = ''
    runHook preInstall
    mkdir -p $out/poplog $out/bin
    cp -R pop $out/poplog/pop
    cp -R target $out/poplog/target
    cp -R scripts $out/poplog/scripts 2>/dev/null || true

    # runtime wrapper: every entry point is the env script + an engine
    cat > $out/poplog/poplog <<WRAP
#!/bin/sh
usepop=$out/poplog
popsrc=\$usepop/pop/src; popsys=\$usepop/target/pop
popexternlib=\$usepop/target/exlib; popobjlib=\$usepop/target/obj
export usepop popsrc popsys popexternlib popobjlib
popautolib=\$usepop/pop/lib/auto; popdatalib=\$usepop/pop/lib/data
popliblib=\$usepop/pop/lib/lib; popvedlib=\$usepop/pop/lib/ved
poppackages=\$usepop/pop/packages
export popautolib popdatalib popliblib popvedlib poppackages
poplocal=\''${poplocal:-\$HOME/.poplog}; poplocalauto=\$poplocal/auto
poplocalbin=\$poplocal/bin; popcontrib=\$usepop/pop/packages/contrib
export poplocal poplocalauto poplocalbin popcontrib
poplib=\''${poplib:-\$HOME}; popsavelib=\$usepop/target/psv
popcomppath=':\$poplib:\$poplocalauto:\$popautolib:\$popliblib'
popsavepath=':\$poplib:\$poplocalbin:\$popsavelib'
export poplib popsavelib popsavepath popcomppath
exec "\$@"
WRAP
    chmod +x $out/poplog/poplog

    for tool in basepop11 pop11 ved; do
      cat > $out/bin/$tool <<EOT
#!/bin/sh
exec $out/poplog/poplog $out/poplog/target/pop/basepop11 \''${0##*/} "\$@"
EOT
      chmod +x $out/bin/$tool
    done
    # pop11 is the bare engine, not a "command" argument
    cat > $out/bin/pop11 <<EOT
#!/bin/sh
exec $out/poplog/poplog $out/poplog/target/pop/basepop11 "\$@"
EOT
    chmod +x $out/bin/pop11
    for lang in clisp prolog pml; do
      cat > $out/bin/$lang <<EOT
#!/bin/sh
exec $out/poplog/poplog $out/poplog/target/pop/basepop11 +$out/poplog/target/psv/$lang.psv "\$@"
EOT
      chmod +x $out/bin/$lang
    done

    # smoke test the installed tree
    res=$(echo '6 * 7 =>' | $out/bin/pop11)
    echo "$res" | grep -q '\*\* 42' || { echo "POPLOG SMOKE TEST FAILED: $res"; exit 1; }
    runHook postInstall
  '';

  # binaries embed fixed addresses and self-generated code: leave them alone
  dontStrip = true;
  dontPatchELF = true;
  dontFixup = isDarwin;

  meta = with lib; {
    description = "Poplog: incremental Pop-11, Prolog, Common Lisp and Standard ML";
    homepage = "https://github.com/truedat101/poplog";
    license = licenses.mit;  # Free Poplog licence (XFree86-style)
    platforms = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "riscv64-linux" ];
  };
}
