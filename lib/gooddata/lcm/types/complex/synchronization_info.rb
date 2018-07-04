# encoding: UTF-8

#
# Copyright (c) 2010-2017 GoodData Corporation. All rights reserved.
# This source code is licensed under the BSD-style license found in the
# LICENSE file in the root directory of this source tree.

require_relative '../base_type'

require_relative '../special/array'
require_relative 'complex'

module GoodData
  module LCM2
    module Type
      class SynchronizationInfoType < ComplexType
        CATEGORY = :complex

        PARAMS = define_type(self) do
          description 'From which project'
          param :from, instance_of(Type::StringType), required: true

          description 'To which projects'
          param :to, array_of(instance_of(Type::HashType)), required: true

          description 'Uri of the source output stage. It must be in the same domain as the target project.'
          param :ads_output_stage_uri, instance_of(Type::StringType), required: false
        end

        def check(value)
          BaseType.check_params(PARAMS, value)
        end
      end
    end
  end
end
