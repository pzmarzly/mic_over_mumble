#!/usr/bin/env bats
# shellcheck shell=bash
# End-to-end tests: the real script (or $MOM_SCRIPT), fake pactl/mumble,
# real mumble-server. See test/README.md.

load helpers

@test "pactl stub reproduces the captured PipeWire state" {
    q set-default-sink Speakers # the defaults in the VM
    q set-default-source HwMic
    q load-module module-null-sink sink_name=Loopback_of_Mumble \
        sink_properties=device.description=Loopback_of_Mumble
    q load-module module-remap-source source_name=VirtualMic \
        master=Loopback_of_Mumble.monitor source_properties=device.description=VirtualMic
    q set-default-source VirtualMic
    MOM_TEST_ID=$BATS_TEST_TMPDIR PIPEWIRE_NODE=Loopback_of_Mumble \
        "$STUBS/mumble" mumble://localhost 3>&- &
    poll mumble_playing
    local f cmd
    for f in info get-default-sink get-default-source list_sinks list_sources \
        list_modules list_sink-inputs list_source-outputs list_short_modules \
        list_short_sink-inputs; do
        read -ra cmd <<< "${f//_/ }"
        diff -u "$RUNNING/$f.txt" <(q "${cmd[@]}")
    done
}

# Regression test for PR #29 (pactl output parsed as pacmd output).
@test "starts, reaches 'Press Return', cleans up on Return (PipeWire backend)" {
    start_script
    wait_for "Press Return"
    assert_set_up
    press_return
    wait_exit
    [ "$status" -eq 0 ]
    assert_cleaned_up
}

@test "moves Mumble's stream when Mumble ignores PIPEWIRE_NODE (PulseAudio backend)" {
    start_script STUB_MUMBLE_BACKEND=pulse
    wait_for "Press Return"
    assert_set_up
    grep -q '^move-sink-input ' "$STUB_STATE/pactl.log"
    press_return
    wait_exit
    [ "$status" -eq 0 ]
    assert_cleaned_up
}

@test "keeps the default sink when the new sink becomes the default" {
    start_script STUB_NULL_SINK_BECOMES_DEFAULT=1
    wait_for "Press Return"
    assert_set_up
    [ "$(q get-default-sink)" = "$INITIAL_SINK" ]
    press_return
    wait_exit
    [ "$status" -eq 0 ]
    assert_cleaned_up
}

@test "SIGINT (Ctrl+C) at the prompt cleans up" {
    start_script
    wait_for "Press Return"
    kill -INT "$PID"
    wait_exit
    [ "$status" -eq 130 ]
    assert_cleaned_up
}

@test "SIGTERM at the prompt cleans up" {
    start_script
    wait_for "Press Return"
    kill -TERM "$PID"
    wait_exit
    [ "$status" -eq 143 ]
    assert_cleaned_up
}

@test "parsing does not depend on the locale" {
    start_script LANG=de_DE.UTF-8 LC_ALL= LC_MESSAGES= STUB_MUMBLE_BACKEND=pulse
    wait_for "Press Return"
    assert_set_up
    press_return
    wait_exit
    [ "$status" -eq 0 ]
    assert_cleaned_up
}
