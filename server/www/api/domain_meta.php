<?php

require_once('function.php');

$getip = $_REQUEST['getip'];
if (!empty($getip)) {
    $dInfo = getDomainInfo($getip);
    if ($dInfo === false) {
        die_error('not found', 404);
    }
    die($dInfo['ip']);
}

$getdomain = $_REQUEST['getdomain'];
if (!empty($getdomain)) {
    $dom = getIpDomain($getdomain);
    if (empty($dom)) {
        die_error('not found', 404);
    }
    die($dom);
}
