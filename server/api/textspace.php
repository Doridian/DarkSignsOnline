<?php

require_once('function.php');

$action = $_REQUEST['action'];

if ($action === 'download')
{
	$data = (int)$_REQUEST['data'];
	$stmt = $db->prepare('SELECT `text` FROM textspace WHERE chan = ? ORDER BY id DESC LIMIT 1');
	$stmt->bind_param('i', $data);
	$stmt->execute();
	$res = $stmt->get_result();
	$row = $res->fetch_array();

	if (empty($row)) {
		die_error('4501  ', 404);
	}

	die('4501'.$row['text']);
}

if ($action === 'upload')
{
	$chan = (int)$_REQUEST['chan'];
	if ($chan <= 1)
	{
		die_error('4500Invalid channel.', 400);
	}

	$data = $_REQUEST['data'];
	$time = time();

	$stmt = $db->prepare('INSERT INTO textspace (`chan`, `owner`, `lastupdate`, `text`, `deleted`) VALUES (?, ?, ?, ?, 0)');
	$stmt->bind_param('iiis', $chan, $user['id'], $time, $data);
	$stmt->execute();

	die("4500Updated: $chan!");
}
