require 'rubygems'
require 'mechanize'
require 'logger'
require 'cgi'
require 'date'

##
# Milton fills out timesheets for the ADP ezLaborManager.

class Milton

  VERSION = '1.0.0'

  def initialize &block
    @agent = WWW::Mechanize.new
    @page = nil
    @username = nil
    yield self if block_given?
  end

  ##
  # Sets the client name +name+

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

  ##
  # Logs in +username+ with +password+

  def login username, password
    @username = username

    @page = @page.form('Login') { |form|
      form['txtUserID']     = username
      form['txtPassword']   = password
      form['__EVENTTARGET'] = 'btnLogin'
    }.submit.link_with(:text => 'Time Sheet').click
  end

  ##
  # Selects the current week's timesheet

  def select_current_week
    select_week_of Date.today
  end

  def rows_per_day= rows = 1
    @page = @page.form('Form1') { |form|
      form['__EVENTTARGET'] = 'SETNOOFROWS'
      form['__EVENTARGUMENT'] = rows.to_s
      form['__PageDirty']   = 'False'
    }.submit
  end

  ##
  # Fills in timesheet rows that don't already have data

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

  ##
  # Prints out your timesheet for the selected time frame

  def extract_timesheet
    timesheet = parse_timesheet

    department  = timesheet.first[6]
    employee_id = timesheet.first[7]

    puts "Employee #{@username} id #{employee_id}, department #{department}"

    puts "-" * 80

    timesheet.each do |row|
      if row[0] == '0' then
        puts "#{row[2]} no time entered"
      else
        puts "#{row[2]} #{row[3]} to #{row[4]} for %2d hours" % row[5].to_i
      end
    end
  end

  ##
  # Selects the timesheet for the week containing +date+

  def select_week_of(date)
    monday = date - date.wday + 1
    friday = monday + 4
    @page = @page.form('Form1') { |form|
      form['__EVENTTARGET'] = 'ctrlDtRangeSelector'
      form['ctrlDtRangeSelector:SelectionItem'] = '3' # Set to this week
      form['ctrlDtRangeSelector:BeginDate']     = monday.strftime('%m/%d/%Y')
      form['ctrlDtRangeSelector:EndDate']       = friday.strftime('%m/%d/%Y')
      form['__PageDirty']   = 'False'
    }.submit
  end

  private

  ##
  # Returns an array of arrays containing: row id, day start time, date, start
  # time, end time, hours, department, employee id.  All values are strings.

  def parse_timesheet
    @page.body.scan(/TCMS.oTD.push\((\[.*\])\)/).map do |match|
      match[0].gsub(/"/, '').split(',').map { |x|
        CGI.unescape(x.strip).delete('[]')
      }.values_at(0, 7, 8, 9, 11, 12, 14, 15)
    end
  end

end

