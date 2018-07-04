# encoding: UTF-8

#
# Copyright (c) 2010-2017 GoodData Corporation. All rights reserved.
# This source code is licensed under the BSD-style license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../rest/rest'

module GoodData
  # Base class for Ruby SDK CLI Apps
  class App
    def main
      fail NotImplementedError 'Application must implement #main'
    end
  end
end
