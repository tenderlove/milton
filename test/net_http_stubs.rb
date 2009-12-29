# Base directory for our ADP documents
HTDOCS_DIR = File.join(File.dirname(__FILE__), 'htdocs')

class Net::HTTP
  alias :old_do_start :do_start

  def self.responses
    @responses ||= []
  end

  def do_start
    @started = true
  end

  alias :old_request :request

  def request(request, *data, &block)
    url = URI.parse(request.path)
    path = URI.unescape(url.path)

    path = '/index.html' if path == '/'

    res = Response.new
    request.query = WEBrick::HTTPUtils.parse_query(url.query)
    request.cookies = WEBrick::Cookie.parse(request['Cookie'])

    filename = File.join(HTDOCS_DIR,
                         "#{path.gsub(/[^\/\\.\w_\s]/, '_')}.#{request.method}"
                        )
    puts filename

    code, location, body = self.class.responses.shift

    raise "no body for test: #{request.class::METHOD} #{path.inspect}" unless
      body

    res.body = body
    res.code = code

    res["Location"] = location if location
    res['Content-Type'] ||= 'text/html'
    res['Content-Length'] ||= res.body.length.to_s

    res.cookies.each do |cookie|
      res.add_field('Set-Cookie', cookie.to_s)
    end
    yield res if block_given?
    res
  end
end

class Net::HTTPRequest
  attr_accessor :query, :body, :cookies, :user
end

class Response
  include Net::HTTPHeader

  attr_reader :code
  attr_accessor :body, :query, :cookies

  def code=(c)
    @code = c.to_s
  end

  alias :status :code
  alias :status= :code=

  def initialize
    @header = {}
    @body = ''
    @code = nil
    @query = nil
    @cookies = []
  end

  def read_body
    yield body
  end
end
