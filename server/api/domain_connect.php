<?php

require_once('function.php');

print_returnwith('4100');

$port = (int)$_REQUEST['port'];

if ($port < 1 || $port > 65535) {
	die_error('not found', 400);
}

$d = $_REQUEST['d'];
$d = strtolower($d);
$dInfo = getDomainInfo($d);
if ($dInfo === false) {
	die_error('not found', 404);
}

$stmt = $db->prepare('SELECT code FROM domain_scripts WHERE domain = ? AND port = ? AND ver = ?;');
$stmt->bind_param('iii', $dInfo['id'], $port, $ver);
$stmt->execute();
$exists = $stmt->get_result();
$code_a = $exists->fetch_row();
if (empty($code_a)) {
	die_error('not found', 404);
}

switch ($ver) {
	case 1:
		echo '4100';
		$preamble = "\$serverdomain = \"$d\"\r\n\$serverip = \"$dInfo[ip]\"\r\n\$serverport = $port\r\n";
		$lines = explode("\r\n", $code_a[0]);
		foreach ($lines as $k => $v) {
			$v = preg_replace('/(fileserver\()/i', "\$1$dInfo[keycode], $d, ", $v);
			$v = preg_replace('/^(\s*SERVER )(WRITE |APPEND )/i', "\$1$dInfo[keycode]:---:$d:----:\$2", $v);
			$lines[$k] = $v;
		}
		echo $d . '_' . $port . '::' . dso_b64_encode($preamble . implode("\r\n", $lines));
		break;
	case 2:
		$dHost = $dInfo['host'];
		if (empty($dHost)) {
			$dHost = $dInfo['ip'];
		}
		echo $dHost . ':-:' . $port . ':-:' . $dInfo['ip'] . ':-:UID-' . $dInfo['owner'] . ':-:' . $dInfo['keycode'] . ':-:' . dso_b64_encode($code_a[0]);
		break;
	default:
		die_error('not found', 400);
}
