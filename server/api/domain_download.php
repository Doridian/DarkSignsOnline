<?php

$rewrite_done = true;
require_once("function.php");


$uid = $user['id'];
$d = trim($_REQUEST['d']);
$port = (int)$_REQUEST['port'];

$filename = $_REQUEST['filename'];

print_returnwith();

$dInfo = getDomainInfo($d);
if ($dInfo[0] <= 0) {
	die('Domain does not exist.');
}

$stmt = $db->prepare('SELECT code FROM domain_scripts WHERE domain=? AND port=? AND owner=? AND ver = ?');
$stmt->bind_param('iiii', $dInfo[0], $port, $uid, $ver);
$stmt->execute();
$res = $stmt->get_result();
$row = $res->fetch_assoc();
if (!empty($row)) {
	$script = $row['code'];

	$script = str_replace("\n", "*- -*", $script);
	$script = str_replace("\r", "", $script);
	die("$filename:$script");
} else {
	die("No Script Found: " . strtoupper($d) . ":$port");
}
