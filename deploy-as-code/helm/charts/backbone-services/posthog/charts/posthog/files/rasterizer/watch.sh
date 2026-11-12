# Runs the rasterizer ("$@") and exits once its Temporal worker reports FAILED.
# Upstream's worker can end in that state when Temporal goes away under it (a restarting frontend
# answers a poll with InvalidArgument), and the process then stays up: /_health keeps answering 200
# while nothing polls rasterization-task-queue, so Replay Vision scans wait until they time out.
# On that log line the worker gets SIGTERM, SIGKILL after 15 s, and the kubelet restarts the container.
# SIGTERM to this shell is forwarded, so in-flight renders still drain on a normal shutdown.
set -u
fifo=/tmp/rasterizer-stdout
rm -f "$fifo" && mkfifo "$fifo"
"$@" >"$fifo" 2>&1 &
pid=$!
trap 'kill -TERM "$pid" 2>/dev/null' TERM INT
# mawk buffers piped input in blocks unless interactive; the FAILED line would sit there.
if command -v mawk >/dev/null 2>&1; then awk="mawk -W interactive"; else awk=awk; fi
$awk -v pid="$pid" '
  { print; fflush() }
  !failed && /"state":"FAILED"/ && /Worker state changed/ {
    failed = 1
    print "{\"level\":\"error\",\"source\":\"chart\",\"msg\":\"Temporal worker FAILED; stopping the rasterizer so the pod restarts\"}"; fflush()
    system("(kill -TERM " pid "; sleep 15; kill -KILL " pid ") 2>/dev/null &")
  }' <"$fifo" &
watcher=$!
rc=0
wait "$pid" || rc=$?
while kill -0 "$pid" 2>/dev/null; do rc=0; wait "$pid" || rc=$?; done
wait "$watcher" 2>/dev/null
exit "$rc"
