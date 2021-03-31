`/usr/local/bin/check-doms.sh /etc/squid/blacklist.list`

```
acl youtube_doms dstdomain .youtube.com .youtu.be .ytimg.com
acl YTMETHODS method GET POST PUT OPTIONS HEAD

external_acl_type sni_matcher concurrency=10 children-max=60 children-startup=20 children-idle=20 ttl=15 %SRC %ssl::>sni %METHOD %DST /usr/bin/socat - UNIX-CONNECT:/tmp/sni-dstdomain
acl sni_matcher_helper external sni_matcher

##
external_acl_type youtube_blacklist concurrency=10 children-max=60 children-startup=20 children-idle=20 ttl=15 %SRC %URI %METHOD /usr/bin/socat - UNIX-CONNECT:/tmp/youtube-filter
acl yt_blacklist_helper external youtube_blacklist

##
external_acl_type youtube_whitelist concurrency=10 children-max=60 children-startup=20 children-idle=20 ttl=15 %SRC %URI %METHOD /usr/bin/socat - UNIX-CONNECT:/tmp/youtube-filter-whitelist
acl yt_whitelist_helper external youtube_whitelist

##
external_acl_type sni_matcher concurrency=10 children-max=60 children-startup=20 children-idle=20 ttl=15 %SRC %ssl::>sni %METHOD %DST /usr/bin/socat - UNIX-CONNECT:/tmp/sni-dstdomain
acl sni_matcher_helper external sni_matcher

acl tls_to_bump any-of Bump_server_name Bump_server_regex_by_urls_domain Bump_server_regex Bump_dst sni_matcher_helper yandex_bl_checker_helper

http_access deny YTMETHODS youtube_doms ythelper_1

## Static Lists
http_access allow YTMETHODS youtube_doms yt_urls_whitelist_regex_list
http_access deny YTMETHODS youtube_doms yt_urls_blacklist_regex_list

## Helper
http_access deny YTMETHODS youtube_doms yt_blacklist_helper
```
