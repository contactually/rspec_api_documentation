require 'rspec_api_documentation/writers/formatter'
require 'yaml'

module RspecApiDocumentation
  module Writers
    class SwaggerWriter < Writer
      FILENAME = 'swagger'

      delegate :docs_dir, :swagger_config_path, to: :configuration

      def write
        File.open(docs_dir.join("#{FILENAME}.json"), 'w+') do |f|
          f.write Formatter.to_json(SwaggerIndex.new(index, configuration, load_config))
        end
      end

      def load_config
        YAML.load_file(swagger_config_path) if File.exist?(swagger_config_path)
      end
    end

    class SwaggerIndex
      attr_reader :index, :configuration, :init_config

      def initialize(index, configuration, init_config)
        @index = index
        @configuration = configuration
        @init_config = init_config
      end

      def as_json
        swagger = init_config ? Swaggers::Root.new(init_config) : Swaggers::Root.new
        swagger.tags = extract_tags
        swagger.paths = extract_paths
        swagger.securityDefinitions = extract_security_definitions
        swagger.as_json
      end

      private

      def examples
        index.examples.map { |example| SwaggerExample.new(example) }
      end

      def extract_security_definitions
        security_definitions = Swaggers::SecurityDefinitions.new

        arr = examples.map do |example|
          example.respond_to?(:authentications) ? example.authentications : nil
        end.compact

        arr.each do |securities|
          securities.each do |security, opts|
            schema = Swaggers::SecuritySchema.new(
              name: opts[:name],
              description: opts[:description],
              type: opts[:type],
              in: opts[:in]
            )
            security_definitions.add_setting security, :value => schema
          end
        end
        security_definitions unless arr.empty?
      end

      def extract_tags
        tags = {}
        examples.each do |example|
          tags[example.resource_name] = tags[example.resource_name] || example.resource_explanation
        end
        tags.map { |(k, v)| Swaggers::Tag.new(name: k, description: v) }
      end

      def extract_paths
        paths = Swaggers::Paths.new
        examples.each do |example|
          paths.add_setting example.route, :value => Swaggers::Path.new

          operation = Swaggers::Operation.new(
            tags: [example.resource_name],
            summary: example.description,
            parameters: extract_parameters(example),
            responses: extract_responses(example),
            consumes: example.requests.map { |request| request[:request_content_type] }.compact.map { |q| q[/[^;]+/] },
            produces: example.requests.map { |request| request[:response_content_type] }.compact.map { |q| q[/[^;]+/] },
            security: example.respond_to?(:authentications) ? example.authentications.map { |(k, _)| {k => []} } : []
          )

          paths.setting(example.route).assign_setting(example.http_method, operation)
        end
        paths
      end

      def extract_responses(example)
        return [] unless example.respond_to?(:requests)
        responses = Swaggers::Responses.new
        schema = extract_schema(example.respond_to?(:response_fields) ? example.response_fields : [])
        example.requests.each do |request|
          response = Swaggers::Response.new(
            description: request[:response_status_text],
            schema: schema
          )

          if request[:response_headers]
            response.headers ||= Swaggers::Headers.new
            request[:response_headers].each do |header, value|
              response.headers.add_setting header, :value => Swaggers::Header.new('x-example-value' => value)
            end
          end

          if /\A(?<response_content_type>[^;]+)/ =~ request[:response_content_type]
            response.examples ||= Swaggers::Example.new
            response_body = request[:response_body] ? JSON.parse(request[:response_body]) : request[:response_body]
            response.examples.add_setting response_content_type, :value => response_body
          end
          responses.add_setting "#{request[:response_status]}", :value => response
        end
        responses
      end

      def extract_schema(fields)
        schema = {type: 'object', properties: {}}

        fields.each do |field|
          current = schema
          if field[:scope]
            [*field[:scope]].each do |scope|
              current[:properties][scope] ||= {type: 'object', properties: {}}
              current = current[:properties][scope]
            end
          end
          current[:properties][field[:name]] = {type: field[:type]}
          current[:required] ||= [] << field[:name] if field[:required]
        end

        Swaggers::Schema.new(schema)
      end

      def extract_parameters(example)
        return [] unless example.respond_to?(:parameters)

        others = example.parameters.select { |parameter| !parameter[:skip] && !(parameter[:in].to_s == 'body') }.map do |parameter|
          Swaggers::Parameter.new(
            name: parameter[:name],
            in: parameter[:in],
            description: parameter[:description],
            required: parameter[:required] ? parameter[:required] : false,
            type: parameter[:type]
          )
        end

        fields = example.parameters.select { |parameter| !parameter[:skip] && parameter[:in].to_s == 'body' }

        others.unshift(
          Swaggers::Parameter.new(
            name: 'body',
            in: 'body',
            description: '',
            schema: extract_schema(fields)
          )
        ) unless fields.empty?

        others
      end
    end

    class SwaggerExample
      def initialize(example)
        @example = example
      end

      def method_missing(method, *args, &block)
        @example.send(method, *args, &block)
      end

      def respond_to?(method, include_private = false)
        super || @example.respond_to?(method, include_private)
      end

      def http_method
        metadata[:method]
      end

      def requests
        super.select { |request| request[:request_method].to_s.downcase == http_method.to_s.downcase }
      end

      def route
        super.gsub(/:(?<parameter>[^\/]+)/, '{\k<parameter>}')
      end
    end
  end
end