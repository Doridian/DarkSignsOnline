<?php

$rewrite_done = true;
require_once("function.php");


$uid = $user['id'];
$returnwith = trim($returnwith);
$d = trim($_REQUEST['d']);

$filename = $_REQUEST['filename'];


if (trim($returnwith) == "") {
	$returnwith = "2000";
}
echo $returnwith;

$port = (int) $_REQUEST['port'];
if ($port < 1 || $port > 65536) {
	die ("Error: Port number must be between 1 and 65536.");
}

$dInfo = getDomainInfo($d);
if ($dInfo[0] <= 0) {
	die ("Domain does not exist.");
}

$stmt = $db->prepare("SELECT code FROM domain_scripts WHERE domain=? AND port=? AND owner=?");
$stmt->bind_param('iii', $dInfo[0], $port, $uid);
$stmt->execute();
$res = $stmt->get_result();
$row = $res->fetch_array();
if (!empty ($row)) {
	$row = $res->fetch_array();
	$script = $row['code'];

	$script = str_replace("\n", "*- -*", $script);
	$script = str_replace("\r", "", $script);
	die ("$filename:$script");
} else {
	die ("No Script Found: " . strtoupper($d) . ":$port");
}
