require 'mechanize'
require 'logger'

class Milton
  VERSION = '0.0.0'

  def initialize &block
    @agent = WWW::Mechanize.new
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

  def select_current_week
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

  def rows_per_day= rows = 1
    @page = @page.form('Form1') { |form|
      form['__EVENTTARGET'] = 'SETNOOFROWS'
      form['__EVENTARGUMENT'] = rows.to_s
      form['__PageDirty']   = 'False'
    }.submit
  end

  def fill_timesheet
    rows = []
    parse_timesheet.each do |data|
      next if data[0].to_i > 0

      department  = data[6]
      employee_id = data[7]
      date        = Date.parse(CGI.unescape(data[1])).strftime('%m/%d/%Y')

      rows << ['0','','False','True','False','False','False',
      "#{date} 12:00:00 AM",
      "#{date} 08:30 AM",'',
      '04:30 PM',
      '8','',
      department,
      employee_id,
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
  end

  def extract_timesheet
    puts parse_timesheet.map { |x| x.join(', ') }.join("\n")
  end

  private
  def parse_timesheet
    @page.body.scan(/TCMS.oTD.push\((\[.*\])\)/).map do |match|
      match[0].gsub(/"/, '').split(',').map { |x|
        CGI.unescape(x.strip).delete('[]')
      }.values_at(0, 7, 8, 9, 11, 12, 14, 15)
    end
  end
end

if __FILE__ == $0
  config = YAML.load_file(File.join(ENV['HOME'], '.milton'))
  Milton.new do |client|
    client.client_name = config['client_name']
    client.login config['username'], config['password']
    client.select_current_week
    client.rows_per_day = 1
    client.fill_timesheet
    client.extract_timesheet
  end
end
