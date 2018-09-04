#!/usr/bin/env python
from setuptools import setup

setup (name   = 'cdo',
  version     = '1.3.7',
  author      = "Ralf Mueller",
  author_email= "stark.dreamdetective@gmail.com",
  license     = "GPLv2",
  description = """python bindings to CDO""",
  py_modules  = ["cdo"],
  url         = "https://code.mpimet.mpg.de/projects/cdo/wiki/Cdo%7Brbpy%7D",
  classifiers = [
        "Development Status :: 4 - Beta",
        "Topic :: Utilities",
        "Operating System :: POSIX",
        "Programming Language :: Python",
    ],
  install_requires=['six'],
  )
