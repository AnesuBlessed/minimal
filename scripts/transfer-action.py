#!/usr/bin/env python3
import sys
from transfer_state import submit_action
try:
    submit_action(*sys.argv[1:])
except (ValueError, OSError, TypeError) as error:
    print(error, file=sys.stderr)
    sys.exit(1)
