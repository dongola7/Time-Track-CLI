# Copyright (c) 2012, Blair Kitchen
# All rights reserved.
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.

package require Tcl 8.5
package require cmdline 1.3

package provide cli 1.0

namespace eval ::cli { 
    dict create commands { }
    dict create appInfo { }
    set terminalWidth 80

    namespace export setAppInfo registerCommand wrapText
}

proc ::cli::setTerminalWidth {width} {
    variable terminalWidth

    set terminalWidth $width
}

proc ::cli::FindMatchingCommand {cmd} {
    variable commands

    if {[dict keys $commands $cmd] ne {}} {
        return $cmd
    }

    # See if this is a unique prefix
    set cmd_list [dict keys $commands $cmd*]
    if {[llength $cmd_list] == 1} {
        return [lindex $cmd_list 0]
    }

    # Generate an error message.  If we have some possible
    # commands, include these in the message.
    set error_msg "Unknown command '$cmd'."
    if {[llength $cmd_list] > 0} {
        set cmd_list [lsort $cmd_list]
        append error_msg "\nDid you mean:"
        foreach cmd $cmd_list {
            append error_msg "\n\t$cmd"
        }
    }

    return -code error $error_msg
}

proc ::cli::wrapText {text {linePrefix ""} {width ""}} {
    variable terminalWidth

    if {$width eq ""} {
        set width $terminalWidth
    }

    if {[string length $text] < $width} {
        return $text
    }

    set result ""

    while {[string length $text] > $width} {

        if {[string length $result] > 0} {
            append result "\n$linePrefix"
            set width [expr {$width - [string length $linePrefix]}]
        }

        set lineEndIndex [string wordstart $text $width]
        if {$lineEndIndex != 0} {
            incr lineEndIndex -1
        }
        append result [string range $text 0 $lineEndIndex]
        set text [string range $text [expr {$lineEndIndex + 1}] end]
    }

    if {[string length $text] > 0} {
        append result "\n$linePrefix$text"
    }

    return $result
}

proc ::cli::setAppInfo {name version args} {
    variable appInfo

    set options {
        {description.arg "" "Description of the software"}
        {extra.arg "" "Extra text to include at the end of help output"}
    }

    array set params [::cmdline::getoptions args $options]

    dict set appInfo name $name
    dict set appInfo version $version
    dict set appInfo description $params(description)
    dict set appInfo extra $params(extra)
}

proc ::cli::main {argc argv} {
    if {$argv < 1} {
        Cmd.help {} {}
        exit -1
    }

    set cmd [lindex $argv 0]
    set argv [lrange $argv 1 end]

    if {[catch {FindMatchingCommand $cmd} commandProc]} {
        puts stderr $commandProc
        exit -1
    }

    if {[catch {ExecuteCommand $commandProc $argv} msg]} {
        puts stderr $msg
        exit -1
    }
}

proc ::cli::ExecuteCommand {cmd argv} {
    variable commands

    set description [dict get $commands $cmd description]
    set options [dict get $commands $cmd options]
    set usage [dict get $commands $cmd usage]
    set proc [dict get $commands $cmd proc]

    set params [::cmdline::getoptions argv $options $usage]

    uplevel #0 [list $proc $params $argv]
}

proc ::cli::registerCommand {cmd args} {
    variable commands

    set options {
        {description.arg "" "Description of the command"}
        {options.arg "" "Options accepted by the command (same format as cmdline)"}
        {arguments.arg "" "Other arguments required by the command"}
        {name.arg "" "Name for the command (defaults to Tcl procedure name)"}
    }

    array set params [::cmdline::getoptions args $options]
    if {$params(name) eq ""} {
        set params(name) $cmd
    }

    dict set commands $params(name) options $params(options)
    dict set commands $params(name) description $params(description)
    dict set commands $params(name) usage "$params(name) \[options] $params(arguments)\n\n$params(description)\n\noptions:"
    dict set commands $params(name) proc $cmd
}

::cli::registerCommand ::cli::Cmd.help \
    -description "Lists all available commands." \
    -name "help"
proc ::cli::Cmd.help {params argv} {
    variable commands
    variable appInfo

    if {$appInfo ne {}} {
        puts "[dict get $appInfo name] [dict get $appInfo version]"
        puts ""
    }
    puts [wrapText "Usage: [info script] <command> ?options?" "   "]
    if {[dict get $appInfo description] ne ""} {
        puts ""
        puts [wrapText [dict get $appInfo description]]
    }
    puts ""
    puts "Available commands:"
    puts ""
    foreach command [lsort [dict keys $commands]] {
        set description [dict get $commands $command description]
        if {$description ne ""} {
            set description " - $description"
        }
        puts [wrapText "   $command$description" "      "]
    }
    puts ""
    puts [wrapText \
        "See '[info script] <command> -help' for more information on a specific command."]

    set extra [dict get $appInfo extra]
    if {$extra ne ""} {
        puts ""
        foreach line [split $extra \n] {
            puts [wrapText $line]
        }
    }
}

::cli::registerCommand ::cli::cmd.version \
    -description "Prints the version number." \
    -name "version"
proc ::cli::cmd.version {params argv} {
    variable appInfo
    puts [dict get $appInfo version]
}
