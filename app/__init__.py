import logging
import os
from pathlib import Path
from typing import TYPE_CHECKING

from fastapi import FastAPI
from fastapi.responses import HTMLResponse

if TYPE_CHECKING:
    from apscheduler.schedulers.asyncio import AsyncIOScheduler

    from app.metrics.metric_reporting import MetricsReporter

ONE_HOUR_IN_SECONDS = 3600
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO").upper()

app = FastAPI(title="status-monitor")
scheduler: "AsyncIOScheduler | None" = None
reporter: "MetricsReporter | None" = None


@app.on_event("startup")
async def startup_event():
    """Lifecycle event that is triggered when the application starts."""
    from apscheduler.schedulers.asyncio import AsyncIOScheduler

    from app.metrics.iq_activity import clear_old_activity_files
    from app.metrics.metric_reporting import MetricsReporter

    logging.basicConfig(
        level=LOG_LEVEL, format="%(asctime)s.%(msecs)03d %(levelname)s %(message)s", datefmt="%Y-%m-%d %H:%M:%S"
    )
    logging.info("Starting status-monitor server...")
    logging.info("Will report metrics to the cloud every hour")

    global scheduler
    scheduler = AsyncIOScheduler()

    global reporter
    reporter = MetricsReporter()

    # Every hour, on the hour, collect metrics to send to the cloud.
    scheduler.add_job(reporter.collect_metrics_for_cloud, "cron", hour="*", minute="0")
    # Every hour, try to report collected metrics to the cloud. Run at 3 minutes past the hour, with a jitter of 120
    # seconds, to avoid every edge-endpoint report hitting the server at the exact same time.
    scheduler.add_job(reporter.report_metrics_to_cloud, "cron", hour="*", minute="3", jitter=120)
    scheduler.add_job(clear_old_activity_files, "interval", seconds=ONE_HOUR_IN_SECONDS)
    scheduler.start()


@app.get("/status/metrics.json")
async def get_metrics():
    """Return system metrics as JSON."""
    if reporter is None:
        from app.metrics.metric_reporting import MetricsReporter

        return MetricsReporter().metrics_payload()
    return reporter.metrics_payload()


@app.get("/status")
async def get_status():
    """Serve the status monitoring HTML page."""
    html_path = Path(__file__).parent / "static" / "status.html"
    with open(html_path, "r") as f:
        html_content = f.read()
    return HTMLResponse(content=html_content)
