#!/usr/bin/env python
from setuptools import setup

setup (name   = 'cdo',
  version     = '1.0.6',
  author      = "Ralf Mueller",
  author_email= "stark.dreamdetective@gmail.com",
  license     = "GPLv2",
  description = """python bindings to CDO""",
  py_modules  = ["cdo"],
  url = "http://pypi.python.org/pypi/cdo",
  classifiers = [
        "Development Status :: 4 - Beta",
        "Topic :: Utilities",
        "Operating System :: POSIX",
        "Programming Language :: Python",
    ],
  )
