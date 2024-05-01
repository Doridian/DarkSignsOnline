<?php

require_once('function.php');

if ($ver < 2) {
	echo '2003';
}

$port = (int)$_POST['port'];
if ($port < 1 || $port > 65535)
{
	die_error('Port number must be between 1 and 65535.');
}

$d = $_POST['d'];
$dInfo = getDomainInfo($d);

if ($dInfo === false) {
	die_error('Domain does not exist.', 404);
}

if ($user['id'] !== $dInfo['owner']) {
	die_error('Restricted access.', 403);
}

$code = line_endings_to_dos(dso_b64_decode($_POST['filedata']));
$stmt = $db->prepare('INSERT INTO domain_scripts (domain, port, code, ip, time, ver) VALUES (?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE code=?, ip=?, time=?;');
$time = time();
$stmt->bind_param('iissiissi', $dInfo['id'], $port, $code, $_SERVER['REMOTE_ADDR'], $time, $ver, $code, $_SERVER['REMOTE_ADDR'], $time);
$stmt->execute();

die('success');
