#!/bin/bash

# script to filter away default KOReader log messages
# and keep messages or errors triggered by user scripts
# and to colorize the resulting log file output

# 90–97 yields bright/high-intensity variants of the colors
# attributes can be combined with ;
# e.g. combine color with bold (1 = bold, 0 = reset all lay-out): \x1b[1;31m for bold red

# you'll have to tinker with settings below to suit your personal needs...

# ---- Config ----
LOG_FILE="/var/log/syslog"
HIST_LINES=800

PROCESS_NAME="koreader-ubuntu-restart\.desktop"
PROCESS_NAME_SHORTENED="ubuntu"
PROCESS_NAME_2="koreader-latest-restart\.desktop"
PROCESS_NAME_SHORTENED_2="latest"

RED=$'\x1b[31m' # to mark errors
GREEN=$'\x1b[32m'
YELLOW=$'\x1b[33m' # to mark warnings
BLUE=$'\x1b[94m' # to mark files
RESET=$'\x1b[0m' # to reset color formatting

REMOVE_LINES_FILTER_ENABLED=1

join_items() {
    local IFS='|'
    printf '%s' "$*"
}

# ---- Filters ----

APPLICATION_FILTER='koreader'
EXCLUDE_FILTER_PATTERNS=(
    '\.\.\.'
    '\-\-+'
    '[0-9]+\-[0-9]+\-[0-9]+ [0-9]+:[0-9]+:[0-9]+$'
    'a scroll'
    'at 0x'
    'CRE:'
    'Current time'
    'Desktop\/koreader'
    'doublecmd\.desktop'
    'ffi\.load'
    'ffi\.find'
    'for markdown parsing'
    'framebuffer resolution'
    'freetype'
    '[hw] = '
    'Inhibiting user input'
    'initializing for device'
    'KOReader\-'
    'launch'
    'lib_'
    'message repeated'
    'monolibtic'
    'No dialogs left'
    'Preparing'
    'ReaderUI instance mismatch[^\n]+'
    'reader\.lua'
    'Restoring'
    'Starting'
    '\[table:'
    'tail\.sh'
    'Tearing'
    'Version'
)
EXCLUDE_FILTER=$(join_items "${EXCLUDE_FILTER_PATTERNS[@]}")

ERROR_PATTERNS=(
    "'[^']+' expected near '[^']+'"
    'attempt to call method [^\n]+'
    'attempt to compare number with nil'
    'attempt to concatenate[^\n]+'
    'attempt to get length of[^\n]+'
    'attempt to index a nil value'
    'attempt to index (field|local) [^\n]+'
    'attempt to index upvalue[^\n]+'
    'cannot open'
    'ERROR (An error occurred while executing handler [^\n\r]+):'
    "error loading module '[^']+'"
    'Error when loading'
    'Failed to initialize [a-z]+ plugin'
    # "in function" is critical for displaying stack traces:
    "in function '[^']+'"
    'in main chunk'
    'invalid value[^\n]+'
    'module [^ ]+ not found'
    'No such file or directory'
    'Patching failed'
    'stack traceback:'
    'table index is nil'
    "unexpected symbol near '[^']+'"
)
ERROR_REGEX=$(join_items "${ERROR_PATTERNS[@]}")


# ---- Function to colorize a single line ----

colorize_line() {
    local line="$1"

    sed_expressions=(
	    # General replacements
	    "s/#011frontend/frontend/g"
	    "s/#011\[C\]//g"
	    "s/..luajit://g"
	    "s/\.[0-9]+\+[0-9]+:[0-9]+ MacBuntu\-i7//g"

	    # Lua errors
	    "s/(${ERROR_REGEX})/${RED}\1${RESET}/g"
    			# errors with mention of file:
	    "s/(cannot open|from file|from file) ([a-zA-Z0-9./']+\.lua'?)/${RED}\1${RESET} ${BLUE}\2${RESET}/g"

	    # File names and locations
	    "s/([a-zA-Z0-9./']+\.lua:[0-9]+):/${BLUE}\1${RESET}/g"

	    # Simplify process names
	    "s/ ${PROCESS_NAME}\[[0-9]+\]:/ ${PROCESS_NAME_SHORTENED}/g"
	    "s/ ${PROCESS_NAME_2}\[[0-9]+\]:/ ${PROCESS_NAME_SHORTENED_2}/g"

	    # Remove timestamps
	    "s/\/[0-9]{4}\/[0-9]{2}\/[0-9]{2}\-[0-9]{2}:[0-9]{2}:[0-9]{2} //g"
	    "s/[0-9]{4}\-[0-9]{2}\-[0-9]{2}T//g"
	    "s/(latest|ubuntu) [0-9]{2}\/[0-9]{2}\/[0-9]{2}\-[0-9]{2}:[0-9]{2}:[0-9]{2}/\1/g"

	    # Remove date-time entries before parts of an echoed lua table
	    "s/[0-9]+:[0-9]+:[0-9]+[ \t]+(ubuntu|latest) WARN([^\[{}]*)([\[{}])/WARN \2\3/g"

	    # Log levels
	    "s/INFO ([^\n]+)/${GREEN}\1${RESET}/g"
	    "s/HEADING ([^\n]+)/${YELLOW}\1${RESET}/g"
	    "s/WARN[ \t]*\n//g"
	    "s/(LOGGER_)?WARN([^\n]+)/YELLOWYELLOW\2${RESET}/g"
	    "s/(\/home\/alex[^\n:]+)/${BLUE}\1${RESET}/g"

	    # Remove left overs
	    # WARN marking an empty line:
	    "s/.+WARN$//g"
	    # remove date-time entry before yellow-marker:
	    "s/.+YELLOWYELLOW/YELLOWYELLOW/g"
	    # now mark info lines yellow:
	    "s/YELLOWYELLOW/${YELLOW}/g"
	)

	sed_args=()
	for expression in "${sed_expressions[@]}"; do
	    sed_args+=(-e "$expression")
	done

	echo "$line" | sed -E "${sed_args[@]}"
}

if [ "$REMOVE_LINES_FILTER_ENABLED" -eq 0 ]; then
	EXCLUDE_FILTER='onzinnig'
fi


# Read last HIST_LINES and follow new entries
tail -n "$HIST_LINES" -F "$LOG_FILE" |
	# Mandatory filter: koreader
  rg -i --line-buffered --smart-case --color=always "$APPLICATION_FILTER" |
	# Strip ANSI codes before processing
	# sed -u (for unbuffered) forces output to be immediately visible:
  sed -u -r 's/\x1B\[[0-9;]*[mK]//g' |
	# Exclude unwanted patterns: THIS REMOVES THE ENTIRE LINES CONTAINING THE PATTERN!
	# If you only want to remove unwanted phrases from lines you DO want to keep,
	# you can do that in the colorize_line function above:
  rg -v --line-buffered "$EXCLUDE_FILTER" |
	# ---- Run with live line-by-line processing ----
	while IFS= read -r line; do
		printf '%s\n' "$(colorize_line "$line")"
  done
