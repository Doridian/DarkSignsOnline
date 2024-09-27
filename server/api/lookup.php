<?php

require_once('function.php');

print_returnwith();

$d = trim($_REQUEST['d']);
$dInfo = getDomainInfo($d);
if ($dInfo === false) {
    die('not found');
}

$owner_id = $dInfo['owner'];
$date_formatted = date('Y-m-d H:i:s', $dInfo['time']);
$owner = idToUser($owner_id);

echo "$d was created by $owner on $date_formatted";
