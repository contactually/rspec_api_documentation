require 'rspec_api_documentation/dsl/endpoint/set_param'

module RspecApiDocumentation
  module DSL
    module Endpoint
      class Params
        attr_reader :example_group, :example

        def initialize(example_group, example, extra_params)
          @example_group = example_group
          @example = example
          @extra_params = extra_params
        end

        def call
          parameters = example.metadata.fetch(:parameters, {}).inject({}) do |hash, param|
            SetParam.new(self, hash, param).call
          end
          parameters.deep_merge!(extra_params)
          parameters
        end

        def extended
          example.metadata.fetch(:parameters, {}).map do |param|
            p = Marshal.load(Marshal.dump(param))
            p[:value] = SetParam.new(self, nil, p).value
            unless p[:value]
              cur = extra_params
              [*p[:scope]].each { |scope| cur = cur && (cur[scope.to_sym] || cur[scope.to_s]) }

              return if cur.is_a?(Array)
              
              p[:value] = cur && (cur[p[:name].to_s] || cur[p[:name].to_sym])
            end
            p
          end
        end

      private

        attr_reader :extra_params

      end
    end
  end
end
