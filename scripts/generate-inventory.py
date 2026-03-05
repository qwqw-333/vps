#!/usr/bin/env python3
"""
Generate ansible/inventory.yml from Terraform output.

Requires: jinja2 (installed as part of ansible)

Usage:
    python3 scripts/generate-inventory.py
"""

import os
import subprocess
import sys
from pathlib import Path

from jinja2 import Environment, FileSystemLoader

REPO_ROOT = Path(__file__).resolve().parent.parent
INFRA_DIR = REPO_ROOT / "infra"
TEMPLATE_DIR = REPO_ROOT / "ansible"
TEMPLATE_FILE = "inventory.yml.j2"
INVENTORY_PATH = REPO_ROOT / "ansible" / "inventory.yml"


# Inline ANSI colors — respects NO_COLOR env var (https://no-color.org)
def _colors() -> dict:
    if os.environ.get("NO_COLOR"):
        return {"green": "", "cyan": "", "red": "", "nc": ""}
    return {
        "green": "\033[1;32m",
        "cyan": "\033[1;36m",
        "red": "\033[1;31m",
        "nc": "\033[0m",
    }


C = _colors()


def log_info(msg: str) -> None:
    print(f"{C['cyan']}[inventory]{C['nc']} {msg}")


def log_ok(msg: str) -> None:
    print(f"{C['green']}[inventory]{C['nc']} {msg}")


def log_error(msg: str) -> None:
    print(f"{C['red']}[inventory]{C['nc']} {msg}", file=sys.stderr)


def get_terraform_output(key: str) -> str:
    try:
        result = subprocess.run(
            ["terraform", f"-chdir={INFRA_DIR}", "output", "-raw", key],
            capture_output=True,
            text=True,
            check=True,
        )
        value = result.stdout.strip()
        if not value:
            raise ValueError(f"terraform output '{key}' returned empty string")
        return value
    except subprocess.CalledProcessError as e:
        log_error(f"terraform output failed: {e.stderr.strip()}")
        log_error("Hint: run 'task apply' in infra/ first")
        sys.exit(1)
    except FileNotFoundError:
        log_error("terraform not found in PATH — brew install terraform")
        sys.exit(1)


def render_template(variables: dict) -> str:
    env = Environment(loader=FileSystemLoader(str(TEMPLATE_DIR)), keep_trailing_newline=True)
    template = env.get_template(TEMPLATE_FILE)
    return template.render(**variables)


def main() -> None:
    log_info(f"Reading terraform outputs ({INFRA_DIR.name}/) ...")
    name = get_terraform_output("server_name")
    ip = get_terraform_output("server_ip")

    rendered = render_template({"server_name": name, "server_ip": ip})
    INVENTORY_PATH.write_text(rendered)

    log_ok(f"Written: {INVENTORY_PATH.relative_to(REPO_ROOT)}")
    log_ok(f"  host: {name} @ {ip}")


if __name__ == "__main__":
    main()
