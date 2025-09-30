"""Utility helpers for working with the escalation queue."""

from __future__ import annotations

import logging
from typing import Any

from app.escalation_queue.models import EscalationInfo
from app.escalation_queue.queue_writer import QueueWriter

logger = logging.getLogger(__name__)


def write_escalation(
    queue_writer: QueueWriter,
    escalation_info: EscalationInfo,
    detector_id: str,
    *,
    context: dict[str, Any] | None = None,
) -> bool:
    """Write an escalation using the provided writer.

    Parameters
    ----------
    queue_writer: QueueWriter
        The queue writer responsible for writing the escalation to disk.
    escalation_info: EscalationInfo
        The escalation payload that should be written.
    detector_id: str
        The identifier of the detector that produced the escalation.
    context: dict[str, Any] | None
        Optional additional context to attach to the log record when handling failures.

    Returns
    -------
    bool
        ``True`` if the write succeeded, otherwise ``False``.
    """
    try:
        return queue_writer.write_escalation(escalation_info)
    except Exception as exc:  # noqa: BLE001 - we simply log and propagate failure as False.
        extra = {"detector_id": detector_id, "exception": exc}
        if context:
            extra.update(context)

        logger.info(
            f"Writing an escalation for detector {detector_id} failed with {exc.__class__.__name__}: {exc}",
            extra=extra,
        )
        return False
