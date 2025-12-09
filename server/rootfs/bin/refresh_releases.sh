#!/bin/sh
set -e

TARGET_FILE="${1-/run/darksignsonline/releases.json}"
RELEASES_BASE_URL='https://api.github.com/repos/Doridian/DarkSignsOnline/releases/'

releases_tmp="$(mktemp)"
chmod 644 "${releases_tmp}"

curl_retry() {
    local url="${1}"
    local retries=3
    local delay=1s
    local timeout=5

    for i in $(seq 1 "${retries}"); do
        if curl -m "${timeout}" -fsL \
            -H 'Accept: application/vnd.github+json' \
            -H 'X-GitHub-Api-Version: 2022-11-28' \
            "${url}"; then
            return 0
        fi
        echo "Retrying ${url} in ${delay}" >&2
        sleep "${delay}"
    done

    echo "Failed to fetch URL: ${url}" >&2
    return 1
}

get_release() {
    local track="${1}"
    local url="${RELEASES_BASE_URL}${2}"
    local suffix="${3-,}"

    echo "Fetching release from ${url}"

    local response="$(curl_retry "${url}" || exit 1)"
    echo "\"${track}\": ${response}${suffix}" >> "${releases_tmp}"
}

get_release_last() {
    get_release "${1}" "${2}" ''
}

echo '{' > "${releases_tmp}"
get_release 'stable' 'latest' # versioned release
get_release_last 'nightly' 'tags/latest' # nightly
echo '}' >> "${releases_tmp}"

jq . "${releases_tmp}" >/dev/null # Validate JSON

echo 'Releases downloaded OK'

mv "${releases_tmp}" "${TARGET_FILE}"
