#!/bin/sh
# This line continues for Tcl, but is a single line for 'sh' \
exec tclsh "$0" ${1+"$@"}

# Copyright (c) 2010, Blair Kitchen
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1) Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
# 2) Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
# 3) Neither the name Blair Kitchen nor the names of contributors may be used
#    to endorse or promote products derived from this software without specific
#    prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

package require Tcl 8.4
package require cmdline 1.3

array set state [list \
    data {} \
    data_file [file join $::env(HOME) .time_track time_track.txt] \
]

proc main {argc argv} {
    if {$argv < 1} {
        cmd.help {}
        exit -1
    }

    set cmd [lindex $argv 0]
    set argv [lrange $argv 1 end]

    file mkdir [file dirname $::state(data_file)]

    if {[catch {findMatchingCommand $cmd} cmd]} {
        puts stderr $cmd
        exit -1
    }

    set ::state(data) [read_data_file $::state(data_file)]
    if {[catch {$cmd $argv} msg]} {
        puts stderr $msg
        exit -1
    }
    write_data_file $::state(data_file) $::state(data)
}

proc read_data_file {filename} {
    if {![file exists $filename]} {
        return {}
    }

    set in [open $filename r]

    set result {}
    set line [gets $in]
    while {![eof $in]} {
        set line [string trim $line]
        if {$line ne {}} {
            lappend result $line
        }
        set line [gets $in]
    }
    close $in

    return $result
}

proc write_data_file {filename data} {
    set out [open $filename w]
    foreach line $data {
        puts $out $line
    }
    close $out
}

proc findMatchingCommand {cmd} {
    if {[info commands cmd.$cmd] ne {}} {
        return cmd.$cmd
    }

    # See if this is a unique prefix
    set cmd_list [info commands cmd.$cmd*]
    if {[llength $cmd_list] == 1} {
        return [lindex $cmd_list 0]
    }

    # Generate an error message.  If we have
    # some possible commands, include those in
    # the message.
    set error_msg "Unknown command '$cmd'."
    if {[llength $cmd_list] > 0} {
        set cmd_list [lsort $cmd_list]
        append error_msg "\nDid you mean:"
        foreach cmd $cmd_list {
            append error_msg "\n\t[regsub -- {cmd\.} $cmd {}]"
        }
    }

    return -code error $error_msg
}

proc format_time {time} {
    return [clock format $time -format "%D %R"]
}

proc format_duration {duration} {
    if {$duration == 0} {
        return "not long at all"
    }

    set hours [expr {$duration/60}]
    set minutes [expr {$duration - ($hours * 60)}]

    if {$hours > 1} {
        set hour_string "$hours hours"
    } elseif {$hours > 0} {
        set hour_string "$hours hour"
    } else {
        set hour_string ""
    }

    if {$minutes > 1} {
        set minute_string "$minutes minutes"
    } elseif {$minutes > 0} {
        set minute_string "$minutes minute"
    } else {
        set minute_string ""
    }

    if {$hour_string ne "" && $minute_string ne ""} {
        return "$hour_string, $minute_string"
    } elseif {$hour_string ne ""} {
        return $hour_string
    } else {
        return $minute_string
    }
}

proc line_to_components {line} {
    if {[regexp -- {^\((.*)\) (.*?)(\s+@.*)?} $line -> times message code] == 0} {
        return -code error "Malformed line '$line'"
    }

    if {[regexp -- {(.*) - (.*)} $times -> start_time end_time] == 0} {
        return -code error "Malformed times in line '$line'"
    }

    set start_time [clock scan $start_time]
    if {$end_time ne ""} {
        set end_time [clock scan $end_time]
    }

    set code [string range [string trim $code] 1 end]

    return [list start_time $start_time end_time $end_time message $message code $code]
}

proc components_to_line {components} {
    array set parts $components
    
    if {$parts(code) ne ""} {
        set message "$parts(message) @$parts(code)"
    } else {
        set message $parts(message)
    }

    set start_time [format_time $parts(start_time)]
    if {$parts(end_time) eq ""} {
        set end_time ""
    } else {
        set end_time [format_time $parts(end_time)]
    }

    return "($start_time - $end_time) $message"
}

proc exists_active_task {} {
    if {[llength $::state(data)] == 0} {
        return 0
    }

    set line [lindex $::state(data) end]
    array set parts [line_to_components $line]

    if {$parts(end_time) eq ""} {
        return 1
    }

    return 0
}

proc foreach_entry {var_name body} {
    global errorInfo errorCode

    upvar 1 $var_name components

    foreach line $::state(data) {
        set components [line_to_components $line]

        set code [catch {uplevel 1 $body} message]
        switch -- $code {
            0 { }
            1 { error $message $::errorInfo $::errorCode }
            2 { return $message }
            3 { break }
            4 { continue }
            default { return -code $code $message }
        }
    }
}

proc foreach_entry_in_range {start_time end_time var_name body} {
    global errorInfo errorCode

    upvar 1 $var_name components

    foreach_entry components {
        array set parts $components

        if {$parts(start_time) > $end_time} {
            continue
        } elseif {$parts(end_time) ne "" && $parts(end_time) < $start_time} {
            continue
        }

        set code [catch {uplevel 1 $body} message]
        switch -- $code {
            0 { }
            1 { error $message $::errorInfo $::errorCode }
            2 { return $message }
            3 { break }
            4 { continue }
            default { return -code $code $message }
        }
    }
}


