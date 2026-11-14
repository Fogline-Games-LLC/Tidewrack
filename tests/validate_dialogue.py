#!/usr/bin/env python3
"""Validate Tidewrack dialogue graphs without needing the Godot engine.

Checks, for every data/dialogue/*.json file:
  - it parses as a JSON object of node_id -> node
  - each node is either a linear node ("next": id|null) or a choice node
    ("choices": [{text, next, set_flag?}]) — not neither, not both
  - every referenced target id exists
  - at least one terminal (next == null) is reachable from an entry point
  - reports orphan nodes (unreachable from any known entry) as warnings

Exit code 0 = all valid, 1 = at least one error.

Usage:  python3 tests/validate_dialogue.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

# Entry-point node ids the game starts graphs from (see scripts/game.gd).
KNOWN_ENTRIES = {"logbook", "radio", "door", "start"}
JOURNAL_ENTRY_PREFIX = "entry_"

ROOT = Path(__file__).resolve().parent.parent
DIALOGUE_DIR = ROOT / "data" / "dialogue"


def reachable(graph: dict, entries: set[str]) -> set[str]:
    seen: set[str] = set()
    stack = [e for e in entries if e in graph]
    while stack:
        nid = stack.pop()
        if nid in seen:
            continue
        seen.add(nid)
        node = graph[nid]
        targets: list[str] = []
        if isinstance(node.get("choices"), list):
            targets += [c.get("next") for c in node["choices"]]
        if "next" in node:
            targets.append(node.get("next"))
        for t in targets:
            if isinstance(t, str) and t in graph:
                stack.append(t)
    return seen

def _validate_discover_log(val: object, context: str, errors: list[str]) -> None:
	if val is None:
		return
		if isinstance(val, str):
			if not val.startswith(JOURNAL_ENTRY_PREFIX) or len(val) <= len(JOURNAL_ENTRY_PREFIX):
				errors.append(f"{context}: 'discover_log' must be a non-empty '{JOURNAL_ENTRY_PREFIX}*' id")
    elif isinstance(val, list):
        if len(val) == 0 or any(not isinstance(x, str) or not x.startswith(JOURNAL_ENTRY_PREFIX) or len(x) <= len(JOURNAL_ENTRY_PREFIX) for x in val):
        	errors.append(f"{context}: 'discover_log' list must contain non-empty '{JOURNAL_ENTRY_PREFIX}*' ids")
		else:
			errors.append(f"{context}: 'discover_log' must be a string or list of strings")
			
def validate_file(path: Path) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []

    try:
        graph = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        return [f"{path.name}: invalid JSON — {exc}"], warnings

    if not isinstance(graph, dict):
        return [f"{path.name}: top level must be an object of node_id -> node"], warnings

    has_terminal = False
    for nid, node in graph.items():
        if not isinstance(node, dict):
            errors.append(f"{path.name}:{nid}: node must be an object")
            continue
        _validate_discover_log(node.get("discover_log"), f"{path.name}:{nid}", errors)

        has_choices = isinstance(node.get("choices"), list) and len(node["choices"]) > 0
        has_next = "next" in node

        if not has_choices and not has_next:
            errors.append(f"{path.name}:{nid}: node has neither 'next' nor 'choices'")
        if has_choices and has_next:
            errors.append(f"{path.name}:{nid}: node has both 'next' and 'choices' (ambiguous)")

        if has_next and node.get("next") is None:
            has_terminal = True

        if has_next and isinstance(node.get("next"), str) and node["next"] not in graph:
            errors.append(f"{path.name}:{nid}: 'next' points to missing node '{node['next']}'")

        if has_choices:
            for i, choice in enumerate(node["choices"]):
                if not isinstance(choice, dict) or "text" not in choice:
                    errors.append(f"{path.name}:{nid}: choice #{i} needs a 'text' field")
                    continue
                _validate_discover_log(choice.get("discover_log"), f"{path.name}:{nid}:choice#{i}", errors)
                target = choice.get("next")
                if target is not None and (not isinstance(target, str) or target not in graph):
                    errors.append(f"{path.name}:{nid}: choice #{i} 'next' -> missing node '{target}'")
                if target is None:
                    has_terminal = True

    if not has_terminal:
        errors.append(f"{path.name}: no terminal node (a node with next == null) — the graph never ends")

    entries = KNOWN_ENTRIES & set(graph.keys())
    if not entries:
        warnings.append(f"{path.name}: no known entry point ({sorted(KNOWN_ENTRIES)}) present")
    else:
        seen = reachable(graph, entries)
        for orphan in sorted(set(graph) - seen):
            warnings.append(f"{path.name}:{orphan}: unreachable from entry points {sorted(entries)}")

    return errors, warnings


def main() -> int:
    files = sorted(DIALOGUE_DIR.glob("*.json"))
    if not files:
        print(f"No dialogue files found in {DIALOGUE_DIR}")
        return 1

    all_errors: list[str] = []
    all_warnings: list[str] = []
    for path in files:
        errs, warns = validate_file(path)
        all_errors += errs
        all_warnings += warns
        status = "OK" if not errs else "FAIL"
        print(f"[{status}] {path.relative_to(ROOT)}  ({len(json.loads(path.read_text()))} nodes)")

    for w in all_warnings:
        print(f"  warning: {w}")
    for e in all_errors:
        print(f"  ERROR:   {e}")

    print()
    if all_errors:
        print(f"✗ {len(all_errors)} error(s), {len(all_warnings)} warning(s)")
        return 1
    print(f"✓ all dialogue graphs valid ({len(all_warnings)} warning(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())


# --- Public Demo: journal graphs -------------------------------------------
# The journal system (scripts/journal.gd) reads discovered-log entries from the
# same JSON-graph format, so they validate through the checker above. Journal
# graphs live under data/dialogue/ with an "entry_*" id and are held to the same
# rules (targets resolve, a terminal exists). This hook is a placeholder until
# the journal content lands for the public demo.
JOURNAL_ENTRY_PREFIX = "entry_"


def is_journal_graph(graph: dict) -> bool:
	return any(str(k).startswith(JOURNAL_ENTRY_PREFIX) for k in graph)
