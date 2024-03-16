<?php

$rewrite_done = true;
require_once ('function.php');

echo '2003';
	
$port = (int)$_POST['port'];
if ($port < 1 || $port > 65536)
{
	die("Error: Port number must be between 1 and 65536.");
}


$d = $_POST['d'];
$temp = getDomainInfo($d);

if ($temp[0] > 0)
{
	if ($user['id'] === $temp[1])
	{
		$code = $_POST['filedata'];

		$stmt = $db->prepare("INSERT INTO domainscripts VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE code=?, ip=?, time=?;");
		$time = time();
		$stmt->bind_param('iisssssi', $temp[0], $port, $code, $_SERVER['REMOTE_ADDR'], $time, $code, $_SERVER['REMOTE_ADDR'], $time);
		$stmt->execute();

		die('success');
	}
	else
	{
		die('Restricted access.');
	}
}
else
{
	die('Domain does not exist.');
}
