module EzlogsRubyAgent
  class HttpTracker
    def initialize(app)
      @app = app
    end

    def call(env)
      start_time = Time.current
      status, headers, response = @app.call(env)
      end_time = Time.current

      EzlogsRubyAgent::EventQueue.add({
        type: "http_request",
        method: env["REQUEST_METHOD"],
        path: env["PATH_INFO"],
        params: env["rack.input"].read,
        status: status,
        response_time: (end_time - start_time).to_f,
        timestamp: Time.current
      })

      [status, headers, response]
    end
  end
end
