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
$code = $exists->fetch_row();
if (empty ($code)) {
	die ('not found');
}

echo $d . '_' . $port . '::' . $code[0];
