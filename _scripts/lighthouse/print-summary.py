#!/usr/bin/env python3

import sys
import json
import re

columns = [ ('performance', 'perf'),
            ('accessibility', 'a11y'),
            ('best-practices', 'best'),
            ('seo', 'seo') ]

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
        entry['stripped'] = re.sub('^.*/(?=.)', '', entry['url'])
        rep.append(entry)
        maxlen = max(maxlen, len(entry['stripped']))

width = 8

# print the header
urlfmt = '{:' + str(maxlen) + '}'
print(urlfmt.format('url'), end='')
for _, name in columns:
    print('{:>{width}}'.format(name, width=width), end='')
print()


# print the data
for entry in rep:
    print(urlfmt.format(entry['stripped'], width=width), end='')
    summary = entry['summary']
    for col, _ in columns:
        v = summary[col]
        if v is not None:
            print('{:{width}.0f}'.format(v * 100, width=width), end='')
        else:
            # sometimes the score is missing, indicating a failure
            # in the underlying lighthouse testing module
            print('{:>{width}}'.format('error', width=width), end='')

    print()

