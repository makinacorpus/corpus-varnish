#!/usr/bin/env python
# -*- coding: utf-8 -*-
from __future__ import absolute_import
from __future__ import division
from __future__ import print_function

from distutils.version import LooseVersion

def check_varnish_version_greater_than(target="4.1"):
    ret = __salt__['cmd.run']('varnishd -V')
    firstline = ret.split("\n")[0]
    words = firstline.split()
    if len(words) <= 2:
        # unknown version
        return False
    word = words[1]
    if word.startswith("(varnish-"):
        VERSION = word[9:]
    else:
        return False
    return LooseVersion(VERSION) >= LooseVersion(target)
# vim:set et sts=4 ts=4 tw=80:
