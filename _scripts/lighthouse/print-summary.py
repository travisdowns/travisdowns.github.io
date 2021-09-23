#!/usr/bin/env python3

import sys
import json
import re

columns = [ "performance", 
            "accessibility", 
            "best-practices",
            "seo" ]

if len(sys.argv) > 1:
    with open(sys.argv[1]) as f:
        input = f.read()
else:
    input = sys.stdin.read()

parsed = json.loads(input)

rep = []
maxlen = 0
for entry in parsed:
    if (entry['isRepresentativeRun']):
        entry['stripped'] = re.sub('^http://localhost:[0-9]*', '', entry['url'])
        rep.append(entry)
        maxlen = max(maxlen, len(entry['stripped']))

# print the header
urlfmt = '{:' + str(maxlen) + '}'
print(urlfmt.format('url'), end='')
for c in columns:
    print('{:>16}'.format(c), end='')
print()

# print the data
for entry in rep:
    print(urlfmt.format(entry['stripped']), end='')
    summary = entry['summary']
    for c in columns:
        v = summary[c]
        if v is not None:
            print('{:16.0f}'.format(v * 100), end='')
        else:
            # sometimes the score is missing, indicating a failure
            # in the underlying lighthouse testing module
            print('{:16}'.format('error'), end='')

    print()

