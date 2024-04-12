<?php

require_once('function.php');

$action = $_REQUEST['action'];
if ($action == 'download')
{
	$data = $_REQUEST['data'];
	$result = $db->query("SELECT `text` FROM textspace WHERE chan='$data' ORDER BY rev DESC LIMIT 1") or die($db->error);;
	if ($db->num_rows($result) == 1)
	{
		die('4501'.$db->result($result, 0));
	}
	die_error('4501  ', 404);
}

if ($action == 'upload')
{
	$chan = (int)$_REQUEST['chan'];
	if ($chan <= 1)
	{
		die_error('4500Invalid channel.', 400);
	}

	$data = $_REQUEST['data'];
	$time = time();
	$result = $db->query("SELECT rev FROM textspace WHERE chan=$chan ORDER BY rev DESC LIMIT 1");
	if ($db->num_rows($result) == 0)
	{
		$result = $db->query("INSERT INTO textspace (`rev`, `chan`, `user`, `lastupdate`, `text`, `active`) VALUES (1, $chan, $user[id], $time, '$data', 1)") or die('X '.$db->error.' (B)');
	}
	else
	{
		$rev = $db->result($result, 0)+1;
		$result = $db->query("INSERT INTO textspace (`rev`, `chan`, `user`, `lastupdate`, `text`) VALUES ($rev, $chan, $user[id], $time, '$data')") or die('X '.$db->error.' (C)');
		
	}
	
	die("4500Updated: $chan!");
}
