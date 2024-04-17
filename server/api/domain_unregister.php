<?php

require_once('function.php');

print_returnwith();

$d = strtolower(trim($_POST['d']));
$dInfo = getDomainInfo($d);

if ($dInfo[0] < 0) {
    die_error('Domain not found', 404);
}

if ($dInfo[1] !== $user['id']) {
    die_error('Domain not owned by user', 403);
}

$stmt = $db->prepare('DELETE FROM domain WHERE id=?');
$stmt->bind_param('i', $dInfo[0]);
$stmt->execute();

$stmt = $db->prepare('DELETE FROM iptable WHERE id=?');
$stmt->bind_param('i', $dInfo[0]);
$stmt->execute();

die('Domain unregistered');
