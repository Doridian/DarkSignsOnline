<?php

$rewrite_done = true;
require_once('function.php');

print_returnwith();

$d = trim($_REQUEST['d']);
$dInfo = getDomainInfo($d);

if ($dInfo[0] <= 0) {
	die('not found');
}

$owner_id = $dInfo[1];
$date_formatted = date('Y-m-d H:i:s', $dInfo[4]);
$owner = idToUser($owner_id);

echo "$d was created by $owner on $date_formatted";
