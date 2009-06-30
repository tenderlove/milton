require 'rubygems'
require 'mechanize'
require 'logger'
require 'cgi'
require 'date'
require 'optparse'
require 'optparse/date'
require 'yaml'

##
# Milton fills out timesheets for the ADP ezLaborManager.

class Milton

  VERSION = '1.0.0'

  def self.load_config config_file
    unless File.exist? config_file then
      open config_file, 'wb' do |f|
        f.write YAML.dump({
          'client_name' => 'Your client name',
          'username'    => 'Your username',
          'password'    => 'Your password',
        })
      end

      raise "Please fill out #{config_file}. We've created a template there for you to edit."
    end

    YAML.load_file config_file
  end

  def self.parse_args argv
    options = {
      'date' => nil,
      'view' => false
    }

    opts = OptionParser.new do |opt|
      opt.program_name = File.basename $0
      opt.version = Milton::VERSION
      opt.release = nil
      opt.banner = <<-EOF
Usage: #{opt.program_name} [options]

Milton fills out your ADP timesheet for you.  By default it fills it out for
the current week with eight hours/day.
      EOF

      opt.separator nil

      opt.on('--view',
             'Only view your current timesheet') do |value|
        options['view'] = value
      end

      opt.on('--date=DATE', Date,
             'Select week by day') do |value|
        options['date'] = value
      end

      opt.on('--month [DATE]', Date, 'Select month by day') do |value|
        options['view'] = true  # For your safety, you can only view months
        options['month'] = value || Date.today
      end

      opt.on('--fuck-the-man',
             'Do not include lunch in your timesheet') do |value|
        options['rows_per_day'] = 1
      end
    end

    opts.parse! argv

    options
  end

  def self.run argv = ARGV
    config_file = File.join Gem.user_home, '.milton'

    options = parse_args argv

    config = load_config config_file

    options.merge! config

    new.run options
  end

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
    }.submit
    change_password if @page.body =~ /Old Password/
    @page = @page.link_with(:text => 'Time Sheet').click
  end

  ##
  # Selects the current week's timesheet

  def select_current_week
    select_week_of Date.today
  end

  def rows_per_day= rows = 2
    @rows_per_day = rows
    @page = @page.form('Form1') { |form|
      form['__EVENTTARGET'] = 'SETNOOFROWS'
      form['__EVENTARGUMENT'] = rows.to_s
      form['__PageDirty']   = 'False'
    }.submit
  end

  def run config
    self.client_name = config['client_name']
    login config['username'], config['password']

    date  = config['date']
    month = config['month']

    if date then
      select_week_of date
    elsif month
      select_month_of month
    else
      select_current_week
    end

    unless config['view'] then
      self.rows_per_day = config['rows_per_day'] || 2
      fill_timesheet
    end

    extract_timesheet
  end

  ##
  # Fills in timesheet rows that don't already have data

  def fill_timesheet
    rows = []
    last_date = nil
    filled_in = false

    parse_timesheet.each do |data|
      department  = data[6]
      employee_id = data[7]
      date        = Date.parse(CGI.unescape(data[1])).strftime('%m/%d/%Y')

      # skip days with data already filled (like holidays)
      if data[0].to_i > 0 or (filled_in and date == last_date) then
        filled_in = true
        last_date = date
        next
      end

      filled_in = false

      start, finish = starting_and_ending_timestamp date, last_date

      rows << [
        '0', '', 'False', 'True', 'False', 'False', 'False',
        "#{date} 12:00:00 AM",
        start, '',
        finish,
        '8', '',
        department,
        employee_id,
        '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '',
        '', '', '', 'EDIT', '', '', '', '', '2', '', '0', 'False'
      ]

      # This reset is for the timestamp calculations.
      last_date = date
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

    date      = nil
    last_date = nil

    timesheet.each do |row|
      date = row[2]

      if row[0] == '0' and date == last_date then
        # do nothing
      elsif row[0] == '0' then
        puts "#{row[2]} no time entered"
      elsif date == last_date then
        puts "           %s to %s for %3s hours %s" % row.values_at(3, 4, 5, 8)
      else
        puts "%s %s to %s for %3s hours %s" % row.values_at(2, 3, 4, 5, 8)
      end

      last_date = date
    end
  end

  ##
  # Selects the timesheet for the week containing +date+

  def select_week_of date
    monday = date - date.wday + 1
    friday = monday + 4
    select_range(monday, friday)
  end

  def select_month_of date
    first = date - date.mday + 1
    last  = Date.new(first.year, first.month, -1)
    select_range(first, last)
  end

  private

  def change_password
    puts "Your password needs to be updated.  :-("
    puts "\t#{@page.uri}"
    exit
  end

  def select_range start, finish
    @page = @page.form('Form1') { |form|
      form['__EVENTTARGET'] = 'ctrlDtRangeSelector'
      form['ctrlDtRangeSelector:SelectionItem'] = '3' # Set to this week
      form['ctrlDtRangeSelector:BeginDate']     = start.strftime('%m/%d/%Y')
      form['ctrlDtRangeSelector:EndDate']       = finish.strftime('%m/%d/%Y')
      form['__PageDirty']   = 'False'
    }.submit
  end

  ##
  # Returns an array of arrays containing: row id, day start time, date, start
  # time, end time, hours, department, employee id and earnings code.  All
  # values are strings.

  def parse_timesheet
    @page.body.scan(/TCMS.oTD.push\((\[.*\])\)/).map do |match|
      row = match[0].gsub(/"/, '').split(',')
      row.map { |x|
        CGI.unescape(x.strip).delete('[]')
      }.values_at(0, 7, 8, 9, 11, 12, 14, 15, 32)
    end
  end

  ##
  # Returns the starting and ending EZLabor-style timestamps for the
  # current date row in the timesheet.
  def starting_and_ending_timestamp(date, last_date)
    if @rows_per_day == 2
      if last_date == date
        start_timestamp = "#{date} 08:30 AM"
        end_timestamp = '12:00 PM'
      else
        start_timestamp = "#{date} 12:30 PM"
        end_timestamp = '05:00 PM'
      end
    else
      start_timestamp = "#{date} 08:30 AM"
      end_timestamp = '04:30 PM'
    end
    return start_timestamp, end_timestamp
  end
end

