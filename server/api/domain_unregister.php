<?php

$rewrite_done = true;
require_once("function.php");

$returnwith = (string)(int)$_REQUEST['returnwith'];
if ($returnwith === '0') {
    $returnwith = '2000';
}
echo $returnwith;

if ($_POST['pw'] !== $_SERVER['PHP_AUTH_PW']) {
    die('Invalid password');
}

$domain = $_POST['d'];
$dInfo = getDomainInfo($domain);

if ($dInfo[0] < 0) {
    die('Domain not found');
}

if ($dInfo[1] !== $user['id']) {
    die('Domain not owned by user');
}

$stmt = $db->prepare("DELETE FROM domain WHERE id=?");
$stmt->bind_param('i', $dInfo[0]);
$stmt->execute();
$stmt->close();
die('Domain unregistered');
