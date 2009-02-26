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
    }.submit.link_with(:text => 'Time Sheet').click
  end

  def current_week
    today = Date.today
    monday = today - today.wday + 1
    friday = monday + 4
    @page = @page.form('Form1') { |form|
      form['__EVENTTARGET'] = 'ctrlDtRangeSelector'
      form['ctrlDtRangeSelector:SelectionItem'] = '3' # Set to this week
      form['ctrlDtRangeSelector:BeginDate']     = monday.strftime('%m/%d/%Y')
      form['ctrlDtRangeSelector:EndDate']       = friday.strftime('%m/%d/%Y')
      form['__PageDirty']   = 'False'
    }.submit
  end

  def timesheet_for
    rows = []
    @page.body.scan(/TCMS.oTD.push\((\[.*\])\)/).each do |match|
      next unless match[0] =~ /^\[0,/
      data        = match[0].gsub(/"/, '').split(',')

      department  = data[14].to_i
      employee_id = data[15].to_i
      date        = Date.parse(CGI.unescape(data[7])).strftime('%m/%d/%Y')

      rows << ['0','','False','True','False','False','False',
      "#{date} 12:00:00 AM",
      "#{date} 08:30 AM",'',
      '04:30 PM',
      '8','',
      department.to_s,
      employee_id.to_s,
      '','','','','','','','','','','','','','','','','','','','','EDIT','','','','','2','','0','False']

    end
    
    @page = @page.form('Form1') { |form|
      ## FIXME: Fill out this form
      form['hdnRETURNDATA'] = rows.map { |row|
        row.map { |value|
          CGI.escape(value)
        }.join('~~')
      }.join('~||~')

      form['__EVENTTARGET'] = 'TG:btnSubmitTop'
      form['__PageDirty']   = 'True'
    }.submit
    @page.save('bar.html')
  end
end

if __FILE__ == $0
  config = YAML.load_file(File.join(ENV['HOME'], '.milton'))
  Milton.new do |client|
    client.client_name = config['client_name']
    client.login config['username'], config['password']
    client.current_week
    client.timesheet_for
  end
end
