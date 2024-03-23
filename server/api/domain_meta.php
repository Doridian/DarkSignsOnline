<?php

$rewrite_done = true;
require_once("function.php");

$getip = $_REQUEST['getip'];
if (!empty($getip)) {
    $dInfo = getDomainInfo($getip);
    if ($dInfo[0] <= 0) {
        die_error('not found', 404);
    }
    die($dInfo[3]);
}

$getdomain = $_REQUEST['getdomain'];
if (!empty($getdomain)) {
    $dom = getIpDomain($getdomain);
    if (empty($dom)) {
        die_error('not found', 404);
    }
    die($dom);
}
