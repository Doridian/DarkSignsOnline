<?php

$rewrite_done = true;
include_once "function.php";

$returnwith = (string) (int) $_GET['returnwith'];
$d = trim($_REQUEST['d']);
if (trim($returnwith) == "0") {
	$returnwith = "2000";
}
echo $returnwith;

$uid = $user['id'];
$port = (int) $_REQUEST['port'];
if ($port < 1 || $port > 65536) {
	die ("Error: Port number must be between 1 and 65536.");
}

//----------------------------------------------------------------------------------------------------------
//NOTE - when modifying this script, consider that you may need to modify domain_download.php as well!!!
//----------------------------------------------------------------------------------------------------------

$originaldomain = trim($d);
$temp = getDomainInfo($d);

if ($temp[0] <= 0) {
	die ("Domain does not exist.");
}

$stmt = $db->prepare("DELETE FROM domainscripts WHERE domain=? AND port=? AND owner=?;");
$stmt->bind_param('iii', $temp[0], $port, $uid);
$stmt->execute();

if ($stmt->affected_rows) {
	die ("Port successfully closed.: " . strtoupper($originaldomain) . ":$port");
} else {
	die ("No script is active on this port.");
}