set cmd.start.description "Starts a new task.  Stops the current task (if any)."
proc cmd.start {argv} {
    set options {
        {time.arg "now" "Explicitly set the starting time."}
        {code.arg "" "Specify the associated charge code."}
    }
    set usage "start \[options] <task>\n\n${::cmd.start.description}\n\noptions:"

    array set params [::cmdline::getoptions argv $options $usage]

    if {$params(time) eq "now"} {
        set params(time) [clock seconds]
    } else {
        set params(time) [clock scan $params(time)]
    }

    set parts [list start_time $params(time) end_time "" message $argv code $params(code)]

    if {[exists_active_task] != 0} {
        cmd.stop [list -time [format_time $params(time)]]
    }

    lappend ::state(data) [components_to_line $parts]
}

set cmd.stop.description "Stops the current active task."
proc cmd.stop {argv} {
    set options {
        {time.arg "now" "Explicitly set the stop time."}
    }
    set usage "stop \[options]\n\n${::cmd.stop.description}\n\noptions:"

    array set params [::cmdline::getoptions argv $options $usage]

    if {[exists_active_task] == 0} {
        return -code error "You're not currently working on anything."
    }

    set line [lindex $::state(data) end]
    array set parts [line_to_components $line]

    if {$params(time) eq "now"} {
        set params(time) [clock seconds]
    } else {
        set params(time) [clock scan $params(time)]
    }

    if {$parts(start_time) > $params(time)} {
        return -code error "Cannot stop active task.  End time '[format_time $params(time)]' is less than start time '[format_time $parts(start_time)]'"
    }
    set parts(end_time) $params(time)

    set ::state(data) [lreplace $::state(data) end end [components_to_line [array get parts]]]
}

set cmd.summary.description "Generates a summary report of the tasks for a given date."
proc cmd.summary {argv} {
    set options {
        {date.arg "today" "The date to summarize"}
    }
    set usage "summary \[options]\n\n${::cmd.summary.description}\n\noptions:"

    array set params [::cmdline::getoptions argv $options $usage]

    if {$params(date) eq "today"} {
        set filter_start_time [clock scan "today 0:00"]
    } else {
        set filter_start_time [clock scan $params(date)]
        set filter_start_time [clock scan [clock format $filter_start_time -format %D]]
    }

    set filter_end_time [expr {86400 + $filter_start_time}]

    array set summary {}

    foreach_entry_in_range $filter_start_time $filter_end_time components {
        array set parts $components

        if {$parts(end_time) eq ""} {
            set parts(end_time) [clock seconds]
        }

        if {$parts(code) eq ""} {
            set parts(code) "<NONE>"
        }

        if {![info exists summary($parts(code))]} {
            set summary($parts(code)) {}
        }

        set duration [expr {($parts(end_time) - $parts(start_time)) / 60}]
        lappend summary($parts(code)) $duration $parts(message)
    }

    set daily_total 0
    foreach code [lsort [array names summary]] {
        set subtotal 0

        # Combine tasks with identical descriptions.
        array set messages {}
        foreach {duration message} $summary($code) {
            if {[info exists messages($message)]} {
                incr messages($message) $duration
            } else {
                set messages($message) $duration
            }
        }

        puts "Charges to $code"
        foreach message [array names messages] {
            set duration $messages($message)
            puts "   $message -  [format_duration $duration]"
            incr subtotal $duration
            incr daily_total $duration
        }
        array unset messages

        puts "---"
        puts "Subtotal for $code [format_duration $subtotal]"
        puts ""
    }
    puts "For the day [format_duration $daily_total]"
}

set cmd.status.description "Lists the active task and amount of time spent."
proc cmd.status {argv} {
    set options { }
    set usage "status \[options]\n\n${::cmd.status.description}\n\noptions:"

    array set params [::cmdline::getoptions argv $options $usage]

    if {[exists_active_task] == 0} {
        return -code error "You're not currently working on anything."
    }

    set line [lindex $::state(data) end]
    array set parts [line_to_components $line]

    set duration [expr {([clock seconds] - $parts(start_time)) / 60}]

    puts "$parts(message) for [format_duration $duration]"
}

set cmd.list-codes.description "Lists all active charge codes and the last date and task for each."
proc cmd.list-codes {argv} {
    set options { }
    set usage "list-codes \[options]\n\n${::cmd.list-codes.description}\n\noptions:"

    array set params [::cmdline::getoptions argv $options $usage]

    array set summary {}

    foreach_entry components {
        array set parts $components

        set date $parts(end_time)
        if {$date eq ""} {
            set date $parts(start_time)
        }

        set code $parts(code)
        if {$code eq ""} {
            set code "<NONE>"
        }

        set date [clock format $date -format "%D"]
        set summary($code) "- $date - $parts(message)"
    }

    foreach code [lsort [array names summary]] {
        puts "$code $summary($code)"
    }
}

set cmd.help.description "Lists all available commands."
proc cmd.help {argv} {
    set options { }
    set usage "help \[options]\n\n${::cmd.help.description}\n\noptions:"

    array set params [::cmdline::getoptions argv $options $usage]

    puts "time_track.tcl 0.3"
    puts ""
    puts "Command line based time tracking software."
    puts ""
    puts "Usage: [info script] <command> ?options?"
    puts ""
    puts "Available commands:"
    puts ""
    foreach command [lsort [info commands cmd.*]] {
        set description ""
        if {[info exists ::$command.description]} {
            set description " - [set ::$command.description]"
        }
        set command [regsub -- {cmd\.} $command {}]
        puts "   $command$description"
    }
    puts ""
    puts "See '[info script] <command> -help' for more information on a specific command."
    puts ""
    puts "Source code and releases may be found at http://github.com/dongola7/Time-Track-CLI."
    puts "Report bugs at http://github.com/dongola7/Time-Track-CLI/issues."
    puts ""
    puts "Released under the BSD license (http://creativecommons.org/licenses/BSD/)."
}

main $argc $argv
