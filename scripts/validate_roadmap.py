#!/usr/bin/env python3
"""Validate ROADMAP.md YAML frontmatter.

Catches issues that standard YAML parsers silently ignore:
- Duplicate top-level keys (e.g., two 'completed:' blocks)
- Missing required keys
- Completed items missing required fields for website display
- Planned items missing required fields

Run locally:  python3 scripts/validate_roadmap.py
Run in CI:    automatically via .github/workflows/validate-roadmap.yml
"""

import re
import sys
from pathlib import Path

# PyYAML is available in GitHub Actions (ubuntu-latest) and most Python installs
import yaml


def extract_frontmatter(text: str) -> str:
    """Extract YAML frontmatter between first two --- delimiters."""
    parts = text.split("---", 2)
    if len(parts) < 3:
        print("ERROR: Could not find YAML frontmatter (need two --- delimiters)")
        sys.exit(1)
    return parts[1]


def check_duplicate_keys(frontmatter: str) -> list[str]:
    """Check for duplicate top-level YAML keys (zero-indent, no leading spaces)."""
    errors = []
    seen = {}
    for i, line in enumerate(frontmatter.splitlines(), 1):
        # Match top-level keys: starts at column 0, word characters, then colon
        match = re.match(r"^([a-zA-Z]\w*):", line)
        if match:
            key = match.group(1)
            if key in seen:
                errors.append(
                    f"Duplicate top-level key '{key}' on lines {seen[key]} and {i}"
                )
            else:
                seen[key] = i
    return errors


def validate_structure(data: dict) -> list[str]:
    """Validate the parsed YAML has the expected structure."""
    errors = []

    # Required top-level keys
    required_keys = ["currentVersion", "planned", "completed"]
    for key in required_keys:
        if key not in data:
            errors.append(f"Missing required top-level key: '{key}'")

    if not isinstance(data.get("currentVersion"), str):
        errors.append("'currentVersion' must be a string")

    # Validate planned items
    for i, item in enumerate(data.get("planned") or []):
        prefix = f"planned[{i}] ({item.get('id', '?')})"
        for field in ["id", "title", "tags", "targetVersion"]:
            if field not in item:
                errors.append(f"{prefix}: missing required field '{field}'")

    # Validate completed items
    for i, item in enumerate(data.get("completed") or []):
        prefix = f"completed[{i}] ({item.get('id', '?')})"
        for field in ["id", "title", "tags", "version"]:
            if field not in item:
                errors.append(f"{prefix}: missing required field '{field}'")

    # Validate inProgress items (if any)
    for i, item in enumerate(data.get("inProgress") or []):
        prefix = f"inProgress[{i}] ({item.get('id', '?')})"
        for field in ["id", "title", "tags"]:
            if field not in item:
                errors.append(f"{prefix}: missing required field '{field}'")

    return errors


def check_id_uniqueness(data: dict) -> list[str]:
    """Check that all item IDs are unique across all sections."""
    errors = []
    seen_ids = {}
    for section in ["inProgress", "planned", "completed"]:
        for item in data.get(section) or []:
            item_id = item.get("id")
            if not item_id:
                continue
            if item_id in seen_ids:
                errors.append(
                    f"Duplicate item ID '{item_id}' in '{section}' "
                    f"(already in '{seen_ids[item_id]}')"
                )
            else:
                seen_ids[item_id] = section
    return errors


def main():
    roadmap_path = Path(__file__).parent.parent / "ROADMAP.md"
    if not roadmap_path.exists():
        print(f"ERROR: {roadmap_path} not found")
        sys.exit(1)

    text = roadmap_path.read_text()
    frontmatter = extract_frontmatter(text)

    all_errors = []

    # Check for duplicate keys (before parsing, since parsers silently drop them)
    all_errors.extend(check_duplicate_keys(frontmatter))

    # Parse and validate structure
    try:
        data = yaml.safe_load(frontmatter)
    except yaml.YAMLError as e:
        print(f"ERROR: Invalid YAML: {e}")
        sys.exit(1)

    if not isinstance(data, dict):
        print("ERROR: Frontmatter did not parse as a YAML mapping")
        sys.exit(1)

    all_errors.extend(validate_structure(data))
    all_errors.extend(check_id_uniqueness(data))

    # Report
    if all_errors:
        print(f"ROADMAP.md validation failed with {len(all_errors)} error(s):\n")
        for error in all_errors:
            print(f"  - {error}")
        sys.exit(1)

    # Summary
    n_progress = len(data.get("inProgress") or [])
    n_planned = len(data.get("planned") or [])
    n_completed = len(data.get("completed") or [])
    print(
        f"ROADMAP.md valid: v{data['currentVersion']} — "
        f"{n_progress} in progress, {n_planned} planned, {n_completed} completed"
    )


if __name__ == "__main__":
    main()
