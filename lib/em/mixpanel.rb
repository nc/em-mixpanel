require 'base64'
require 'json'
require 'em/mixpanel/version'
require 'em-http'

module EM
  class Mixpanel
    TRACK_URI = 'http://api.mixpanel.com/track'
    #from https://mixpanel.com/docs/people-analytics/special-properties
    PERSON_PROPERTIES = %w{email created first_name last_name name last_login username country_code region city}
    #from https://mixpanel.com/docs/people-analytics/people-http-specification-insert-data
    PERSON_REQUEST_PROPERTIES = %w{token distinct_id ip ignore_time}
    PERSON_URI = 'http://api.mixpanel.com/engage/'
    
    attr_reader :token, :default_properties
    
    def initialize(token, default_properties={})
      @token, @default_properties = token, default_properties
    end
    
    def track(event, properties={})
      data = self.class.encode_data(event, {
        token: token,
        time: Time.now.to_i
      }.merge(default_properties).merge(properties))
      
      EM::HttpRequest.new(TRACK_URI.to_s).post(
        body: {data: data},
        query: {ip: 0}
      )
    end

    def increment(distinct_id, properties={}, options={})
      engage :add, distinct_id, properties, options
    end

    def set(distinct_id, properties={}, options={})
      engage :set, distinct_id, properties, options
    end

    def request(url)
      http = EM::HttpRequest.new(url).post()
      http.errback { p 'Uh oh' }
      http.callback {
        p http.response_header.status
        p http.response_header
        p http.response
      }
    end

    def engage(action, request_properties_or_distinct_id, properties, options)
      default = {:url => PERSON_URI}
      options = default.merge(options)

      request_properties = person_request_properties(request_properties_or_distinct_id)

      if action == :unset
        data = build_person_unset request_properties, properties
      else
        data = build_person action, request_properties, properties
      end

      url = "#{options[:url]}?data=#{encoded_data(data)}"
      request(url)
    end

    def properties_hash(properties, special_properties)
      properties.inject({}) do |props, (key, value)|
        key = "$#{key}" if special_properties.include?(key.to_s)
        props[key.to_sym] = value
        props
      end
    end

    def encoded_data(parameters)
      Base64.encode64(JSON.generate(parameters)).gsub(/\n/,'')
    end

    def person_request_properties(request_properties_or_distinct_id)
      default = {:token => @token, :ip => 0}
      if request_properties_or_distinct_id.respond_to? :to_hash
        default.merge(request_properties_or_distinct_id)
      else
        default.merge({ :distinct_id => request_properties_or_distinct_id })
      end
    end

    def build_person(action, request_properties, person_properties)
      properties_hash(request_properties, PERSON_REQUEST_PROPERTIES).merge({ "$#{action}".to_sym => properties_hash(person_properties, PERSON_PROPERTIES) })
    end

    def build_person_unset(request_properties, property)
      properties_hash(request_properties, PERSON_REQUEST_PROPERTIES).merge({ "$unset".to_sym => [property] })
    end
    
  private
    
    def self.encode_data(event, properties)
      params = {event: event, properties: properties}
      Base64.strict_encode64 params.to_json
    end
    
  end
end
