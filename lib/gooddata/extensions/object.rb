# Copyright (c) 2010-2017 GoodData Corporation. All rights reserved.
# This source code is licensed under the BSD-style license found in the
# LICENSE file in the root directory of this source tree.
module ObjectExtensions
  refine Object do
    class << self
      def set_const(name, val)
        send(:remove_const, name) if const_defined?(name)
        send(:const_set, name, val)
      end
    end

    def duplicable?
      true
    end

    def set_const(name, val)
      send(:remove_const, name) if const_defined?(name)
      send(:const_set, name, val)
    end

    def to_b
      false
    end
  end
end
