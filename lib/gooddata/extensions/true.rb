# Copyright (c) 2010-2017 GoodData Corporation. All rights reserved.
# This source code is licensed under the BSD-style license found in the
# LICENSE file in the root directory of this source tree.
module TrueExtensions
  refine TrueClass do
    # +true+ is not duplicable:
    #
    #   true.duplicable? # => false
    #   true.dup         # => TypeError: can't dup TrueClass
    def duplicable?
      false
    end

    def to_b
      true
    end

    def to_i
      1
    end
  end
end
