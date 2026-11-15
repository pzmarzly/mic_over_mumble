# shellcheck shell=bash
# Helpers for mic_over_mumble.bats: run the real script against the stubs
# in test/stubs and the real mumble-server.

REPO=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
STUBS=$BATS_TEST_DIRNAME/stubs
IDLE=$BATS_TEST_DIRNAME/fixtures/pipewire-idle
# shellcheck disable=SC2034 # used in the .bats file
RUNNING=$BATS_TEST_DIRNAME/fixtures/pipewire-running

setup() {
    SCRIPT=${MOM_SCRIPT:-./mic_over_mumble}
    [[ $SCRIPT == /* ]] || SCRIPT=$REPO/$SCRIPT
    export STUB_STATE=$BATS_TEST_TMPDIR/state
    TEST_HOME=$BATS_TEST_TMPDIR/home
    OUT=$BATS_TEST_TMPDIR/output
    mkdir -p "$STUB_STATE" "$TEST_HOME/.mic_over_Mumble"
    touch "$TEST_HOME/.mic_over_Mumble/initdone" "$OUT"
    # Not the devices the stub falls back to when the default one is
    # unloaded (Speakers/HwMic): if the script doesn't restore the
    # defaults, assert_cleaned_up notices.
    q set-default-sink MicBus
    q set-default-source MicBus.monitor
    INITIAL_SINK=$(q get-default-sink)
    INITIAL_SOURCE=$(q get-default-source)
}

teardown() {
    if [ -n "${KEEP:-}" ]; then
        exec {KEEP}>&-
    fi
    local pids
    mapfile -t pids < <(test_pids)
    if [ ${#pids[@]} -gt 0 ]; then
        kill -KILL "${pids[@]}" 2>/dev/null || true
    fi
    if [ -n "${PID:-}" ]; then
        wait "$PID" 2>/dev/null || true
    fi
    echo "--- script output:"
    cat "$OUT"
    echo "--- pactl calls:"
    cat "$STUB_STATE/pactl.log" 2>/dev/null || true
}

# Query the fake sound server (not logged).
q() { STUB_NOLOG=1 LC_ALL=C "$STUBS/pactl" "$@"; }

# Processes started by this test's script run: they inherit MOM_TEST_ID.
test_pids() {
    local p
    for p in /proc/[0-9]*; do
        if grep -qzxF "MOM_TEST_ID=$BATS_TEST_TMPDIR" "$p/environ" 2>/dev/null; then
            echo "${p#/proc/}"
        fi
    done
}

# start_script [VAR=value...]: start the script in the background, with
# its stdin on a fifo we write to via fd $KEEP. Perl resets SIGINT, which
# bash ignores in background jobs (and the script then couldn't trap it).
start_script() {
    mkfifo "$BATS_TEST_TMPDIR/stdin"
    perl -e '$SIG{INT} = $SIG{QUIT} = "DEFAULT"; exec @ARGV or die "exec: $!"' \
        env HOME="$TEST_HOME" PATH="$STUBS:$PATH" MOM_TEST_ID="$BATS_TEST_TMPDIR" \
        "$@" "$SCRIPT" < "$BATS_TEST_TMPDIR/stdin" > "$OUT" 2>&1 3>&- &
    PID=$!
    exec {KEEP}> "$BATS_TEST_TMPDIR/stdin"
}

# Sends Return to the script. If it has exited already (the fifo has no
# reader), the write must not kill the test with SIGPIPE: the checks
# after it report what went wrong.
press_return() {
    (trap '' PIPE; echo >&"$KEEP") 2>/dev/null || echo "press_return: nobody reads the fifo (script exited?)"
}

# poll CMD...: until CMD succeeds, 30 s at most.
poll() {
    local i
    for ((i = 0; i < 300; i++)); do
        "$@" && return 0
        sleep 0.1
    done
    echo "timed out: $*"
    return 1
}

# The script is alive (not a zombie).
running() {
    local state
    state=$(cut -d' ' -f3 "/proc/$PID/stat" 2>/dev/null) && [ -n "$state" ] && [ "$state" != Z ]
}
exited() { ! running; }
printed() { grep -qF -e "$1" "$OUT"; }
printed_or_exited() { printed "$1" || exited; }

# wait_for TEXT: until the script prints TEXT; fails if it exits first.
wait_for() {
    poll printed_or_exited "$1"
    printed "$1" || { echo "script exited before printing '$1'"; return 1; }
}

# Waits for the script to exit and sets $status to its exit code.
# shellcheck disable=SC2034 # $status is used by the tests
wait_exit() {
    poll exited
    status=0
    wait "$PID" || status=$?
}

mumble_playing() { [ -n "$(q list short sink-inputs)" ]; }
sink_id() { q list short sinks | awk -v n="$1" '$2 == n { print $1 }'; }

# At the prompt: our devices exist and Mumble plays into our sink.
assert_set_up() {
    [ -n "$(sink_id Loopback_of_Mumble)" ]
    q list short sources | grep -q $'\tVirtualMic\t'
    [ "$(q list short sink-inputs | cut -f2)" = "$(sink_id Loopback_of_Mumble)" ]
    [ "$(q get-default-source)" = VirtualMic ]
}

# After exit: the sound server is as captured after a real run, the
# defaults are restored and no process of ours is left.
assert_cleaned_up() {
    diff -u "$IDLE/list_short_modules.txt" <(q list short modules)
    diff -u "$IDLE/list_short_sinks.txt" <(q list short sinks)
    diff -u "$IDLE/list_short_sources.txt" <(q list short sources)
    [ "$(q get-default-sink)" = "$INITIAL_SINK" ]
    [ "$(q get-default-source)" = "$INITIAL_SOURCE" ]
    diff -u "$IDLE/list_sink-inputs.txt" <(q list sink-inputs)
    local left
    left=$(test_pids)
    if [ -n "$left" ]; then
        echo "processes left over:"
        ps -o pid=,args= -p "${left//$'\n'/,}"
        return 1
    fi
    if [ -s "$STUB_STATE/pactl.errors" ]; then
        echo "unsupported pactl calls:"
        cat "$STUB_STATE/pactl.errors"
        return 1
    fi
}
