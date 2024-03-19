<?php

//----------------------------------------------------------------------------------------------------------
//NOTE - when modifying this script, consider that you may need to modify domain_download.php as well!!!
//----------------------------------------------------------------------------------------------------------

$rewrite_done = true;
require_once('function.php');
global $db;

$d = trim($_REQUEST['d']);
$dInfo = getDomainInfo($d);

function verify_keycode($filename) {
	global $db, $d, $dInfo, $user;
	$is_owner = $user['id'] === $dInfo[1];

	if ($is_owner) {
		$stmt = $db->prepare("SELECT * FROM domain_files WHERE domain = ? AND filename = ?");
		$stmt->bind_param('is', $dInfo[0], $filename);
	} else {
		$keycode = $_REQUEST['keycode'];
		$stmt = $db->prepare("SELECT * FROM domain_files WHERE domain = ? AND filename = ? AND keycode = ?");
		$stmt->bind_param('iss', $dInfo[0], $filename, $keycode);
	}
	$stmt->execute();
	$res = $stmt->get_result();
	$row = $res->fetch_array();

	if (empty($row)) {
		if ($is_owner) {
			return array('id' => -1, 'filename' => $filename, 'contents' => '');
		}
		die("2000Error - ($keycode) Invalid Server Key: " . strtoupper($d));
	}

	if (!$is_owner && strtoupper(substr($row['contents'], 0, 6)) !== 'PUBLIC') {
		die("2000Error - ($keycode) Private file: " . strtoupper($d));
	}

	return $row;
}

function write_file($file, $contents) {
	global $db;
	if ($file['id'] < 0) {
		$stmt = $db->prepare("INSERT INTO domain_files (domain, filename, keycode, contents) VALUES (?, ?, ?, ?)");
		$keycode = make_keycode();
		$stmt->bind_param('iss', $dInfo[0], $filename, $keycode, $contents);
	} else {
		$stmt = $db->prepare("UPDATE domain_files SET contents = ? WHERE id = ?");
		$stmt->bind_param('si', $contents, $id);
	}
	$stmt->execute();
}

$returnwith = $_REQUEST['returnwith'];
if (trim($returnwith) == "") {
	$returnwith = '2000';
}
echo $returnwith;

$write = $_REQUEST['write'];
if (!empty($write)) {
	$file = verify_keycode($write);
	$filedata = $_REQUEST['filedata'];
	write_file($file['id'], $filedata);
	exit;
}

$append = $_REQUEST['append'];
if (!empty($append)) {
	$file = verify_keycode($append);
	$filedata = $file['contents'] . $_REQUEST['filedata'];
	write_file($file['id'], $filedata);
	exit;
}

$downloadfile = $_REQUEST['downloadfile'];
if (!empty($downloadfile)) {
	$file = verify_keycode($fileserver);
	die($file['contents']);
}

$fileserver = $_REQUEST['fileserver'];
if (!empty($fileserver)) {
	$file = verify_keycode($fileserver);

	$maxlines = (int)$_REQUEST['maxlines'];
	$startline = (int)$_REQUEST['startline'];

	if ($startline <= 0) {
		$startline = 1;
	}

	if ($maxlines <= 0) {
		$maxlines = -1;
	}

	//now, get the lines that are required.
	$fdarray = explode('\n', $file['contents']);

	$endline = count($fdarray);
	if ($maxlines > 0) {
		$endline = ($startline - 1) + $maxlines;
	}

	for ($x = $startline - 1; $x < $endline && $x < count($fdarray); $x++) {
		echo $fdarray[$x] . '\n';
	}
	exit;
}
