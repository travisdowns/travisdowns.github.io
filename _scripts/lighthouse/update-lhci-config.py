#!/usr/bin/env python3

import pathlib
import sys
from os import path

basedir = sys.argv[1]
print('basedir: ', basedir)

infile = path.join(path.dirname(__file__), 'config-template.json')
print('infile: ', infile)

outfile = sys.argv[2] if len(sys.argv) >= 3 else 'lighthouserc.json'
print('outfile: ', outfile)

posts = [path.relpath(p, basedir) for p in pathlib.Path(basedir).glob('blog/**/*.html')]
other = ['index.html', 'about']

prefix = 'http://localhost/'
urls = ['"' + prefix + u + '"' for u in posts + other]
jsonStr = ',\n'.join(urls)

with open(infile) as f:
    template=f.read()

outStr = template.replace('"URL_PLACEHOLDER"', jsonStr)

print('Updated lighthouse config:\n=================\n', outStr, '\n=================\n')

with open(outfile, "w") as f:
    f.write(outStr)
