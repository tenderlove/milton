require 'mechanize'
require 'logger'

class Milton
  VERSION = '1.0.0'

  def initialize &block
    @agent = WWW::Mechanize.new { |a|
      a.log = Logger.new('out.log')
    }
    @page = nil
    yield self if block_given?
  end

  def client_name= name
    page = @agent.get('http://workforceportal.elabor.com/ezLaborManagerNetRedirect/clientlogin.aspx')
    @page = page.form('ClientLoginForm') { |form|
      form.txtClientName = name
      form.hdnTimeZone = 'Pacific Standard Time'
      form['__EVENTTARGET'] = 'btnSubmit'
    }.submit
    @page = @page.form_with(:action => /ezlmportaldc2.adp.com/).submit
    @page = @page.form_with(:action => /adp\.com/).submit
  end

  def login username, password
    @page = @page.form('Login') { |form|
      form['txtUserID']     = username
      form['txtPassword']   = password
      form['__EVENTTARGET'] = 'btnLogin'
    }.submit
  end

  def timesheet_for
    @page = @page.link_with(:text => 'Time Sheet').click
    @page.body =~ /TCMS.oTD.push\((\[.*\])\)/
    data        = $1.gsub(/"/, '')
    department  = data.split(',')[14].to_i
    employee_id = data.split(',')[15].to_i
    @page.form('Form1') do |form|
      ## FIXME: Fill out this form
      # form['hdnRETURNDATA']
    end
  end
end

if __FILE__ == $0
  config = YAML.load_file(File.join(ENV['HOME'], '.milton'))
  Milton.new do |client|
    client.client_name = config['client_name']
    client.login config['username'], config['password']
    client.timesheet_for
  end
end
