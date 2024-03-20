<?php

$rewrite_done = true;
require_once('function.php');

$returnwith = (string)(int)$_GET['returnwith'];
if ($returnwith === '0') {
	$returnwith = '2000';
}
echo $returnwith;

$d = trim($_REQUEST['d']);
$dInfo = getDomainInfo($d);

if ($dInfo[0] <= 0) {
	die('not found');
}

$owner_id = $dInfo[1];
$date_formatted = date('Y-m-d H:i:s', $dInfo[4]);

$stmt = $db->prepare('SELECT username FROM users WHERE id=?');
$stmt->bind_param('i', $owner_id);
$stmt->execute();
$res = $stmt->get_result();
$row = $res->fetch_array();
$owner = $row['username'];

echo "$d was created by $owner on $date_formatted";
