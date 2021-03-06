# -*- coding: utf-8 -*-
# flake8: noqa

# Copyright (c) 2006-2012 Filip Wasilewski <http://en.ig.ma/>
# See COPYING for license details.

"""
Discrete forward and inverse wavelet transform, stationary wavelet transform,
wavelet packets signal decomposition and reconstruction module.
"""

from __future__ import division, print_function, absolute_import


from ._pywt import *
from ._functions import *
from ._multilevel import *
from ._multidim import *
from ._thresholding import *
from ._wavelet_packets import *


__all__ = [s for s in dir() if not s.startswith('_')]
try:
    # In Python 2.x the name of the tempvar leaks out of the list
    # comprehension.  Delete it to not make it show up in the main namespace.
    del s
except NameError:
    pass

from pywt.version import version as __version__

from numpy.testing import Tester
test = Tester().test
