# Developer notes

- [../FINDINGS.md](../FINDINGS.md): findings and evidence per measure. Packaged with the other
  pages under `/usr/share/doc/macbook91-hw-fixes/docs/`, so the links work there too.
- [../test-status.json](../test-status.json): every test run with its result and the open
  hardware gates. [../coverage.json](../coverage.json): the coverage matrix.
- `STRUCTURE.md` in the repository root: what lives where.
- Build and test: `make dist && make arch-pkg`; `tests/run-tests.sh` runs the hermetic tests.

## Verification status

Run on the test machine on 2026-11-09 with package 20261102.01-1 on kernel 7.3.3-1-cachyos: the
read-only commands (`macbook91-hw-verify`, `macbook91-hw-migrate status` and `plan`,
`kernel-series`, `sha256sum -c` on a release). The commands that change the system are NOT
VERIFIED for this version. The modules were checked with `linux-cachyos-lts` 6.18.55-2 (GCC
16.2.1) and `linux-cachyos` 7.2.11-1 (clang 23.1.3).

VERIFIED on 6.18 (maintainer, 2026-10-20, earlier package 20261020.01-1, `macbook91-hw-verify`:
`pass=26 warn=0 fail=0`): all five DKMS modules installed, charge limit readable (read, not
changed), backlight native with 1001 CIE L* levels, NVMe `d3cold_allowed` 0, keyboard and light
present. The verify tools of the three driver packages pass; see "Kernel 6.18 LTS" in FINDINGS.md.

NOT VERIFIED on 6.18: suspend and resume, wake with the lid, the backlight across a suspend,
and whether a charge limit below 100 % persists (`suspend_stats` success 0 in the checked
boot). The hardware suspend series for 6.18 is NOT_RUN; earlier suspend results were measured on
7.2 and say nothing about 6.18.
