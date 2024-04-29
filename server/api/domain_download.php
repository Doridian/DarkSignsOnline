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

if ($user['id'] !== $dInfo['owner']) {
	die_error('Restricted access.', 403);
}

$stmt = $db->prepare('SELECT code FROM domain_scripts WHERE domain=? AND port=? AND ver=?');
$stmt->bind_param('iii', $dInfo['id'], $port, $ver);
$stmt->execute();
$res = $stmt->get_result();
$row = $res->fetch_assoc();
if (!empty($row)) {
	$script = $row['code'];
	die("$filename:$script");
} else {
	die("No Script Found: " . strtoupper($d) . ":$port");
}
