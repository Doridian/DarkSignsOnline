<?php

$rewrite_done = true;
require_once('function.php');

$returnwith = (string)(int)$_REQUEST['returnwith'];
if ($returnwith === '0') {
	$returnwith = '7000';
}
echo $returnwith;

$action = $_REQUEST['action'];
if ($action === 'inbox')
{
	$last = (int)$_REQUEST['last'];
	$stmt = $db->prepare('SELECT dsmail.id AS id, from_user_tbl.username AS from_user, dsmail.subject AS subject, dsmail.message AS message, dsmail.time AS time FROM dsmail LEFT JOIN users from_user_tbl ON from_user_tbl.id = dsmail.from_user WHERE dsmail.to_user = ? AND dsmail.id > ? ORDER BY dsmail.id ASC');
	$stmt->bind_param('ii', $user['id'], $last);
	$stmt->execute();
	$result = $stmt->get_result();
	while ($mail = $result->fetch_assoc())
	{
		echo 'X_'.$mail['id'].chr(7).$mail['from_user'].chr(7).$mail['subject'].chr(7).$mail['message'].chr(7).$mail['time']."\r\n";
	}
	exit;
}
/*else if ($action === 'outbox')
{
	$last = (int)$_REQUEST['last'];
	$stmt = $db->prepare('SELECT dsmail.id AS id, to_user_tbl.username AS to_user, dsmail.subject AS subject, dsmail.message AS message, dsmail.time AS time FROM dsmail LEFT JOIN users to_user_tbl ON to_user_tbl.id = dsmail.to_user WHERE dsmail.from_user = ? AND dsmail.id > ? ORDER BY dsmail.id ASC');
	$stmt->bind_param('ii', $user['id'], $last);
	$stmt->execute();
	$result = $stmt->get_result();
	while ($mail = $result->fetch_assoc())
	{
		echo 'X_'.$mail['id'].chr(7).$mail['to_user'].chr(7).$mail['subject'].chr(7).$mail['message'].chr(7).$mail['time']."\r\n";
	}
	exit;
}*/
else if ($action === 'send')
{
	$from = $user['id'];
	$to = $_REQUEST['to'];
	$toArr = explode(',', $to);
	
	if (sizeof($toArr) > 10)
	{
		die('Cant send mail to more than 10 people.');
	}
	
	$nameID = [];
	foreach ($toArr as $name)
	{
		$tmpID = userToId($name);
		if ($tmpID === -1)
		{
			die('Unknown name: '.$name);
		}
		array_push($nameID, $tmpID);
	}

	$sub = preg_replace("[^a-zA-Z0-9., \-]", "", $_REQUEST['subject']);
	$msg = preg_replace("[^a-zA-Z0-9., ".chr(6)."\-]", "", $_REQUEST['message']);
	$time = time();

	foreach ($nameID AS $id)
	{
		$stmt = $db->prepare("INSERT INTO dsmail (from_user, to_user, subject, message, time) VALUES (?, ?, ?, ?, ?)");
		$stmt->bind_param('iissi', $user['id'], $id, $sub, $msg, $time);
		$stmt->execute();
	}
	die('success');
}

die('No request sent');
