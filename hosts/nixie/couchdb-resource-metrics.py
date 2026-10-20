"""Export cgroup-wide resource usage, including CouchDB's Erlang children."""

import os
from pathlib import Path
import subprocess
import tempfile
import time


def collect():
    properties = subprocess.check_output([
        "systemctl", "show", "couchdb.service",
        "--property=ActiveState,CPUUsageNSec,MemoryCurrent,TasksCurrent,NRestarts",
    ], text=True)
    values = dict(line.split("=", 1) for line in properties.splitlines() if "=" in line)
    active = values.get("ActiveState") == "active"
    metrics = []

    def metric(name, kind, help_text, value):
        metrics.extend([f"# HELP {name} {help_text}", f"# TYPE {name} {kind}", f"{name} {value}"])

    metric("couchdb_service_active", "gauge", "Whether CouchDB is active.", int(active))
    for prop, name, kind, divisor, description in [
        ("CPUUsageNSec", "cpu_seconds_total", "counter", 1e9, "Cumulative CPU seconds for the service cgroup."),
        ("MemoryCurrent", "memory_bytes", "gauge", 1, "Service cgroup memory, including filesystem cache."),
        ("TasksCurrent", "tasks", "gauge", 1, "Service cgroup processes and threads."),
        ("NRestarts", "restarts_total", "counter", 1, "Automatic service restarts."),
    ]:
        raw = values.get(prop, "")
        value = int(raw) / divisor if raw.isdigit() and int(raw) < 2**64 - 1 else ("NaN" if active else 0)
        metric("couchdb_service_" + name, kind, description, value)
    size = subprocess.check_output(["du", "--bytes", "--summarize", "/var/lib/couchdb"], text=True).split()[0]
    metric("couchdb_data_size_bytes", "gauge", "Apparent size of the CouchDB data directory.", size)
    metric("couchdb_resource_metrics_timestamp_seconds", "gauge", "Time of the last successful resource sample.", time.time())

    destination = Path("/var/lib/prometheus-node-exporter/textfile/couchdb.prom")
    with tempfile.NamedTemporaryFile(mode="w", dir=destination.parent, prefix="couchdb-", suffix=".tmp", delete=False) as stream:
        temporary = Path(stream.name)
        try:
            stream.write("\n".join(metrics) + "\n")
            stream.flush()
            os.fchmod(stream.fileno(), 0o644)
            temporary.replace(destination)
        finally:
            temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    collect()
