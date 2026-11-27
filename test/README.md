# Tests

End-to-end tests that run the real `mic_over_mumble` with a fake sound
server and a fake Mumble client, and the real Mumble server.

## Running

Linux only (the tests and the script use `/proc`):

    sudo apt install bats mumble-server
    sudo systemctl stop mumble-server  # only if port 64738 is busy
    bats test/

The real `mumble-server` is only smoke-tested: the script starts it (and
checks that it is still alive after its wait), and the tests check that it
is gone after the script exits. Nothing checks that it listens or accepts
the client (the fake client doesn't connect).

To test another copy of the script: `MOM_SCRIPT=path/to/script bats test/`
(relative paths are relative to the repository root). Lint with
`shellcheck mic_over_mumble test/stubs/* test/*.bash test/*.bats`.

Each test uses its own `HOME` (with `~/.mic_over_Mumble/initdone`, so no
first-run wizard) and its own stub state directory, both in
`$BATS_TEST_TMPDIR`. All processes the script starts inherit
`MOM_TEST_ID`; the tests use it to check that none is left behind and
teardown kills them.

## Stubs (`test/stubs/`, first on the script's `PATH`)

- `pactl` emulates PipeWire 1.0.5's PulseAudio server, with state in
  `$STUB_STATE`: loaded modules, default sink/source, which sink Mumble
  plays into. It supports what both script versions use (`info`,
  `load-module` for `module-null-sink`/`module-remap-source`/
  `module-virtual-source`, `unload-module`, `list [short]
  sinks|sources|sink-inputs|source-outputs|modules`,
  `get-/set-default-sink|source`, `move-sink-input`). Output is the
  captured text: the static part as is, the blocks for our sink, source
  and Mumble's streams are the captured ones with new IDs. With a
  non-C locale (`LANG=de_DE.UTF-8`, `LC_ALL` unset) only the labels the
  scripts parse are translated to German, as real pactl 16.1 prints them
  with `LANG=de_DE.UTF-8`: `Default Sink:`, `Default Source:`,
  `Sink Input #`, `Sink #`, `Sink:` and `Source #`; everything else
  stays English, so the locale test catches parsing of these labels
  only. Every call is
  logged to `$STUB_STATE/pactl.log`; unsupported calls fail and are
  recorded in `$STUB_STATE/pactl.errors`, which the tests check.
- `mumble` records its arguments and `PIPEWIRE_NODE` in
  `$STUB_STATE/mumble.log`. While it runs, it has a playback stream (sink
  input) in `pactl`: on `PIPEWIRE_NODE` (like Mumble 1.5's PipeWire
  backend) or, with `STUB_MUMBLE_BACKEND=pulse`, on the default sink (so
  the script has to move it). It waits in a `read` builtin, so its
  command line stays `... mumble mumble://localhost` (the script checks
  that before killing it) and a SIGKILL leaves no child behind.
- `sleep` waits a tenth of the requested time (at least 0.1 s).

## Fixtures (`test/fixtures/`)

Captured with `LC_ALL=C pactl ...` (the file name is the command) on
Ubuntu 24.04 with PipeWire 1.0.5, from a VM with null sinks `Speakers`
and `MicBus` and a remap source `HwMic`:

- `pipewire-running/`: while the fixed script (PR #33) was running.
- `pipewire-idle/`: after it exited (only the files the stub needs).

The first test checks that the stub, after the same calls as the script,
reproduces `pipewire-running/` byte for byte, starting from the VM's
defaults `Speakers`/`HwMic`. The other tests start with the defaults
`MicBus`/`MicBus.monitor`: when the default device is unloaded, the stub
falls back to `Speakers`/`HwMic`, like plain PulseAudio 16.1 does
(WirePlumber 0.4 goes back to the previous default by itself), so a script
that doesn't restore the default source fails `assert_cleaned_up`. The
default sink only changes in the test that sets
`STUB_NULL_SINK_BECOMES_DEFAULT=1`: then loading `module-null-sink` makes
the new sink the default. Neither PulseAudio 16.1 nor WirePlumber 0.4 did
that in our VM; the knob covers servers or policies that switch to new
devices. Not captured, so simplified: the client column of
`list short source-outputs` is `-` (neither script reads it).
