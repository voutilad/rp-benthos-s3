#!/usr/bin/env python3
## Build an AMS Lambda compatible "environment variables" config in JSON syntax.

import os
import json

d = dict(filter(
    lambda t: t[0].startswith("RP_CONNECT_") or t[0].startswith("BENTHOS_"),
    os.environ.items()
))

print(json.dumps({ "Variables": d }))
