" Define syntax highlighting for the Time-Track-CLI text file format
if exists("b:current_syntax")
    finish
endif

syn match ttCode '@\S\+$'
syn match ttDateTime contained '\d\{2\}/\d\{2\}/\d\{4\} \d\{2\}:\d\{2\}'
syn region ttDateTimeBlock start="^(" end=")" transparent contains=ttDateTime

let b:current_syntax = "Time-Track-TCL"

hi def link ttCode Comment
hi def link ttDateTime Constant
