# StrongBox Op-Limit Unlocker

A KernelSU / Magisk module that lifts the **per-UID StrongBox concurrent-operation limit** enforced by
[TEESimulator-RS](https://github.com/Enginex0/TEESimulator-RS) (the `tricky_store` module).

## Problem

TEESimulator-RS simulates a hardware StrongBox and, to stay faithful to real hardware, caps each app at
**4 concurrent StrongBox operations** (`STRONGBOX_MAX_CONCURRENT_OPS`, hardcoded). When an app opens a 5th
concurrent StrongBox operation, keystore returns `TOO_MANY_OPERATIONS` and the app crashes:

```
java.lang.RuntimeException: Unable to create application ...
 Caused by: java.security.KeyStoreException: the master key
            android-keystore://_androidx_security_master_key_ exists but is unusable
 Caused by: java.security.InvalidKeyException: Keystore operation failed
 Caused by: android.security.KeyStoreException: -29 Error::Km(TOO_MANY_OPERATIONS)
```

TEESimulator log at the moment of failure:

```
TEESimulator: StrongBox op limit reached for uid=NNNNN (hw=4 sw=0 max=4)
```

This hits any StrongBox-backed app that opens several keystore operations during startup — typically
`androidx.security` **EncryptedSharedPreferences / MasterKey** users. Reported upstream for 1Password
(#39), pagoPA (#59), DATEV Smartlogin (PR #81), react-native-keychain apps (#49), and more. Upstream
PR #81 (raise the cap to 32) is open but **not merged or released** as of this writing.

## What this module does

It patches **one instruction** in TEESimulator's `classes.dex`
(`KeyMintSecurityLevelInterceptor.trackAndEnforceOpLimit`): the limit comparison

```
if-lt v7, v1, 00ba    # if (total < 4) allow  ->  4 inlined as const/4
```

is changed to an always-true comparison

```
if-le v7, v7, 00ba    # v7 <= v7 is always true -> always allow
```

i.e. the artificial StrongBox op cap is **removed** (behaviour returns to how StrongBox apps run on a
normal device). Only 2 bytes of the instruction change; the dex header SHA-1 signature and Adler-32
checksum are recomputed.

> **Scope:** the cap is a single global constant, so lifting it applies to **all** apps, not any single one.
> This is generally desirable (it fixes the whole class of `TOO_MANY_OPERATIONS` crashes). Attestation /
> Play Integrity spoofing is a separate code path and is **not** touched.

### Why not exactly 32 (like PR #81)?

`const/4` only holds a 4-bit literal (max 7). Writing 32 needs a wider `const/16`, which changes the
instruction length and would shift every following branch offset — not an in-place patch. Removing the cap
is a clean 2-byte edit and is strictly sufficient.

## Safety / behaviour

The module is **hash-gated** (see `module/apply_patch.sh`). On install and on every boot it checks the
current `tricky_store/classes.dex`:

| Current dex                         | Action                                             |
|-------------------------------------|----------------------------------------------------|
| original v6.0.1-307 (`a90f5e0a…`)   | back it up, apply patch, restart TEESimulator      |
| already patched (`e23952ab…`)       | nothing to do                                      |
| **anything else** (other version)   | **do nothing** (logs a warning) — never breaks it  |

So a TEESimulator update that changes the dex will simply not be patched (the app that needs it breaks
again, but the module cannot corrupt a version it doesn't recognise). Re-generate for the new version
(see below).

- Original dex is backed up to `/data/adb/modules/tricky_store/classes.dex.orig_bak`.
- Fully reversible: restore that backup (or remove this module + restore) and reboot.
- Log: `/data/adb/modules/strongbox_oplimit_unlock/patch.log`.

## Install

1. Confirm `tricky_store` is **v6.0.1-307**.
2. KernelSU manager → Modules → Install from storage → pick the zip.
3. The install screen applies it immediately and restarts TEESimulator; a reboot is recommended.
4. Verify:
   ```
   adb shell "su -mm -c 'cat /data/adb/modules/strongbox_oplimit_unlock/patch.log'"
   ```

## Rebuilding for a different TEESimulator version

The pinned hashes and byte offset are specific to v6.0.1-307. For a new version:

1. Pull the module's `classes.dex`, disassemble with `dexdump -d`, and find
   `KeyMintSecurityLevelInterceptor.trackAndEnforceOpLimit` — the `const/4 … #int 4` + `if-lt` pair that
   precedes the `"StrongBox op limit reached"` log string.
2. Update the offsets / expected bytes in `tools/patch_dex.py`, then:
   ```
   python patch_dex.py classes.dex.orig classes.dex.patched
   ```
   (The script asserts the original bytes before writing, so a mismatch aborts safely.)
3. Replace `module/classes.dex.patched` and update both SHA-256 hashes in `module/apply_patch.sh`.
4. Repackage `module/` into a zip.

## Layout

```
module/            flashable KernelSU/Magisk module
  module.prop
  apply_patch.sh   hash-gated patch logic (shared by install + boot)
  service.sh       runs apply_patch on every boot
  customize.sh     runs apply_patch at install time
  classes.dex.patched
  META-INF/...      Magisk-compatible installer (KernelSU uses customize.sh)
tools/
  patch_dex.py     regenerates classes.dex.patched from an original dex
```

## License

GPL-3.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).

`module/classes.dex.patched` is a binary-patched derivative of
[TEESimulator-RS](https://github.com/Enginex0/TEESimulator-RS) (GPL-3.0), so
this module is also distributed under **GPL-3.0**. Upstream (corresponding
source) and credits: TEESimulator-RS by Enginex0, a fork of
[JingMatrix/TEESimulator](https://github.com/JingMatrix/TEESimulator). Patch
approach informed by upstream issues/PRs #39, #49, #59, #81.
