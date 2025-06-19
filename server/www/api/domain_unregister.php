<?php

require_once('function.php');

print_returnwith();

$d = strtolower(trim($_POST['d']));
$dInfo = getDomainInfo($d);

if ($dInfo === false) {
    die_error('Domain not found', 404);
}

if ($dInfo['owner'] !== $user['id']) {
    die_error('Domain not owned by user', 403);
}

$stmt = $db->prepare('DELETE FROM domains WHERE id=?');
$stmt->bind_param('i', $dInfo['id']);
$stmt->execute();

die('Domain unregistered');
