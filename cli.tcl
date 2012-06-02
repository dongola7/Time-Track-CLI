# Copyright (c) 2012, Blair Kitchen
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
package require Tcl 8.5
package require cmdline 1.3

package provide cli 1.0

namespace eval ::cli { 
    dict create commands { }
    dict create appInfo { }
}

proc ::cli::findMatchingCommand {cmd} {
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
        cmd.help {} {}
        exit -1
    }

    set cmd [lindex $argv 0]
    set argv [lrange $argv 1 end]

    if {[catch {findMatchingCommand $cmd} commandProc]} {
        puts stderr $commandProc
        exit -1
    }

    if {[catch {executeCommand $commandProc $argv} msg]} {
        puts stderr $msg
        exit -1
    }
}

proc ::cli::executeCommand {cmd argv} {
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

::cli::registerCommand ::cli::cmd.help \
    -description "Lists all available commands." \
    -name "help"
proc ::cli::cmd.help {params argv} {
    variable commands
    variable appInfo

    if {$appInfo ne {}} {
        puts "[dict get $appInfo name] [dict get $appInfo version]"
        puts ""
    }
    puts "Usage: [info script] <command> ?options?"
    if {[dict get $appInfo description] ne ""} {
        puts ""
        puts [dict get $appInfo description]
    }
    puts ""
    puts "Available commands:"
    puts ""
    foreach command [lsort [dict keys $commands]] {
        set description [dict get $commands $command description]
        if {$description ne ""} {
            set description " - $description"
        }
        puts "   $command$description"
    }
    puts ""
    puts "See '[info script] <command> -help' for more information on a specific command."

    set extra [dict get $appInfo extra]
    if {$extra ne ""} {
        puts ""
        puts $extra
    }
}

::cli::registerCommand ::cli::cmd.version \
    -description "Prints the version number." \
    -name "version"
proc ::cli::cmd.version {params argv} {
    variable appInfo
    puts [dict get $appInfo version]
}
