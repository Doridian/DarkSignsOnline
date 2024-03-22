<?php

$rewrite_done = true;
require_once("function.php");

$ver = (int)$_REQUEST['ver'];
if ($ver < 1) {
	$ver = 1;
}

$port = (int)$_REQUEST['port'];

if ($port < 1 || $port > 65535) {
	die ('not found');
}

$d = $_REQUEST['d'];
$d = strtolower($d);
$dInfo = getDomainInfo($d);

if ($dInfo[0] <= 0) {
	die ('not found');
}

$stmt = $db->prepare("SELECT code FROM domain_scripts WHERE domain_id = ? AND port = ? AND ver = ?;");
$stmt->bind_param('iii', $dInfo[0], $port, $ver);
$stmt->execute();
$exists = $stmt->get_result();
$code_a = $exists->fetch_row();
if (empty($code_a)) {
	die('not found');
}

switch ($ver) {
	case 1:
		echo '4100';
		$preamble = "\$serverdomain = \"$d\"\r\n\$serverip = \"$dInfo[3]\"\r\n\$serverport = $port\r\n";
		$lines = explode("\r\n", $code_a[0]);
		foreach ($lines as $k => $v) {
			$v = preg_replace('/(fileserver\()/i', "\$1$dInfo[2], $d, ", $v);
			$v = preg_replace('/^(\s*SERVER )(WRITE |APPEND )/i', "\$1$dInfo[2]:---:$d:----:\$2", $v);
			$lines[$k] = $v;
		}
		echo $d . '_' . $port . '::' . dso_b64_encode($preamble . implode("\r\n", $lines));
		break;
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

