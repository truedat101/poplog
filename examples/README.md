# Examples

Small, self-contained Pop-11 programs.

## Graphics demos

These use the experimental native graphics backend (`uses popgfx` /
`uses rc_graphic`), so they need a Poplog built with
`./configure --experimental-graphics` (Metal on macOS, SDL3 + OpenGL on
Linux; see `BENCHMARKS.md`/`nix` for builds — `nix build .#poplog-gfx`).
Each opens a window that stays up for about a minute, or until you close it.

```sh
./poplog ./target/pop/basepop11 examples/<name>.p
```

| File | What it draws |
| --- | --- |
| `tenprint.p` | The classic [10 PRINT](https://10print.org/) random-diagonal maze (`10 PRINT CHR$(205.5+RND(1)); : GOTO 10`). |
| `cube3d.p` | A spinning 3D wireframe cube, perspective-projected and redrawn each frame. |
| `poplog_letters.p` | The word **POPLOG** in giant block letters — each big letter drawn out of small copies of itself. |
| `impossible_triangle.p` | The Penrose "tribar" impossible triangle, from three rotated beams. |
| `vectrex.p` | A concept "screenshot" for a [Vectrex](https://en.wikipedia.org/wiki/Vectrex)-style vector game (Asteroids/Minestorm): HUD, ship, drifting rocks, shots. |
| `rc_square.p` | Minimal `rc_graphic` turtle demo — a square. |
| `rc_spiral.p` | `rc_graphic` turtle spiral. |
