= milton

* http://seattlerb.rubyforge.org/milton

== DESCRIPTION:

Milton fills out your ADP ezLaborManager timesheet

== FEATURES/PROBLEMS:

* Fills out timesheets for arbitrary weeks
* Does not account for time off

== SYNOPSIS:

To fill out the current week:

  milton

To view your timesheet for the current week:

  milton --view

To fill out a timesheet for an arbitrary week:

  milton --date=02/25/2009

To view a timesheet for an arbitrary week:

  milton --view --date=02/25/2009

== REQUIREMENTS:

* ADP ezLaborManager client name, username and password

== INSTALL:

* sudo gem install milton

== LICENSE:

(The MIT License)

Copyright (c) 2009 Aaron Patterson, Eric Hodel

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
