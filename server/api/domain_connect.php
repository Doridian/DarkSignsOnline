<?php

$rewrite_done = true;
require_once("function.php");

$ver = (int)$_REQUEST['ver'];
if ($ver < 1) {
	$ver = 1;
}

$port = (int)$_REQUEST['port'];

if ($port < 1 || $port > 65536) {
	die ('not found');
}
$d = $_REQUEST['d'];
$d = strtolower($d);
$dInfo = getDomainInfo($d);

if ($dInfo[0] <= 0) {
	die ('not found');
}

$stmt = $db->prepare("SELECT code FROM domain_scripts WHERE domain_id = ? AND port = ?");
$stmt->bind_param('ii', $dInfo[0], $port);
$stmt->execute();
$exists = $stmt->get_result();
$code_a = $exists->fetch_row();
if (empty($code_a)) {
	die('not found');
}

switch ($ver) {
	case 2:
		$params = $_REQUEST['params'];
		$preamble = 'Public Const ServerDomain = "' . $d . '"
Public Const ServerIP = "' . $dInfo[3] . '"
Public Const ServerPort = ' . $port . '
';
		echo $d . ':-:' . $port . ':-:' . $dInfo[2] . ':-:' . dso_b64_encode($preamble) . ':-:' . dso_b64_encode($code_a[0]);
		if (!empty($params)) {
			foreach ($params as $v) {
				echo ':-:' . dso_b64_encode($v);
			}
		}
		break;
	default:
		die('not found');
}

