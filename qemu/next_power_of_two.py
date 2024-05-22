#!/usr/bin/env python3

import math
import argparse

parser = argparse.ArgumentParser(description="Calculate the next power of two for a given image size.")
parser.add_argument('size', metavar='size', type=int, help='the size of the image')
args = parser.parse_args()
print(2**(math.ceil(math.log(args.size, 2))))
