<?php

$rewrite_done = true;
require_once('function.php');

print_returnwith();

$d = trim($_REQUEST['d']);
$uid = $user['id'];
$port = (int)$_REQUEST['port'];

$originaldomain = trim($d);
$dInfo = getDomainInfo($d);
if ($dInfo[0] <= 0) {
	die ("Domain does not exist.");
}

$stmt = $db->prepare("DELETE FROM domain_scripts WHERE domain=? AND port=? AND owner=? AND ver=?;");
$stmt->bind_param('iiii', $dInfo[0], $port, $uid, $ver);
$stmt->execute();

if ($stmt->affected_rows) {
	die ("Port successfully closed.: " . strtoupper($originaldomain) . ":$port");
} else {
	die ("No script is active on this port.");
}
