require 'net/http'
require 'openssl'
require 'json'

module Pipeline
  module Helpers
    # Helper module for handling HTTP client requests
    module HTTP
      extend self

      def get(url: nil, ssl: true, user: nil, pass: nil, headers: {})
        uri = URI(url)
        req = Net::HTTP::Get.new(uri)
        req.basic_auth user, pass if user && pass
        add_headers(request: req, headers: headers) unless headers.empty?
        http(uri, ssl).request(req)
      end

      def post(url: nil, ssl: true, user: nil, pass: nil, headers: {}, data: nil)
        uri = URI(url)
        req = Net::HTTP::Post.new(uri)
        req.basic_auth user, pass if user && pass
        add_headers(request: req, headers: headers) unless headers.empty?
        req.body = data unless data.nil?
        http(uri, ssl).request(req)
      end

      def put(url: nil, ssl: true, user: nil, pass: nil, headers: {}, data: nil)
        uri = URI(url)
        req = Net::HTTP::Put.new(uri)
        req.basic_auth user, pass if user && pass
        add_headers(request: req, headers: headers) unless headers.empty?
        req.body = data unless data.nil?
        http(uri, ssl).request(req)
      end

      private

      def http(uri, ssl = true)
        http = Net::HTTP.new(uri.hostname, uri.port)
        return http unless ssl

        http.use_ssl = true
        http
      end

      def add_headers(request:, headers:)
        headers.keys.each { |key| request[key] = headers[key] }
        request
      end
    end
  end
end
