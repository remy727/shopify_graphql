module ShopifyGraphQL
  class Client
    def initialize(api_version = ShopifyAPI::Base.api_version)
      @api_version = api_version
    end

    def execute(query, variables = nil, operation_name: nil)
      response = connection.post do |req|
        req.body = {
          query: query,
          operationName: operation_name,
          variables: variables,
        }.to_json
      end
      handle_response(response)
    end

    def api_url
      [ShopifyAPI::Base.site, @api_version.construct_graphql_path].join
    end

    def request_headers
      ShopifyAPI::Base.headers
    end

    def connection
      @connection ||= Faraday.new(url: api_url, headers: request_headers) do |conn|
        conn.use Faraday::Response::RaiseError
        conn.request :json
        conn.response :json, parser_options: { object_class: OpenStruct }
      end
    end

    def handle_response(response)
      case response.status
      when 200..400
        handle_graphql_errors(response.body)
      else
        raise ConnectionError.new(response.body, "Unknown response code: #{response.status}")
      end
    end

    def handle_graphql_errors(response)
      return response if response.errors.blank?

      error = response.errors.first
      error_message = error.message
      error_code = error.extensions.code
      error_doc = error.extensions.documentation

      case error_code
      when "THROTTLED"
        raise TooManyRequests.new(response, error_message, code: error_code, doc: error_doc)
      else
        raise ConnectionError.new(response, error_message, code: error_code, doc: error_doc)
      end
    end

    def handle_user_errors(response)
      return response if response.userErrors.blank?

      error = response.userErrors.first
      error_message = error.message
      error_fields = error.field

      raise ClientError.new(response, error_message, fields: error_fields)
    end
  end

  def self.client(api_version = ShopifyAPI::Base.api_version)
    Client.new(api_version)
  end
end