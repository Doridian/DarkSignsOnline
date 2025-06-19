<?php

require_once('function.php');

print_returnwith();

$d = trim($_REQUEST['d']);
$uid = $user['id'];
$port = (int)$_REQUEST['port'];

$originaldomain = trim($d);
$dInfo = getDomainInfo($d);
if ($dInfo === false) {
    die_error('Domain does not exist.', 404);
}

if ($user['id'] !== $dInfo['owner']) {
    die_error('Restricted access.', 403);
}

$stmt = $db->prepare("DELETE FROM domain_scripts WHERE domain=? AND port=? AND ver=?;");
$stmt->bind_param('iii', $dInfo['id'], $port, $ver);
$stmt->execute();

if ($stmt->affected_rows) {
    die ("Port successfully closed.: " . strtoupper($originaldomain) . ":$port");
} else {
    die ("No script is active on this port.");
}
