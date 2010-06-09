#!/bin/sh
# This line continues for Tcl, but is a single line for 'sh' \
exec tclsh "$0" ${1+"$@"}

package require Tcl 8.4
package require cmdline 1.3

array set state [list \
    data {} \
    data_file [file join $::env(HOME) .time_track time_track.txt] \
]

proc main {argc argv} {
    if {$argv < 1} {
        puts stderr "Usage: [info script] <command> ?options?"
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

proc cmd.start {argv} {
    set options {
        {time.arg "now" "Explicitly set the starting time."}
        {code.arg "" "Specify the associated charge code."}
    }
    set usage "start \[options] <task>\noptions:"

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

proc cmd.stop {argv} {
    set options {
        {time.arg "now" "Explicitly set the stop time."}
    }
    set usage "stop \[options]\noptions:"

    array set params [::cmdline::getoptions argv $options $usage]

    if {[exists_active_task] == 0} {
        return -code error "You're not currently working on anything."
    }

    set line [lindex $::state(data) end]
    array set parts [line_to_components $line]

    set start_time [clock scan $parts(start_time)]

    if {$params(time) eq "now"} {
        set params(time) [clock seconds]
    } else {
        set params(time) [clock scan $params(time)]
    }

    set parts(end_time) $params(time)

    set ::state(data) [lreplace $::state(data) end end [components_to_line [array get parts]]]
}

proc cmd.summary {argv} {
    set options {
        {date.arg "today" "The date to summarize"}
    }
    set usage "summary \[options]\noptions:"

    array set params [::cmdline::getoptions argv $options $usage]

    if {$params(date) eq "today"} {
        set filter_start_time [clock scan "today 0:00"]
    } else {
        set filter_start_time [clock scan $params(date)]
        set filter_start_time [clock scan [clock format $filter_start_time -format %D]]
    }

    set filter_end_time [expr {86400 + $filter_start_time}]

    array set summary {}

    foreach line $::state(data) {
        array set parts [line_to_components $line]

        if {$parts(end_time) eq ""} {
            set parts(end_time) [clock seconds]
        }

        if {$parts(start_time) > $filter_end_time} {
            continue
        } elseif {$parts(end_time) < $filter_start_time} {
            continue
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
        
        puts "Charges to $code"
        foreach {duration message} $summary($code) {
            puts "   $message -  [format_duration $duration]"
            incr subtotal $duration
            incr daily_total $duration
        }

        puts "---"
        puts "Subtotal for $code [format_duration $subtotal]"
        puts ""
    }
    puts "For the day [format_duration $daily_total]"
}

proc cmd.status {argv} {
    if {[exists_active_task] == 0} {
        return -code error "You're not currently working on anything."
    }

    set line [lindex $::state(data) end]
    array set parts [line_to_components $line]

    set duration [expr {([clock seconds] - $parts(start_time)) / 60}]

    puts "$parts(message) for [format_duration $duration]"
}

proc cmd.list-codes {argv} {
    array set summary {}

    foreach line $::state(data) {
        array set parts [line_to_components $line]

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

main $argc $argv
