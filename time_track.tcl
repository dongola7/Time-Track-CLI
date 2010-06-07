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

proc line_to_components {line} {
    if {[regexp -- {^\((.*)\) (.*) (\@.*)?} $line -> times message code] == 0} {
        return -code error "Malformed line '$line'"
    }

    if {[regexp -- {(.*) - (.*)} $times -> start_time end_time] == 0} {
        return -code error "Malformed times in line '$line'"
    }

    set code [string range $code 1 end]

    return [list start_time $start_time end_time $end_time message $message code $code]
}

proc components_to_line {components} {
    array set parts $components
    if {$parts(code) ne ""} {
        set parts(message) "$parts(message) @$parts(code)"
    }
    return "($parts(start_time) - $parts(end_time)) $parts(message)"
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
        {time.arg "" "Explicitly set the starting time."}
        {code.arg "" "Specify the associated charge code."}
    }
    set usage "start \[options] <task>\noptions:"

    array set params [::cmdline::getoptions argv $options $usage]

    if {$params(time) eq ""} {
        set params(time) [format_time [clock seconds]]
    } else {
        set params(time) [format_time [clock scan $params(time)]]
    }

    set parts [list start_time $params(time) end_time "" message $argv code $params(code)]

    if {[exists_active_task] != 0} {
        cmd.stop {}
    }

    lappend ::state(data) [components_to_line $parts]
}

proc cmd.stop {argv} {
    set options {
        {time.arg "" "Explicitly set the stop time."}
    }
    set usage "stop \[options]\noptions:"

    array set params [::cmdline::getoptions argv $options $usage]

    if {[exists_active_task] == 0} {
        return -code error "There is no currently active task."
    }

    set line [lindex $::state(data) end]
    array set parts [line_to_components $line]

    set start_time [clock scan $parts(start_time)]

    if {$params(time) eq ""} {
        set params(time) [format_time [clock seconds]]
    } else {
        set params(time) [format_time [clock scan $params(time)]]
    }

    set parts(end_time) $params(time)

    set ::state(data) [lreplace $::state(data) end end [components_to_line [array get parts]]]
}

proc cmd.status {argv} {
    if {[exists_active_task] == 0} {
        return -code error "You're not currently working on anything."
    }

    set line [lindex $::state(data) end]
    array set parts [line_to_components $line]

    set start_time [clock scan $parts(start_time)]

    set duration [expr {([clock seconds] - $start_time) / 60}]

    puts "$parts(message) for $duration minutes"
}

main $argc $argv
