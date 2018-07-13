# Copyright (c) 2010-2017 GoodData Corporation. All rights reserved.
# This source code is licensed under the BSD-style license found in the
# LICENSE file in the root directory of this source tree.
module NilExtensions
  refine NilClass do
    # +nil+ is not duplicable:
    #
    #   nil.duplicable? # => false
    #   nil.dup         # => TypeError: can't dup NilClass
    def duplicable?
      false
    end

    def to_b
      false
    end
  end
end
