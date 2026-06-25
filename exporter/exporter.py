#!/usr/bin/env python3
"""
Smart Infrastructure Monitoring Platform - Metrics Exporter
Serves Prometheus textfile metrics over HTTP on port 9200.
monitor.sh writes /data/metrics.prom; this exposes it to Prometheus.
"""

import os
import time
import logging
from http.server import HTTPServer, BaseHTTPRequestHandler

METRICS_FILE = os.environ.get("METRICS_FILE", "/data/metrics.prom")
PORT = int(os.environ.get("EXPORTER_PORT", "9200"))

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)

FALLBACK_METRICS = """\
# HELP monitor_exporter_up 1 if exporter is running
# TYPE monitor_exporter_up gauge
monitor_exporter_up 1
# HELP monitor_metrics_file_missing 1 if metrics file is not yet written
# TYPE monitor_metrics_file_missing gauge
monitor_metrics_file_missing 1
"""


class MetricsHandler(BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802
        if self.path not in ("/metrics", "/"):
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"404 Not Found\n")
            return

        if os.path.exists(METRICS_FILE):
            try:
                with open(METRICS_FILE, "r") as f:
                    content = f.read()
                # Append exporter health metric
                content += "\n# HELP monitor_exporter_up 1 if exporter is running\n"
                content += "# TYPE monitor_exporter_up gauge\n"
                content += "monitor_exporter_up 1\n"
                content += "# HELP monitor_metrics_file_missing 1 if metrics file is not yet written\n"
                content += "# TYPE monitor_metrics_file_missing gauge\n"
                content += "monitor_metrics_file_missing 0\n"
                body = content.encode("utf-8")
            except Exception as exc:
                logger.error("Failed to read metrics file: %s", exc)
                body = FALLBACK_METRICS.encode("utf-8")
        else:
            logger.warning("Metrics file not found: %s", METRICS_FILE)
            body = FALLBACK_METRICS.encode("utf-8")

        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):  # suppress default access log spam
        logger.debug(fmt, *args)


if __name__ == "__main__":
    logger.info("Exporter starting on :%d — serving %s", PORT, METRICS_FILE)
    server = HTTPServer(("0.0.0.0", PORT), MetricsHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Exporter stopped")
