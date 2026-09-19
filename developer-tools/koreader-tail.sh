#!/bin/bash

# script to filter away default KOReader log messages
# and keep messages or errors triggered by user scripts
# and to colorize the resulting log file output

# 90–97 yields bright/high-intensity variants of the colors
# attributes can be combined with ;
# e.g. combine color with bold (1 = bold, 0 = reset all lay-out): \x1b[1;31m for bold red

# ---- Config ----
LOG_FILE="/var/log/syslog"
HIST_LINES=800

PROCESS_NAME="koreader-ubuntu-restart\.desktop"
PROCESS_NAME_SHORTENED="ubuntu"
PROCESS_NAME_2="koreader-latest-restart\.desktop"
PROCESS_NAME_SHORTENED_2="latest"

RED=$'\x1b[31m'
BRIGHT_RED=$'\x1b[1;31m' # to mark error messages
GREEN=$'\x1b[32m'
YELLOW=$'\x1b[33m' # to mark warnings
BRIGHT_YELLOW=$'\x1b[93m'
BLUE=$'\x1b[94m' # to mark files
RESET=$'\x1b[0m' # to reset color formatting


# ---- Function to colorize a single line ----

colorize_line() {
    local line="$1"
    
    sed_expressions=(
	    # General replacements
	    "s/#011frontend/frontend/g"
	    "s/..luajit://g"
	    #"s/ (INFO|WARN) */ /g"
	    "s/\.[0-9]+\+[0-9]+:[0-9]+ MacBuntu\-i7//g"

	    # Log levels
	    "s/INFO ([^\n]+)/${GREEN}\1${RESET}/g"
	    "s/HEADING ([^\n]+)/${YELLOW}\1${RESET}/g"
	    "s/WARN ([^\n]+)/${YELLOW}\1${RESET}/g"

	    # Lua errors
	    			# "in function" is critical for displaying stack traces:
	    "s/(attempt to call method [^\n]+|attempt to concatenate[^\n]+|module [^ ]+ not found|attempt to index (field|local) [^\n]+|'[^']+' expected near '[^']+'|unexpected symbol near '[^']+'|in function '[^']+'|stack traceback:|No such file or directory|Patching failed|invalid value[^\n]+|attempt to index a nil value|attempt to get length of[^\n]+|attempt to index upvalue[^\n]+|Error when loading)/${RED}\1${RESET}/g"
	    			# errors with mention of file:
	    "s/(cannot open|from file|from file) ([a-zA-Z0-9./']+\.lua'?)/${RED}\1${RESET} ${BLUE}\2${RESET}/g"
	    "s/ERROR (An error occurred while executing handler [^\n\r]+):/${RED}\1${RESET}/g"

	    # File names and locations
	    "s/([a-zA-Z0-9./']+\.lua:[0-9]+):/${BLUE}\1${RESET}/g"

	    # Simplify process names
	    "s/ ${PROCESS_NAME}\[[0-9]+\]:/ ${PROCESS_NAME_SHORTENED}/g"
	    "s/ ${PROCESS_NAME_2}\[[0-9]+\]:/ ${PROCESS_NAME_SHORTENED_2}/g"

	    # Remove timestamps
	    "s/\/[0-9]{4}\/[0-9]{2}\/[0-9]{2}\-[0-9]{2}:[0-9]{2}:[0-9]{2} //g"
	    "s/[0-9]{4}\-[0-9]{2}\-[0-9]{2}T//g"
	    "s/(latest|ubuntu) [0-9]{2}\/[0-9]{2}\/[0-9]{2}\-[0-9]{2}:[0-9]{2}:[0-9]{2}/\1/g"
	)
	
	sed_args=()
	for expression in "${sed_expressions[@]}"; do
	    sed_args+=(-e "$expression")
	done

	echo "$line" | sed -E "${sed_args[@]}"
}

# ---- Filters ----

KOREADER_FILTER='koreader'
EXCLUDE_FILTER='ffi\.load|ffi\.find|freetype|lib_|Version|Starting|launch|monolibtic|a scroll|Current time|\[table:|[hw] = |tail\.sh|CRE:|at 0x|\.\.\.|Desktop\/koreader|for markdown parsing|Inhibiting user input|Restoring|Preparing|Tearing|reader\.lua|KOReader|\-\-+|framebuffer resolution|message repeated|No dialogs left|doublecmd\.desktop|initializing for device'


# Read last HIST_LINES and follow new entries
tail -n "$HIST_LINES" -F "$LOG_FILE" |
# Mandatory filter: koreader
    rg -i --line-buffered --smart-case --color=always "$KOREADER_FILTER" |
# Strip ANSI codes before processing
# sed -u (for unbuffered) forces output to be immediately visible:
    sed -u -r 's/\x1B\[[0-9;]*[mK]//g' |
# Exclude unwanted patterns: THIS REMOVES THE ENTIRE LINES CONTAINING THE PATTERN! If you only want to remove unwanted phrases from lines you DO want to keep, you can do that in the colorize_line function above:
    rg -v --line-buffered "$EXCLUDE_FILTER" |
# ---- Run with live line-by-line processing ----
    while IFS= read -r line; do
        printf '%s\n' "$(colorize_line "$line")"
    done

