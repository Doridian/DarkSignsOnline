<?php

$rewrite_done = true;
require_once 'function.php';

echo '4100';

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
$code = $code_a[0];
$lines = explode("\n", $code);

foreach ($lines as $k => $v) {
	$v = preg_replace('/(fileserver\()/i', "\$1$dInfo[2], $d, ", $v);
	$v = preg_replace('/^(\s+SERVER )(WRITE | APPEND )/i', "\$1$dInfo[2]:---:$d:----:\$2", $v);
	$lines[$k] = $v;
}

echo $d . '_' . $port . '::' . dso_b64_encode(implode("\n", $lines));
