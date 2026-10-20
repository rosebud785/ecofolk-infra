#!/usr/bin/env bash
# check-load-target.sh — guard for #16: refuse to point the k6 beta load test
# (load/beta-20.js) at anything but a public, https, non-prod QA target.
#
# WHY
#   The load test drives 20 VUs for 10 minutes and, with a token, writes rows.
#   Aimed at prod it is an outage plus junk data; aimed at a private or loopback
#   address from a hosted runner it is at best noise, at worst a probe of
#   whatever answers there. The run is cheap to start by accident, so the guard
#   runs first and refuses anything that isn't plainly a QA URL.
#
# WHAT IT REFUSES (exit 1)
#   - a scheme other than https;
#   - a URL containing "prod" anywhere, in any case (host, path, query);
#   - a host that is a private or loopback address:
#       IPv4 10/8, 172.16/12, 192.168/16, 127.0.0.0/8,
#       plus 0.0.0.0/8 and 169.254.0.0/16 (link-local, cloud metadata);
#       IPv6 ::1, ::, fc00::/7, fe80::/10, and IPv4-mapped ::ffff:*;
#       the name "localhost" (and *.localhost);
#   - a numeric host that isn't a plain dotted quad (e.g. 2130706433, 0x7f.1,
#     017.0.0.1): those are other spellings of an IPv4 address, refused rather
#     than decoded;
#   - no host at all.
#
# WHAT IT DOES NOT DO
#   No DNS lookup: a public name that resolves to a private address passes.
#   The target is meant to come from one reviewed variable (the local
#   follow-up workflow's QA base URL), not from free text.
#
# USAGE
#   bash scripts/check-load-target.sh URL
#
# EXIT: 0 = URL accepted (prints LOAD_TARGET_OK).
#       1 = URL refused (prints REFUSED and the reason).
#       2 = usage error (no URL, or more than one argument).

set -uo pipefail

RED=$'\033[31m'; GRN=$'\033[32m'; RST=$'\033[0m'
[ -t 1 ] || { RED=""; GRN=""; RST=""; }

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
    echo "usage: bash scripts/check-load-target.sh URL" >&2
    exit 2
fi

URL="$1"
# tr, not ${URL,,}: that is bash 4 and a bad substitution on macOS bash 3.2 (#76).
LC_URL="$(printf '%s' "$URL" | tr '[:upper:]' '[:lower:]')"

refuse() {
    echo "${RED}REFUSED${RST}: $1 ($URL)"
    exit 1
}

# 1. Scheme.
case "$LC_URL" in
    https://*) ;;
    *) refuse "scheme is not https" ;;
esac

# 2. "prod" anywhere in the URL.
case "$LC_URL" in
    *prod*) refuse "URL contains \"prod\"" ;;
esac

# 3. Host: drop the scheme, then everything from the first / ? or #, then any
#    userinfo, then the port.
rest="${LC_URL#https://}"
authority="${rest%%[/?#]*}"
host="${authority##*@}"
if [[ "$host" == \[* ]]; then
    # IPv6 literal: [addr] or [addr]:port.
    host="${host#\[}"
    host="${host%%\]*}"
    ipv6=1
else
    host="${host%%:*}"
    ipv6=0
fi
host="${host%.}"   # a trailing dot is the same name

[ -n "$host" ] || refuse "no host"

if [ "$ipv6" -eq 1 ]; then
    case "$host" in
        ::1|0:0:0:0:0:0:0:1|::|0:0:0:0:0:0:0:0) refuse "loopback or unspecified IPv6 address" ;;
        f[cd]*:*) refuse "private IPv6 address (fc00::/7)" ;;
        fe[89ab]*:*) refuse "link-local IPv6 address (fe80::/10)" ;;
        *::ffff:*) refuse "IPv4-mapped IPv6 address" ;;
    esac
    echo "${GRN}LOAD_TARGET_OK${RST}: $URL"
    exit 0
fi

case "$host" in
    localhost|*.localhost) refuse "loopback name" ;;
esac

# A host made only of digits, dots and hex markers is an IPv4 address in some
# spelling. Accept only a plain dotted quad (no leading zeros, octets <= 255),
# and refuse every other numeric form rather than guess how a client decodes it.
if [[ "$host" =~ ^(0x[0-9a-f]*|[0-9]+)(\.(0x[0-9a-f]*|[0-9]+))*$ ]]; then
    if ! [[ "$host" =~ ^(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})$ ]]; then
        refuse "numeric host is not a plain dotted-quad IPv4 address"
    fi
    IFS=. read -r a b _ _ <<< "$host"
    for o in ${host//./ }; do
        [ "$o" -le 255 ] || refuse "IPv4 octet out of range"
    done
    if   [ "$a" -eq 10 ];                          then refuse "private IPv4 address (10/8)"
    elif [ "$a" -eq 172 ] && [ "$b" -ge 16 ] && [ "$b" -le 31 ]; then refuse "private IPv4 address (172.16/12)"
    elif [ "$a" -eq 192 ] && [ "$b" -eq 168 ];     then refuse "private IPv4 address (192.168/16)"
    elif [ "$a" -eq 127 ];                         then refuse "loopback IPv4 address (127.0.0.0/8)"
    elif [ "$a" -eq 0 ];                           then refuse "unspecified IPv4 address (0.0.0.0/8)"
    elif [ "$a" -eq 169 ] && [ "$b" -eq 254 ];     then refuse "link-local IPv4 address (169.254.0.0/16)"
    fi
fi

echo "${GRN}LOAD_TARGET_OK${RST}: $URL"
exit 0
