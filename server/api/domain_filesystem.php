<?php

//----------------------------------------------------------------------------------------------------------
//NOTE - when modifying this script, consider that you may need to modify domain_download.php as well!!!
//----------------------------------------------------------------------------------------------------------

$rewrite_done = true;
require_once("function.php");
global $db;

$d = trim($_REQUEST['d']);
$dInfo = getDomainInfo($d);

function verify_keycode($filename) {
	global $db, $d, $dInfo, $user;
	$is_owner = $user['id'] === $dInfo[1];

	$keycode = $_REQUEST['keycode'];
	if ($keycode !== $dInfo[2]) {
		die("2000Error - ($filename) Invalid Server Key: " . strtoupper($d));
	}

	$stmt = $db->prepare("SELECT * FROM domain_files WHERE domain = ? AND filename = ?");
	$stmt->bind_param('is', $dInfo[0], $filename);
	$stmt->execute();
	$res = $stmt->get_result();
	$row = $res->fetch_array();

	if (!$is_owner) {
		if (empty($row)) {
			die("2000Error - ($filename) File not found: " . strtoupper($d));
		}
		if(strtoupper(substr($row['contents'], 0, 6)) !== 'PUBLIC') {
			die("2000Error - ($filename) Private file: " . strtoupper($d));
		}
	}

	if (empty($row)) {
		return array('id' => -1, 'filename' => $filename, 'contents' => '');
	}
	return $row;
}

function write_file($file_id, $filename, $contents) {
	global $db, $dInfo;
	if (strlen($contents) === 0) {
		if ($file_id < 0) {
			return;
		}
		$stmt = $db->prepare("DELETE FROM domain_files WHERE id = ?");
		$stmt->bind_param('i', $file_id);
	} else if ($file_id < 0) {
		$stmt = $db->prepare("INSERT INTO domain_files (domain, filename, contents) VALUES (?, ?, ?)");
		$stmt->bind_param('iss', $dInfo[0], $filename, $contents);
	} else {
		$stmt = $db->prepare("UPDATE domain_files SET contents = ? WHERE id = ?");
		$stmt->bind_param('si', $contents, $file_id);
	}

	$stmt->execute();
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
	$fdarray = explode("\r\n", $file['contents']);

	$endline = count($fdarray);
	if ($maxlines > 0) {
		$endline = ($startline - 1) + $maxlines;
	}

	for ($x = $startline - 1; $x < $endline && $x < count($fdarray); $x++) {
		echo $fdarray[$x] . "\r\n";
	}
	exit;
}

$returnwith = $_REQUEST['returnwith'];
if (trim($returnwith) == "") {
	$returnwith = '2000';
}
echo $returnwith;

$write = $_REQUEST['write'];
if (!empty($write)) {
	$file = verify_keycode($write);
	$filedata = line_endings_to_dos($_REQUEST['filedata']);
	write_file($file['id'], $write, $filedata);
	exit;
}

$append = $_REQUEST['append'];
if (!empty($append)) {
	$file = verify_keycode($append);
	$filedata = $file['contents'] . line_endings_to_dos($_REQUEST['filedata']);
	write_file($file['id'], $append, $filedata);
	exit;
}

$downloadfile = $_REQUEST['downloadfile'];
if (!empty($downloadfile)) {
	$file = verify_keycode($fileserver);
	die($file['contents']);
}
