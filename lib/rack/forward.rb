require 'rack/forward/version'
require 'net/http'

module Rack
  class Forward
    HTTP_METHODS = %w(GET HEAD PUT POST DELETE OPTIONS PATCH)

    def initialize(app, &block)
      self.class.send(:define_method, :uri_for, &block)
      @app = app
    end

    def call(env)
      req    = Rack::Request.new(env)
      uri    = uri_for(req)
      method = req.request_method.upcase

      return @app.call(env) unless uri && HTTP_METHODS.include?(method)

      sub_request = Net::HTTP.const_get(method.capitalize).new("#{uri.path}#{"?" if uri.query}#{uri.query}")

      if sub_request.request_body_permitted? and req.body
        sub_request.body_stream = req.body
        sub_request.content_length = req.content_length
        sub_request.content_type = req.content_type
      end
      
      sub_request['X-Identity-Service-Key'] = req.env['HTTP_X_IDENTITY_SERVICE_KEY']
      sub_request['X-Forwarded-For'] = (req.env['X-Forwarded-For'].to_s.split(/, */) + [req.env['REMOTE_ADDR']]).join(', ')
      sub_request['Accept'] = req.env['HTTP_ACCEPT']
      sub_request['Accept-Encoding'] = req.accept_encoding
      sub_request['Authorization']  = req.env['HTTP_AUTHORIZATION']
      sub_request['Cookie']  = req.env['HTTP_COOKIE']
      sub_request['Referer'] = req.referer
      
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true if uri.port == 443
      sub_response = http.start do |http|
        http.request(sub_request)
      end

      headers = {}
      sub_response.each_header do |k, v|
        if k.to_s =~ /set-cookie/i
          headers[k] = cleanup_cookie(v)
        else
          headers[k] = v unless k.to_s =~ /content-length|transfer-encoding/i
        end
      end

      [sub_response.code.to_i, headers, [sub_response.read_body]]
    end

    private

    # Removes path and expiration values from cookie.
    def cleanup_cookie(cookie_val)
      cleaned_val = cookie_val.gsub(/(path=[^,;]+[,;])|(expires=.*)/, ' ')
      cleaned_val += " path=/"
      cleaned_val.gsub!(/\s+/, ' ')

      cleaned_val
    end

  end
end
