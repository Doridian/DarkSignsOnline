<?php

$rewrite_done = true;
require_once 'function.php';

echo '4100';

$port = (int) $_REQUEST['port'];

if ($port < 1 || $port > 65536) {
	die ('not found');
}
$d = $_REQUEST['d'];
$d = strtolower($d);
$temp = getDomainInfo($d);

if ($temp[0] <= 0) {
	die ('not found');
}

$stmt = $db->prepare("SELECT code FROM domainscripts WHERE domain_id = ? AND port = ?");
$stmt->bind_param('ii', $temp[0], $port);
$stmt->execute();
$exists = $stmt->get_result();
$code_a = $exists->fetch_row();
if (empty($code_a)) {
	die('not found');
}
$code = $code_a[0];
// Edit code as necessary here
echo $d . '_' . $port . '::' . dso_b64_encode($code);
