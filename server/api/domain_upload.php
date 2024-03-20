<?php

$rewrite_done = true;
require_once("function.php");

echo '2003';
	
$port = (int)$_POST['port'];
if ($port < 1 || $port > 65536)
{
	die("Error: Port number must be between 1 and 65536.");
}


$d = $_POST['d'];
$dInfo = getDomainInfo($d);

if ($dInfo[0] > 0)
{
	if ($user['id'] === $dInfo[1])
	{
		$code = dso_b64_decode(line_endings_to_dos($_POST['filedata']));
		$stmt = $db->prepare("INSERT INTO domain_scripts VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE code=?, ip=?, time=?;");
		$time = time();
		$stmt->bind_param('iisssssi', $dInfo[0], $port, $code, $_SERVER['REMOTE_ADDR'], $time, $code, $_SERVER['REMOTE_ADDR'], $time);
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
