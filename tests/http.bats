#!/usr/bin/env bats

. ../inc.common.sh

@test "HTTP URL tests" {
    $(is_http_url "http://www.delfi.lv")
    $(is_http_url "https://www.delfi.lv")
    ! $(is_http_url "http:/www.delfi.lv")
}
