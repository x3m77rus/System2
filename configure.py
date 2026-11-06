import os
from ambuild2 import run

parser = run.BuildParser(sourcePath=os.path.dirname(os.path.abspath(__file__)), api='2.2')
parser.options.add_argument('--sm-path', required=True, help='SourceMod 1.13 source tree')
parser.options.add_argument('--deps-path', default='/opt/system2-deps', help='Static Linux x86 dependencies')
parser.options.add_argument('--enable-debug', action='store_true')
parser.options.add_argument('--enable-optimize', action='store_true')
parser.Configure()
