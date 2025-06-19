<?php

require_once("function.php");


$uid = $user['id'];
$d = trim($_REQUEST['d']);
$port = (int)$_REQUEST['port'];

$filename = $_REQUEST['filename'];

print_returnwith();

$dInfo = getDomainInfo($d);
if ($dInfo === false) {
    die_error('Domain does not exist.', 404);
}

$stmt = $db->prepare('SELECT code FROM domain_scripts WHERE domain=? AND port=? AND ver=?');
$stmt->bind_param('iii', $dInfo['id'], $port, $ver);
$stmt->execute();
$res = $stmt->get_result();
$row = $res->fetch_assoc();
if (!empty($row)) {
    $script = $row['code'];

    if (strtoupper(substr($script, 0, strlen(DSO_SCRIPT_CRYPTO_HEADER))) === strtoupper(DSO_SCRIPT_CRYPTO_HEADER)) {
        die_error("Cannot Download Compiled Script: " . strtoupper($d) . ":$port", 403);
    }

    die("$filename:$script");
} else {
    die_error("No Script Found: " . strtoupper($d) . ":$port", 404);
}
