<?php

$rewrite_done = true;
require_once('function.php');

$action = $_REQUEST['action'];

$download = $_REQUEST['download'];
if (!empty($download)) {
	$download_int = (int)$download;
	if ($download_int < 1) {
		die_error('4501', 404);
	}

	$stmt = $db->prepare('SELECT `text` FROM textspace WHERE chan = ? ORDER BY id DESC LIMIT 1');
	$stmt->bind_param('i', $download_int);
	$stmt->execute();
	$res = $stmt->get_result();
	$row = $res->fetch_array();

	if (empty($row)) {
		die('4501');
	}

	die('4501'.$row['text']);
}

$upload = $_REQUEST['upload'];
if (!empty($upload)) {
	$upload_int = (int)$upload;
	if ($upload_int <= 1) {
		die_error('4500Invalid channel.', 400);
	}

	$data = $_REQUEST['data'];
	$time = time();

	$stmt = $db->prepare('INSERT INTO textspace (`chan`, `owner`, `lastupdate`, `text`, `deleted`) VALUES (?, ?, ?, ?, 0)') or die($db->error);
	$stmt->bind_param('iiis', $upload_int, $user['id'], $time, $data);
	$stmt->execute() or die($db->error);

	die("4500Updated: $upload_int!");
}

die_error('4500Invalid action.', 400);
