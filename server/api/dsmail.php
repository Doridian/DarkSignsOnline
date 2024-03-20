<?php

$rewrite_done = true;
require_once('function.php');

$returnwith = (string)(int)$_REQUEST['returnwith'];
if ($returnwith === '0') {
	$returnwith = '7000';
}
echo $returnwith;

$action = $_REQUEST['action'];
if ($action == 'inbox')
{
	
	$last = (int)$_REQUEST['last'];
	$stmt = $db->prepare('SELECT id, from_user_tbl.username AS from_user, subject, message, time FROM dsmail WHERE to_user = ? LEFT JOIN users from_user_tbl ON users.id = dsmail.from_user AND id > ? ORDER BY id ASC');
	$stmt->bind_param('ii', $user['id'], $last);
	$stmt->execute();
	$result = $stmt->get_result();
	while ($mail = $result->fetch_array())
	{
		echo 'X_'.$mail['id'].chr(7).$mail['from_user'].chr(7).$mail['subject'].chr(7).$mail['message'].chr(7).$mail['time']."\n";
	}
	exit;
}
else if ($action == 'send')
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
		if ($tmpID == -1)
		{
			die('Unknown name: '.$name);
		}
		else
		{
			array_push($nameID, $tmpID);
		}				
	}

	$sub = preg_replace("[^a-zA-Z0-9., \-]", "", $_REQUEST['subject']);
	$msg = preg_replace("[^a-zA-Z0-9., ".chr(6)."\-]", "", $_REQUEST['message']);
	$time = time();

	foreach ($nameID as $id)
	{
		$stmt = $db->prepare("INSERT INTO dsmail (from_user, to_user, subject, message, time) VALUES (?, ?, ?, ?, ?)");
		$stmt->bind_param('iissi', $user['id'], $id, $sub, $msg, $time);
		$stmt->execute();
	}
	die('success');
}

die('No request sent');
