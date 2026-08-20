#!/usr/bin/env python3
"""
Prints targets from assets/targets.yaml in file order, annotated with
their current state/<target>.yaml status if one exists. The first
target NOT marked 'won' or 'human_flagged' is what the next gauntlet
run should pick up -- this script just surfaces the list; it doesn't
choose for you (SKILL.md step 1 does that by reading this output).
"""
import os
import sys
import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL_ROOT = os.path.dirname(HERE)


def load_config():
    with open(os.path.join(SKILL_ROOT, "assets", "config.yaml")) as f:
        return yaml.safe_load(f)


def load_targets():
    with open(os.path.join(SKILL_ROOT, "assets", "targets.yaml")) as f:
        return yaml.safe_load(f)["targets"]


def load_state(target_id, state_dir):
    path = os.path.join(state_dir, f"{target_id}.yaml")
    if not os.path.exists(path):
        return {"status": "not_started", "rounds": 0}
    with open(path) as f:
        return yaml.safe_load(f) or {"status": "not_started", "rounds": 0}


def main():
    cfg = load_config()
    state_dir = os.path.join(
        os.path.dirname(SKILL_ROOT), os.path.basename(SKILL_ROOT), "state"
    )
    # config.yaml's state_dir is relative to the repo root, not this skill
    # folder -- resolve it against the repo root (cwd) instead.
    state_dir = cfg["state_dir"]

    targets = load_targets()
    print(f"{'TARGET':<22} {'REPO STATUS':<14} {'GAUNTLET STATUS':<16} ROUNDS")
    next_pick = None
    for t in targets:
        state = load_state(t["id"], state_dir)
        status = state.get("status", "not_started")
        rounds = state.get("rounds", 0)
        print(f"{t['id']:<22} {t['repo_status']:<14} {status:<16} {rounds}")
        if next_pick is None and status not in ("won", "human_flagged"):
            next_pick = t["id"]

    print()
    if next_pick:
        print(f"NEXT TARGET: {next_pick}")
    else:
        print("All targets resolved (won or human_flagged). Nothing to run.")
        print("Add new targets to assets/targets.yaml to continue.")


if __name__ == "__main__":
    main()
