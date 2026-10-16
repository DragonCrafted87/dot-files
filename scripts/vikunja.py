#!/usr/bin/env python3
"""Small Vikunja helper: list open tasks and mark tasks done.

Reads VIKUNJA_URL and VIKUNJA_TOKEN from the environment, or from
~/.config/vikunja/grok-cli.env (KEY=value lines) when they are unset.
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ENV_FILE = Path.home() / ".config" / "vikunja" / "grok-cli.env"


def load_env():
    """Return (url, token), reading the env file for missing values."""
    values = {}
    if ENV_FILE.is_file():
        for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, _, val = line.partition("=")
                key = key.strip().removeprefix("export ").strip()
                values[key] = val.strip().strip("'\"")
    url = os.environ.get("VIKUNJA_URL") or values.get("VIKUNJA_URL")
    token = os.environ.get("VIKUNJA_TOKEN") or values.get("VIKUNJA_TOKEN")
    if not url or not token:
        sys.exit(f"Set VIKUNJA_URL and VIKUNJA_TOKEN (or fill {ENV_FILE}).")
    return url.rstrip("/"), token


def call(method, path, body=None):
    """Make one API call and return the decoded JSON."""
    url, token = load_env()
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        url + path,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as err:
        sys.exit(f"Vikunja {method} {path} failed: {err.code} {err.read().decode()}")


def project_names():
    """Map project id to title."""
    return {p["id"]: p["title"] for p in call("GET", "/projects?per_page=200")}


def cmd_list(args):
    """Print open tasks as 'id  project  title'."""
    names = project_names()
    query = {"filter": "done = false", "per_page": "200"}
    if args.search:
        query["s"] = args.search
    path = "/tasks?" + urllib.parse.urlencode(query)
    if args.project:
        pid = next(
            (i for i, n in names.items() if n.lower() == args.project.lower()), None
        )
        if pid is None:
            sys.exit(f"No project named {args.project!r}.")
        path = f"/projects/{pid}/views"
        views = call("GET", path)
        view = next(v for v in views if v.get("view_kind") in ("list", 0))
        path = f"/projects/{pid}/views/{view['id']}/tasks?" + urllib.parse.urlencode(
            query
        )
    for task in call("GET", path) or []:
        project = names.get(task.get("project_id"), "?")
        print(f"{task['id']:>5}  {project:<28}  {task['title']}")


def cmd_done(args):
    """Mark each task id done."""
    for task_id in args.ids:
        task = call("GET", f"/tasks/{task_id}")
        task["done"] = True
        call("POST", f"/tasks/{task_id}", task)
        print(f"done: {task_id}  {task['title']}")


def main():
    """Parse arguments and dispatch."""
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)
    lst = sub.add_parser("list", help="list open tasks")
    lst.add_argument("search", nargs="?", help="text to search for")
    lst.add_argument("-p", "--project", help="only this project (exact title)")
    lst.set_defaults(func=cmd_list)
    done = sub.add_parser("done", help="mark tasks done")
    done.add_argument("ids", nargs="+", type=int)
    done.set_defaults(func=cmd_done)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
