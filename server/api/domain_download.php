<?php

require_once("function.php");


$uid = $user['id'];
$d = trim($_REQUEST['d']);
$port = (int)$_REQUEST['port'];

$filename = $_REQUEST['filename'];

print_returnwith();

$dInfo = getDomainInfo($d);
if ($dInfo === false) {
	die('Domain does not exist.');
}

$stmt = $db->prepare('SELECT code FROM domain_scripts WHERE domain=? AND port=? AND owner=? AND ver=?');
$stmt->bind_param('iiii', $dInfo['id'], $port, $uid, $ver);
$stmt->execute();
$res = $stmt->get_result();
$row = $res->fetch_assoc();
if (!empty($row)) {
	$script = $row['code'];
	die("$filename:$script");
} else {
	die("No Script Found: " . strtoupper($d) . ":$port");
}
