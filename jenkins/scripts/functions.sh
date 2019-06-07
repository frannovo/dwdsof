#!/bin/bash

msg()
{
	printf "%s\n" "$@"
	if read -t0 _; then
		cat
	fi
}

msg_with_prefix()
{
	local prefix="$1"
    local i
	shift
	local lines=("$@")

	if read -t0 _; then
		readarray -t -O "${#lines[@]}" lines
	fi

	for ((i=0; i < ${#lines[@]}; i++)); do
		lines[$i]="${prefix} ${lines[$i]}"
	done

	msg "${lines[@]}"
}

err()
{
	msg_with_prefix '[ERROR]' "$@" >&2
	EXCEPTIONS+=("$@")
}

errfeedback()
{
    # shellcheck disable=SC2034
    FEEDBACK="$*"
    err "$@"
}

die()
{
	err "$@"
	exit 1
}

diefeedback()
{
    # shellcheck disable=SC2034
    FEEDBACK="$*"
    die "$@"
}

die_notifying()
{
    # notifyFailure "<a href="$bamboo_resultsUrl">${bamboo_buildResultKey:-Bamboo Log}</a>: $*" "$ALERTS_NOTIFICATION_IM"
    err "$@"
    die "Delivery Services has been notified. Please ensure you check 'full build log' to find failure reason."
}

# Deprecated. Use err, die or fatal directly instead.
logerror() {
	if (( $# == 2 )) && [[ "$2" == true ]]; then
		die "$1"
	else
		err "$@"
	fi
}

fatal()
{
	die "FATAL: ${*%.}. Exiting."
}

log()
{
	msg_with_prefix '[INFO]' "$@"
}

warn()
{
	msg_with_prefix '[WARN]' "$@"
}

logfeedback()
{
	# shellcheck disable=SC2034
    FEEDBACK="$*"
    log "$@"
}

note()
{
	local debug="${DEBUG-false}"
	if [[ "$debug" == true ]]; then
		msg_with_prefix '   ...' "$@"
	fi
}

checked() {
	if [[ "${1,,}" == "true" ]]; then
		echo -n 'X'
	else
		echo -n ' '
	fi
}

ensure_vars()
{
	for var in "$@"; do
		[[ -z "${!var}" ]] && die "Variable \$$var must not be empty."
	done
}

version_le() {
	test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" == "$1";
}

curl_request_raw() {
	(( $# < 2 )) && return 2
	local method="$1"
	local url="${2// /%20}"
	shift 2
	local extra_params=("$@")

	# Create a file handle and redirect it to stdout. Then print the HTTP
	# status code, which will be captured in the $http_status variable, and
	# redirect the output to the file handle, which will be in turn redirected
	# to stdout. Then we can print the HTTP status code to stderr so we can get
	# both the status code and the output separately.
	local http_status
	local fd
	exec {fd}>&1
	http_status="$(curl \
		--retry "${CURL_NUM_RETRIES}" \
		--retry-delay "${CURL_RETRY_SECONDS}" \
		-skL \
		--post30{1..3} \
		-w '%{http_code}' \
		-o >(cat >&$fd) \
		-X "${method^^}" \
		"${extra_params[@]}" \
		"${url}"
	)"
	local retval=$?
	exec {fd}>&-
	echo -e "\n$http_status" >&2

	if [[ "$http_status" == [45]* ]]; then
		retval="${http_status:0:1}"
	elif [[ "$http_status" != [12345]* ]]; then
		retval=255
	fi

	return "$retval"
}

curl_request() {
	# The HTTP status code comes in stderr, so we discard it.
	curl_request_raw "$@" 2>/dev/null
}

curl_http_code() {
	# In this case, we only want the HTTP status code and not the body. We
	# first redirect the stderr file handle to stdout and then redirect the
	# stdout file handle to /dev/null, so the stderr from curl_request_raw is
	# printed to stdout and the body is discarded.
	# shellcheck disable=SC2069
	curl_request_raw "$@" 2>&1 1>/dev/null
}

curl_get() {
	curl_request GET "$@"
}

curl_post() {
	curl_request POST "$@"
}

curl_put() {
	curl_request PUT "$@"
}

curl_upload() {
    (( $# < 2 )) && return 2
	local src_file="$1"
	local url="$2"
	shift 2
	curl_put "$url" -T "$src_file" "$@"
}

curl_mkdir() {
	local url=''
	local args=()
	local create_parents=''
	local return_httpcode=''

	# Don't want the option to interfere with curl's own, so namespacing it.
	for arg in "$@"; do
		if [[ "$arg" == "--mkdir-create-parents" ]]; then
			create_parents='true'
		elif [[ "$arg" == "--mkdir-return-httpcode" ]]; then
			return_httpcode='true'
		elif [[ "$arg" =~ ^https?:// ]]; then
			url="$arg"
		else
			args+=("$arg")
		fi
	done

	# If there's no URL (only Zuul), then bail out.
	[[ -z "$url" ]] && return 1

	# If the call works the first time, just end it there and move on.
	local httpcode
	exec {fd}>&1
	httpcode="$(curl_request_raw MKCOL "${args[@]}" "$url" 2>&1 >&$fd)"
	local retval=$?
	exec {fd}>&-
	if [[ -n "$return_httpcode" ]]; then
		echo -e "\n$httpcode" >&2
	fi

	(( retval == 0 )) && return 0

	if [[ -n "$create_parents" ]]; then
		local parents=("$url")

		# Remove the last directory fragment.
		url="${url%/*}"
		
		# If the last directory fragment was the root directory already, just
		# bail out.
		[[ "$url" =~ ^https?://[^/]+$ ]] && return "$retval"

		# Keep removing directory fragments from the URL and storing them in an
		# array in reverse order until one call succeeds.
		until curl_request MKCOL "${args[@]}" "$url"; do
			retval=$?
			parents=("$url" "${parents[@]}")
			url="${url%/*}"

			# If the last directory fragment was the root directory already,
			# just bail out.
			[[ "$url" =~ ^https?://[^/]+$ ]] && return "$retval"
		done

		# Finally, try to create all the remaining parent directories.
		for parent in "${parents[@]}"; do
			# We bail out on the first parent that fails, since that means it's
			# not a problem of parents not existing.
			curl_request MKCOL "${args[@]}" "$parent" || return $?
		done
	fi
}

curl_delete() {
	curl_request DELETE "$@"
}

curl_json() {
	curl_request "$@" \
		"${CURL_JSON_HEADERS[@]}"
}

curl_json_get() {
	curl_json GET "$@"
}

curl_json_post() {
	curl_json POST "$@"
}

curl_json_put() {
	curl_json PUT "$@"
}

curl_json_delete() {
	curl_json DELETE "$@"
}

extract_json_from_request()
{
	local url="$1"
	local jq_expr="$2"
	local method="${3:-GET}"
	local payload="$4"

	# shellcheck disable=SC2154
	curl_json "$method" "$url" \
		-d "$payload" \
		-u "${sonar_user}:${sonar_user_password}" | \
		jq -r "$jq_expr"
}

merge_json_objects()
{
	local merge_first="${1:-null}"
	local merge_second="${2:-null}"
	jq \
		-n \
		--argjson merge_first "$merge_first" \
		--argjson merge_second "$merge_second" \
		'($merge_first + {}) * ($merge_second + {})' \
		2>/dev/null
}

deploy_data()
{
	local field="$1"
	local deploy_data="${2-${DEPLOY_DATA}}"

	jq -r ".$field" <<< "$deploy_data"
}

exit_and_save_code()
{
	local retval="$1"
	local prefix="${2-ms}"

	# shellcheck disable=SC2154
	cd "${WORKSPACE}"
	echo "exitcode=$1" > "${prefix}-exitcode.properties"
	exit "$retval"
}

download()
{
    local TARGET="$1"
    local SOURCE="$2"
    local FAILSAFE="${3-true}"
    log "Downloading ${SOURCE} ... "
    
    if ! wget -O "${TARGET}" -q "${SOURCE}"; then
        if [[ "$FAILSAFE" != true ]]; then
            die "Unable to retrieve ${SOURCE}."
        else
            msg "[WARN] Could not download ${SOURCE} but failsafe mode is enabled. The process will continue..."
            return 1
        fi
    fi
}

curl_mkdir_if_not_exists() {
	local http_code=$(curl_mkdir --mkdir-return-httpcode "$@" --user "${sonar_user}:${sonar_user_password}" 2>&1 > /dev/null | tail -1)
	if [[ ${http_code} != [123]* && "${http_code}" == 405 ]]; then
		echo -e "\nThe request to create a directory failed with a HTTP error ${http_code}." >&2
		return "${http_code:0:1}"
	fi
}

check_jq() {
    local jq_path
    jq_path="$(which jq)"
    if [[ -z "${jq_path}" ]]; then
        echo "ERROR: the jq tool is required to run this script. Install it by running < yum/apt-get install jq >" >&2
        exit 1
    fi
}

check_bash() {
    if [[ $bash_major_version -lt $MIN_BASH_VERSION ]]; then
        echo "** Your bash version is too old, this script requires Bash $MIN_BASH_VERSION or newer. **"
        exit 1
    fi
}

# This function can be really useful if we want to take all the environment
# variables (or only some of them, with a prefix) and pass them as JSON values
# somewhere. In the process, since all environment variables are strings, it'll
# try to convert all values into native JSON values: numbers, booleans and even
# JSON objects and arrays.
#
# If you specify a prefix, it'll take the prefix out of the variable name.
env_json()
{
	local prefix="${1//./_}${1+_}"
	jq -n --arg prefix "$prefix" 'env | [to_entries[] | select(.key | startswith($prefix)) | .key |= sub("^\($prefix)"; "") | .value as $v | .value |= try (. | fromjson) catch $v] | from_entries'
}

bamboo_env_json()
{
	local prefix="bamboo_${1//./_}"

	env_json "$prefix"
}

declare -A environments=(
	["dev"]="dev"
	["prod"]="prod"
)

# JENKINS
JENKINS_BASE_URL="http://${JENKINS_BASE_URL}"

# JIRA
JIRA_BASE_URL="http://${JIRA_BASE_URL}"
JIRA_BROWSER="${JIRAOPS_BASE_URL}/browse"
sonar_user="${user}"
sonar_user_password="${password}"
project_key="${project_key}"

# Common settings
CURL_NUM_RETRIES=5
CURL_RETRY_SECONDS=5
CURL_JSON_CONTENT_TYPE=('-H' 'Content-Type: application/json')
CURL_JSON_ACCEPT=('-H' 'Accept: application/json')
CURL_JSON_HEADERS=("${CURL_JSON_CONTENT_TYPE[@]}" "${CURL_JSON_ACCEPT[@]}")
ANSI_LINK_START="\e[1;90m\e[4;30m"
ANSI_LINK_END="\e[0m"

declare -A PIPELINE_STATUSES
PIPELINE_STATUSES=(
    [PENDING]=-1
    [RUNNING]=0
    [RECOVERING]=1
    [SUCCESSFUL]=2
    [RECOVERED]=3
    [FAILED]=4
    [STOPPED]=5
)
