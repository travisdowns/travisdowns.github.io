#!/usr/bin/env python3

import sys
import json
import re
from os import getenv

if getenv('DEBUG') == '1':
    d = lambda *a: print(file=sys.stderr, *a)
else:
    d = lambda *a: None

# prints a summary of the lighthouse results based on a manifest file and
# optionally a links file with links to uploaded results

columns = [ ('performance', 'perf'),
            ('accessibility', 'a11y'),
            ('best-practices', 'best'),
            ('seo', 'seo')
          ]

with open(sys.argv[1]) as f:
    manifest = f.read()

if len(sys.argv) > 2:
    with open(sys.argv[2]) as f:
        linkstr = f.read()
else:
    linkstr = '{}'

parsed = json.loads(manifest)
d('manifest:\n', json.dumps(parsed, indent=2))

links = json.loads(linkstr)
d('links:\n' + json.dumps(links, indent=2))

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
print('  link')

pattern = re.compile('^https://storage\\.googleapis\\.com/lighthouse-infrastructure\\.appspot\\.com/reports/(.*)\\.report\\.html$')

def make_link(url):
    if not url:
        return 'missing'
    m = pattern.match(url)
    if not m:
        return 'unexpected link format' + url
    return 'http://sh.9x.ee#l' + m.group(1)

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
    link = links.get(entry['url'])
    print('  ', make_link(link), sep='')

