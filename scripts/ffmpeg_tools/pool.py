"""Shared encode pool."""

from concurrent.futures import ThreadPoolExecutor
from concurrent.futures import as_completed as futures_as_completed

from . import ENCODING_WORKERS

ENCODING_EXECUTOR = ThreadPoolExecutor(max_workers=ENCODING_WORKERS)


def encoding_executor():
    return ENCODING_EXECUTOR


def wait_jobs(futures, label="Job"):
    results = []
    for idx, future in enumerate(futures_as_completed(futures)):
        result = future.result()
        print(f"Finished {label} {idx: >3}: {result}")
        results.append(result)
    return results
