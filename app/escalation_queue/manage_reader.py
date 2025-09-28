"""Command line interface for reading from the escalation queue."""

import argparse
import logging
import sys
from typing import Iterable

from app.escalation_queue.queue_reader import QueueReader


def build_parser() -> argparse.ArgumentParser:
    """Construct the argument parser for the CLI."""
    parser = argparse.ArgumentParser(
        description="Stream items from the escalation queue using QueueReader.",
    )
    parser.add_argument(
        "--base-dir",
        default=None,
        help=(
            "Optional base directory for the escalation queue. When omitted, the default "
            "configured within QueueReader is used."
        ),
    )
    parser.add_argument(
        "--log-level",
        default="INFO",
        choices=["CRITICAL", "ERROR", "WARNING", "INFO", "DEBUG"],
        help="Logging verbosity level (default: INFO).",
    )
    return parser


def configure_logging(level: str) -> None:
    """Configure basic logging for the CLI."""
    logging.basicConfig(level=getattr(logging, level.upper(), logging.INFO))


def stream_queue_items(reader: Iterable[str]) -> None:
    """Stream queue items to stdout."""
    for item in reader:
        sys.stdout.write(item)
        if not item.endswith("\n"):
            sys.stdout.write("\n")
        sys.stdout.flush()


def main(argv: list[str] | None = None) -> int:
    """Entry point for the escalation queue reader CLI."""
    parser = build_parser()
    args = parser.parse_args(argv)

    configure_logging(args.log_level)

    queue_reader = QueueReader(base_dir=args.base_dir) if args.base_dir else QueueReader()

    try:
        stream_queue_items(queue_reader)
    except KeyboardInterrupt:
        logging.getLogger(__name__).info("Stopping queue reader.")
        return 0

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
