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

  VERSION = '1.1.2'

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
      'date'  => nil,
      'debug' => false,
      'view'  => false,
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

      opt.on('--debug',
             'Print out URLs we visit') do |debug|
        options['debug'] = debug
      end

      opt.on('--month [DATE]', Date, 'Select month by day') do |value|
        options['view'] = true  # For your safety, you can only view months
        options['month'] = value || Date.today
      end

      opt.on('--fuck-the-man',
             'Do not include lunch in your timesheet') do |value|
        options['rows_per_day'] = 1
      end

      opt.on('--rand',
             'Randomize entries around scheduled times; time worked unchanged') do |value|
        options['randomize_time'] = value
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
    change_password password if @page.body =~ /Old Password/

    if @page.body =~ /Supervisor Services/ then
      warn "switching to employee page"
      option = @page.parser.css("select#Banner1_ddlServices").children.find { |n| n["value"] =~ /EmployeeServicesStart/ }
      @page = @agent.get option["value"]
    end

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
    @debug = config['debug']
    if @debug then
      @agent.log = Logger.new $stderr
      @agent.log.formatter = proc do |s, t, p, m| "#{m}\n" end
    end

    @randomize_time = config['randomize_time']

    unless @schedule = config['schedule']
      @schedule = ["8:30 AM", "12 PM", "12:30 PM", "5 PM"] if config['rows_per_day'] == 2
      @schedule ||= ["8:30 AM", "4:30 PM"]
    end

    self.client_name = config['client_name']
    login config['username'], config['password']

    date   = config['date']
    month  = config['month']

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
  rescue => e
    $stderr.puts @page.parser if @debug and @page
    raise
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
    @page.parser.css(".ErrorText").each do |n|
      puts "ERROR: #{n.text}"
    end

    timesheet = parse_timesheet

    department  = timesheet.first[6]
    employee_id = timesheet.first[7]
    error = timesheet.first[9]

    puts "ERROR: #{error}" if error

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

  def change_password old_password
    new_password = (0...8).map { (rand(26) + 97).chr }.join

    @page = @page.form('Form1') { |form|
      form['portPasswordReset:fldOldPassword']     = old_password
      form['portPasswordReset:fldNewPassword']     = new_password
      form['portPasswordReset:fldConfirmPassword'] = new_password
      form['__PageDirty']                          = 'False'
      form['__EVENTTARGET'] = 'portPasswordReset:btnSubmit'
    }.submit

    if @page then
      config_file = File.join Gem.user_home, '.milton'

      config = YAML.load_file config_file

      config['password'] = new_password

      open config_file, 'w' do |io|
        io.write config.to_yaml
      end

      puts 'Changed your password and updated ~/.milton'
    else
      raise 'unable to change password :('
    end
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
      }.values_at(0, 7, 8, 9, 11, 12, 14, 15, 32, 1)
    end
  end

  ##
  # Returns the starting and ending EZLabor-style timestamps for the
  # current date row in the timesheet.
  def starting_and_ending_timestamp(date, last_date)
    timestamps = schedule_for_date(date, @schedule)
    if timestamps.length > 3 && last_date != date
      start_timestamp = timestamps[2].strftime("%m/%d/%Y %I:%M %p")
      end_timestamp = timestamps[3].strftime("%I:%M %p")
    else
      start_timestamp = timestamps[0].strftime("%m/%d/%Y %I:%M %p")
      end_timestamp = timestamps[1].strftime("%I:%M %p")
    end
    return start_timestamp, end_timestamp
  end

  ##
  # Returns an EZLabor-style array of times for a given date and
  # day-schedule array.
  def schedule_for_date(date_str, schedule_arr)
    time_offset = @randomize_time ? random_time_offset : 0
    schedule_arr.map do |time_str|
      dt = DateTime.parse("#{date_str} #{time_str}")
      time = Time.mktime(dt.year, dt.month, dt.day, dt.hour, dt.min, dt.sec, 0)
      (time + time_offset)
    end
  end

  ##
  # Randomizes a time value within a given bracket and returns
  # a +/- number of seconds.
  def random_time_offset(max_minutes_offset=5)
    rand(max_minutes_offset) * (-1).power!(rand(2)) * 60
  end

end

