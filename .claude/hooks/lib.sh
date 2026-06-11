verdict() {
	echo "$1"
	echo "${verdict_prefix:+$verdict_prefix }$2"
	exit 0
}

deny() { verdict deny "$1"; }
warn() { verdict warn "$1"; }

url_host() {
	local host=${1#*://}
	host=${host%%[/?#]*}
	host=${host##*@}
	host=${host%%:*}
	printf '%s' "${host,,}"
}

url_path() {
	local rest=${1#*://}
	rest=${rest%%[?#]*}
	[[ "$rest" == */* ]] && printf '/%s' "${rest#*/}"
}

url_host_is() {
	local host domain
	host=$(url_host "$1")
	shift
	for domain in "$@"; do
		[[ "$host" == "$domain" || "$host" == *".$domain" ]] && return 0
	done
	return 1
}

url_segment() {
	local -a segments
	IFS=/ read -r -a segments <<< "$(url_path "$1")"
	printf '%s' "${segments[$2]:-}"
}
