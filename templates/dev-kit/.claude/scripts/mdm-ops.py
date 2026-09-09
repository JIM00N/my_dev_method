#!/usr/bin/env python3
"""Shared CLI entry point for project operations."""
import importlib.util
from pathlib import Path
import sys
from mdm_operations import main

spec = importlib.util.spec_from_file_location('mdm_contract', Path(__file__).with_name('mdm-contract.py'))
engine = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = engine
spec.loader.exec_module(engine)
if __name__ == '__main__':
    sys.exit(main(engine))
