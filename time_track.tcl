#!/bin/sh
# This line continues for Tcl, but is a single line for 'sh' \
exec tclsh "$0" ${1+"$@"}

# Copyright (c) 2012, Blair Kitchen
# All rights reserved.
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.

package require Tcl 8.5
package require cmdline 1.3
package require fileutil 1.13

source [file join [file dirname [info script]] cli.tcl]

package provide TimeTrackCLI 1.3

array set state [list \
    aliases {} \
    data {} \
    data_file [file join $::env(HOME) .time_track time_track.txt] \
    alias_file [file join $::env(HOME) .time_track aliases.txt] \
    hooks_dir [file join $::env(HOME) .time_track] \
]

::cli::setTerminalWidth [lindex [exec stty size] 1]

::cli::setAppInfo "time_track.tcl" [package require TimeTrackCLI] \
    -description "Command line based time tracking software." \
    -extra "Source code and releases found at http://github.com/dongola7/Time-Track-CLI.
Report bugs at http://github.com/dongola7/Time-Track-CLI/issues.

Released under the BSD license (http://creativecommons.org/licenses/BSD/)."

proc main {argc argv} {
    file mkdir [file dirname $::state(data_file)]
    set ::state(aliases) [read_alias_file $::state(alias_file)]
    set ::state(data) [read_data_file $::state(data_file)]

    if {[catch {::cli::main $argc $argv} msg]} {
        puts stderr $msg
        exit -1
    }

    write_data_file $::state(data_file) $::state(data)
}

proc read_alias_file {filename} {
    if {![file exists $filename]} {
        return {}
    }

    set result {}
    set line_number 1
    ::fileutil::foreachLine line $filename {
        set line [string trim $line]
        if {$line ne {}} {
            set parts [split $line =]
            if {[llength $parts] != 2} {
                return -code error "malformed alias at line $line_number: $line"
            }

            foreach {alias code} $parts break
            lappend result [list [string trim $alias] [string trim $code]]
        }

        incr line_number
    }

    return $result
}

proc read_data_file {filename} {
    if {![file exists $filename]} {
        return {}
    }

    set result {}
    ::fileutil::foreachLine line $filename {
        set line [string trim $line]
        if {$line ne {}} {
            lappend result $line
        }
    }

    return $result
}

proc write_data_file {filename data} {
    set out [open $filename w]
    foreach line $data {
        puts $out $line
    }
    close $out
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

proc get_code_from_alias {alias} {
    set index [lsearch -index 0 $::state(aliases) $alias]
    if {$index == -1} {
        return ""
    }

    return [lindex $::state(aliases) $index 1]
}

proc execute_hook {name args_list} {
    set path [file join $::state(hooks_dir) $name]
    
    if {![file executable $path]} {
        return
    }

    set cmd [list $path]
    foreach arg $args_list {
        lappend cmd [string map {\" \\" \' \\' \\ \\\\ \/ \\/} $arg]
    }

    if {[catch {exec -ignorestderr -- {*}$cmd} error]} {
        puts "error executing $name: $error"
    }
}

::cli::registerCommand cmd.start \
    -description "Starts a new task.  Stops the current task (if any)." \
    -options {
        {time.arg "now" "Explicitly sets the starting time."}
        {code.arg "" "Specify the associated charge code."}
    } \
    -arguments "<task>" \
    -name "start"
proc cmd.start {options argv} {
    array set params $options

    if {$params(time) eq "now"} {
        set params(time) [clock seconds]
    } else {
        set params(time) [clock scan $params(time)]
    }

    set code [get_code_from_alias $params(code)]
    if {$code eq ""} {
        set code $params(code)
    }

    set argv [string trim $argv]
    if {$argv eq ""} {
        return -code error "Refusing to start unspecified task."
    }

    set parts [list start_time $params(time) end_time "" message $argv code $code]

    if {[exists_active_task] != 0} {
        cmd.stop [list time [format_time $params(time)]] {}
    }

    lappend ::state(data) [components_to_line $parts]
}

::cli::registerCommand cmd.stop \
    -description "Stops the current active task." \
    -options {
        {time.arg "now" "Explicitly set the stop time."}
    } \
    -name "stop"
proc cmd.stop {options argv} {
    array set params $options

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

    set post_stop_args [list \
        $parts(message) \
        $parts(start_time) \
        $parts(end_time) \
        $parts(code) \
    ]

    execute_hook post-stop $post_stop_args
}

::cli::registerCommand cmd.cancel \
    -description "Cancels the current active task." \
    -options {
        {resume "Resume the previous task."}
    } \
    -name "cancel"
proc cmd.cancel {options argv} {
    array set params $options

    if {[exists_active_task] == 0} {
        return -code error "You're not currently working on anything."
    }

    # Delete the last task
    set ::state(data) [lreplace $::state(data) end end]

    # If there is still an active task, clear the end time
    if {$params(resume) && [llength $::state(data)] > 0} {
        set line [lindex $::state(data) end]
        array set parts [line_to_components $line]
        
        set parts(end_time) ""

        set ::state(data) [lreplace $::state(data) end end [components_to_line [array get parts]]]
    }
}

::cli::registerCommand cmd.summary \
    -description "Generates a summary report of the tasks for a given date." \
    -options {
        {date.arg "today" "The date to summarize"}
    } \
    -name "summary"
proc cmd.summary {options argv} {
    array set params $options

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

        puts [::cli::wrapText "Charges to $code" "   "]
        foreach message [array names messages] {
            set duration $messages($message)
            puts [::cli::wrapText "   $message -  [format_duration $duration]" "      "]
            incr subtotal $duration
            incr daily_total $duration
        }
        array unset messages

        puts "---"
        puts [::cli::wrapText "Subtotal for $code [format_duration $subtotal]"]
        puts ""
    }
    puts [::cli::wrapText "For the day [format_duration $daily_total]"]
}

::cli::registerCommand cmd.status \
    -description "Lists the active task and amount of time spent." \
    -name "status"
proc cmd.status {options argv} {
    if {[exists_active_task] == 0} {
        return -code error "You're not currently working on anything."
    }

    set line [lindex $::state(data) end]
    array set parts [line_to_components $line]

    set duration [expr {([clock seconds] - $parts(start_time)) / 60}]

    puts [::cli::wrapText "$parts(message) for [format_duration $duration] (since [format_time $parts(start_time)])"]
}

::cli::registerCommand cmd.list-aliases \
    -description "Lists all of the aliases defined along with their associated charge code." \
    -name "list-aliases"
proc cmd.list-aliases {options argv} {
    foreach alias_pair $::state(aliases) {
        foreach {alias code} $alias_pair break
        puts [::cli::wrapText "$alias - $code" "   "]
    }
}

::cli::registerCommand cmd.list-codes \
    -description "Lists all active charge codes and the last date and task for each." \
    -name "list-codes"
proc cmd.list-codes {options argv} {
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
        puts [::cli::wrapText "$code $summary($code)" "   "]
    }
}

::cli::registerCommand cmd.edit-aliases \
    -description "Edits the file defining aliases with the preferred editor" \
    -name "edit-aliases" \
    -options {
        {editor.arg "" "Path to the editor to execute"}
    }
proc cmd.edit-aliases {options argv} {
    array set params $options

    if {$params(editor) ne ""} {
        set editor $params(editor)
    } elseif {[info exists ::env(VISUAL)]} {
        set editor $::env(VISUAL)
    } elseif {[info exists ::env(EDITOR)]} {
        set editor $::env(EDITOR)
    } else {
        puts [::cli::wrapText "unable to determine preferred editor (did you remember to set the EDITOR environment variable?)"]
    }

    exec $editor $::state(alias_file) <@stdin >@stdout 2>@stderr
}

if {$tcl_interactive == 0} {
    main $argc $argv
}
