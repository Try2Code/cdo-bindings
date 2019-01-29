#!/usr/bin/env python
from setuptools import setup

setup (name   = 'cdo',
  version     = '1.4.1rc1',
  author      = "Ralf Mueller",
  author_email= "stark.dreamdetective@gmail.com",
  license     = "GPLv2",
  description = """python bindings to CDO""",
  long_description="CDO is an analysis tool for climate/weather data. This package offers a python-style interface to CDO. Requirement is a working CDO binary.",
  long_description_content_type="text",
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
